#include "WindowsServer.h"

namespace msime::windows {
WindowsServer::WindowsServer(WindowsServerOptions options,
                             std::string host_options,
                             SessionPump::KeyHandler key,
                             SessionPump::EventHandler event,
                             SessionPump::Presentation presentation)
    : inbox_(options.registration_capacity) {
  if (!options.pipes.max_clients || options.pipes.max_clients > 64 ||
      !options.input_capacity || options.input_capacity > 4096 ||
      !options.write_timeout || options.write_timeout == INFINITE || !key ||
      !event)
    throw std::invalid_argument("Invalid Windows server configuration");
  // The inbox exists before listeners start. Early main handshakes can enqueue
  // tickets while the transport/queue/controller are still being constructed.
  service_ = std::make_unique<PipeService>(
      options.pipes,
      [this](uint32_t role, const PipeRegistration &registration) {
        if (registration.status != RegistryStatus::Ready)
          return false;
        return role == FanyImePipeRole::Main ? inbox_.push(registration.ticket)
                                             : !inbox_.closed();
      });
  transport_ = std::make_unique<PipeMainTransport>(service_->registry(),
                                                   options.write_timeout);
  controller_ = std::make_unique<SessionController>(
      *transport_, inbox_, options.pipes.max_clients, options.input_capacity,
      std::move(host_options), std::move(key), std::move(event),
      [this] { return service_->failure() == ERROR_SUCCESS; },
      [this] { service_->stop(); }, std::chrono::milliseconds(100),
      std::move(options.preferences_directory), std::move(presentation),
      std::move(options.preferences_published));
  if (!options.aux_pipe_name.empty()) {
    aux_ = std::make_unique<AuxPipeService>(
        std::move(options.aux_pipe_name), std::move(options.aux_message));
  }
}
WindowsServer::~WindowsServer() { stop(); }

void WindowsServer::request_stop() {
  if (aux_)
    aux_->request_stop();
  if (controller_)
    controller_->request_stop();
}

void WindowsServer::stop() {
  if (aux_)
    aux_->stop();
  if (controller_)
    controller_->stop();
}
} // namespace msime::windows
