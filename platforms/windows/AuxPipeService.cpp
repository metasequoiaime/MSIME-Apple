#include "AuxPipeService.h"
#include "PipeIo.h"
#include <stdexcept>
#include <system_error>

namespace msime::windows {
namespace {
constexpr DWORD max_aux_message_bytes = 4 * 1024;
}

AuxPipeService::AuxPipeService(std::wstring name, Message message,
                               DWORD operation_timeout)
    : message_(std::move(message)), operation_timeout_(operation_timeout) {
  if (name.empty() || !message_ || !operation_timeout_ ||
      operation_timeout_ == INFINITE)
    throw std::invalid_argument("Invalid auxiliary pipe configuration");
  DWORD error = ERROR_SUCCESS;
  listener_ = PipeListener::create(name, error);
  if (!listener_)
    throw std::system_error(static_cast<int>(error), std::system_category(),
                            "Create auxiliary pipe listener");
  cancel_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!cancel_) {
    listener_.reset();
    throw std::system_error(static_cast<int>(GetLastError()),
                            std::system_category(),
                            "Create auxiliary pipe cancellation event");
  }
  try {
    thread_ = std::thread([this] { listen(); });
  } catch (...) {
    CloseHandle(cancel_);
    cancel_ = nullptr;
    listener_.reset();
    throw;
  }
}

AuxPipeService::~AuxPipeService() {
  stop();
  if (cancel_)
    CloseHandle(cancel_);
}

void AuxPipeService::request_stop() {
  if (cancel_)
    SetEvent(cancel_);
}

void AuxPipeService::stop() {
  std::lock_guard lock(stop_mutex_);
  request_stop();
  if (thread_.joinable())
    thread_.join();
  listener_.reset();
}

void AuxPipeService::listen() {
  try {
    while (WaitForSingleObject(cancel_, 0) == WAIT_TIMEOUT) {
      auto accepted = listener_->accept(operation_timeout_, cancel_);
      if (!accepted.io.complete()) {
        if (accepted.io.status == IoStatus::Timeout)
          continue;
        if (accepted.io.status == IoStatus::Cancelled)
          return;
        failure_.store(accepted.io.system_error ? accepted.io.system_error
                                                : ERROR_GEN_FAILURE);
        request_stop();
        return;
      }
      const auto received =
          read_message(accepted.connection->handle(), max_aux_message_bytes,
                       operation_timeout_, cancel_);
      if (received.complete())
        message_(received.frame);
      if (received.status == IoStatus::Cancelled)
        return;
    }
  } catch (...) {
    failure_.store(ERROR_UNHANDLED_EXCEPTION);
    request_stop();
  }
}
} // namespace msime::windows
