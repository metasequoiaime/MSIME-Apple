#include "AuxListener.h"
#include "PipeIo.h"
#include "PipeListener.h"

namespace msime::windows {
namespace {
// One message per connection, read with a short deadline so a client that
// connects and never writes cannot hold the single instance.
constexpr DWORD aux_read_timeout_ms = 200;
constexpr DWORD aux_accept_slice_ms = 1000;
constexpr DWORD aux_backoff_ms = 20;
} // namespace

std::unique_ptr<AuxListener> AuxListener::create(const std::wstring &name,
                                                 Sink sink, DWORD &error,
                                                 MessageSink message_sink) {
  error = ERROR_SUCCESS;
  if (!sink) {
    error = ERROR_INVALID_PARAMETER;
    return nullptr;
  }
  auto listener = PipeListener::create(name, error);
  if (!listener)
    return nullptr;
  std::unique_ptr<AuxListener> aux(new AuxListener());
  aux->cancel_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!aux->cancel_) {
    error = GetLastError();
    return nullptr;
  }
  aux->listener_ = std::move(listener);
  aux->sink_ = std::move(sink);
  aux->message_sink_ = std::move(message_sink);
  aux->worker_ = std::thread([raw = aux.get()] { raw->run(); });
  return aux;
}

AuxListener::~AuxListener() {
  stop();
  if (cancel_)
    CloseHandle(cancel_);
}

void AuxListener::request_stop() {
  if (cancel_)
    SetEvent(cancel_);
}

void AuxListener::stop() {
  std::lock_guard<std::mutex> lock(stop_mutex_);
  request_stop();
  if (worker_.joinable())
    worker_.join();
}

AuxStats AuxListener::stats() const {
  std::lock_guard<std::mutex> lock(stats_mutex_);
  return stats_;
}

void AuxListener::run() {
  while (WaitForSingleObject(cancel_, 0) != WAIT_OBJECT_0) {
    auto accepted = listener_->accept(aux_accept_slice_ms, cancel_);
    if (accepted.io.status == IoStatus::Timeout)
      continue;
    if (accepted.io.status == IoStatus::Cancelled)
      return;
    if (!accepted.io.complete() || !accepted.connection) {
      // A client can disappear before accept finishes; that is ordinary, so
      // back off briefly rather than treating it as a hard failure.
      if (accepted.io.system_error == ERROR_NO_DATA ||
          accepted.io.system_error == ERROR_PIPE_NOT_CONNECTED) {
        if (WaitForSingleObject(cancel_, aux_backoff_ms) != WAIT_TIMEOUT)
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
    const auto message =
        read_message(accepted.connection->handle(),
                     static_cast<DWORD>(max_aux_message_bytes),
                     aux_read_timeout_ms, cancel_);
    if (message.status == IoStatus::Cancelled)
      return;
    if (!message.complete()) {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.malformed;
      continue;
    }
    const auto text =
        aux_text_from_bytes(message.frame.data(), message.frame.size());
    if (!text) {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.malformed;
      continue;
    }
    if (message_sink_)
      message_sink_(*text);
    const auto click = parse_aux_langbar_right_click(*text);
    if (!click) {
      // The other Aux verbs are not this listener's business; drop them without
      // acknowledgement rather than pretending to have acted on them.
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.unknown_verb;
      continue;
    }
    {
      std::lock_guard<std::mutex> lock(stats_mutex_);
      ++stats_.dispatched;
    }
    sink_(tray_menu_anchor(*click));
  }
}
} // namespace msime::windows
