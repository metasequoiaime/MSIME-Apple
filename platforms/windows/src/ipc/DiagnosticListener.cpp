#include "DiagnosticListener.h"
#include "PipeIo.h"
#include "PipeListener.h"

namespace msime::windows {
namespace {
// One batch per connection, read with a short deadline so a TIP that connects
// and never writes cannot hold the single instance.
constexpr DWORD diagnostic_read_timeout_ms = 200;
constexpr DWORD diagnostic_accept_slice_ms = 1000;
constexpr DWORD diagnostic_backoff_ms = 20;
} // namespace

std::unique_ptr<DiagnosticListener>
DiagnosticListener::create(const std::wstring &name, Sink sink, DWORD &error) {
  error = ERROR_SUCCESS;
  if (!sink) {
    error = ERROR_INVALID_PARAMETER;
    return nullptr;
  }
  auto listener = PipeListener::create(name, error);
  if (!listener)
    return nullptr;
  std::unique_ptr<DiagnosticListener> diagnostics(new DiagnosticListener());
  diagnostics->cancel_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!diagnostics->cancel_) {
    error = GetLastError();
    return nullptr;
  }
  diagnostics->listener_ = std::move(listener);
  diagnostics->sink_ = std::move(sink);
  diagnostics->worker_ =
      std::thread([raw = diagnostics.get()] { raw->run(); });
  return diagnostics;
}

DiagnosticListener::~DiagnosticListener() {
  stop();
  if (cancel_)
    CloseHandle(cancel_);
}

void DiagnosticListener::request_stop() {
  if (cancel_)
    SetEvent(cancel_);
}

void DiagnosticListener::stop() {
  std::lock_guard<std::mutex> lock(stop_mutex_);
  request_stop();
  if (worker_.joinable())
    worker_.join();
}

DiagnosticListener::Stats DiagnosticListener::stats() const {
  std::lock_guard<std::mutex> lock(stats_mutex_);
  return stats_;
}

void DiagnosticListener::run() {
  while (WaitForSingleObject(cancel_, 0) != WAIT_OBJECT_0) {
    auto accepted = listener_->accept(diagnostic_accept_slice_ms, cancel_);
    if (accepted.io.status == IoStatus::Timeout)
      continue;
    if (accepted.io.status == IoStatus::Cancelled)
      return;
    if (!accepted.connection) {
      // A client that closed between connect and accept is ordinary; back off
      // briefly rather than treating it as a hard failure.
      if (accepted.io.system_error == ERROR_NO_DATA ||
          accepted.io.system_error == ERROR_PIPE_NOT_CONNECTED) {
        if (WaitForSingleObject(cancel_, diagnostic_backoff_ms) != WAIT_TIMEOUT)
          return;
        continue;
      }
      // Anything else would spin; latch it and leave the endpoint closed.
      failure_.store(accepted.io.system_error ? accepted.io.system_error
                                              : ERROR_GEN_FAILURE);
      return;
    }
    {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.accepted;
    }
    const auto message = read_message(
        accepted.connection->handle(),
        static_cast<DWORD>(FANY_IME_TSF_DIAGNOSTIC_MAX_FRAME_BYTES),
        diagnostic_read_timeout_ms, cancel_);
    if (message.status == IoStatus::Cancelled)
      return;
    if (!message.complete()) {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.malformed;
      continue;
    }
    const auto batch =
        parse_diagnostic_batch(message.frame.data(), message.frame.size());
    if (!batch) {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.malformed;
      continue;
    }
    {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.batches;
      stats_.dropped_records += batch->dropped_count;
    }
    try {
      sink_(*batch);
    } catch (...) {
      // A sink that throws must not take the endpoint down with it: the next
      // batch is still worth collecting.
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.malformed;
    }
  }
}
} // namespace msime::windows
