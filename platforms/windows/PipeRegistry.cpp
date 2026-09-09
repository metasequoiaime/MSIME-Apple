#include "PipeRegistry.h"
#include "MainFrame.h"
#include "ReplyCodec.h"
#include <cstring>
#include <limits>

namespace msime::windows {
namespace {
IoResult stale() {
  return {IoStatus::Cancelled, ERROR_OPERATION_ABORTED, 0, false, {}};
}
} // namespace
struct PipeRegistry::Endpoint {
  std::unique_ptr<PipeConnection> connection;
  std::shared_ptr<PipePeer> peer;
  uint64_t generation = 0;
  HANDLE cancel = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  std::mutex read_mutex;
  ~Endpoint() {
    if (cancel)
      CloseHandle(cancel);
  }
  void stop() { SetEvent(cancel); }
};
struct PipeRegistry::Client {
  std::mutex mutex;
  bool retired = false;
  std::array<std::shared_ptr<Endpoint>, 3> endpoints;
  void clear(uint32_t role) {
    if (endpoints[role])
      endpoints[role]->stop();
    endpoints[role].reset();
  }
};
uint64_t PipeRegistry::next_generation() {
  std::lock_guard lock(mutex_);
  if (stopped_ || next_generation_ == std::numeric_limits<uint64_t>::max())
    return 0;
  return ++next_generation_;
}
std::shared_ptr<PipeRegistry::Client> PipeRegistry::lookup(uint64_t id,
                                                           bool create) {
  std::lock_guard lock(mutex_);
  if (stopped_ || !id)
    return {};
  auto it = clients_.find(id);
  if (it != clients_.end())
    return it->second;
  if (!create || clients_.size() >= max_clients_)
    return {};
  auto client = std::make_shared<Client>();
  clients_.emplace(id, client);
  return client;
}
// Called with Client::mutex held. lookup never waits for a client mutex while
// holding the map mutex, and shutdown releases the map lock before stopping
// I/O.
void PipeRegistry::retire(uint64_t id, const std::shared_ptr<Client> &client) {
  for (const auto &endpoint : client->endpoints)
    if (endpoint)
      return;
  client->retired = true;
  std::lock_guard lock(mutex_);
  auto it = clients_.find(id);
  if (it != clients_.end() && it->second == client)
    clients_.erase(it);
}
PipeTicket PipeRegistry::ticket(uint64_t id, const Client &client) {
  PipeTicket result;
  result.client = id;
  for (size_t i = 0; i < 3; ++i)
    if (client.endpoints[i])
      result.generations[i] = client.endpoints[i]->generation;
  return result;
}
bool PipeRegistry::current(const PipeTicket &value, const Client &client) {
  if (client.retired || !client.endpoints[0] || !client.endpoints[1] ||
      !client.endpoints[2])
    return false;
  return ticket(value.client, client).generations == value.generations;
}
PipeRegistration
PipeRegistry::register_reverse(std::unique_ptr<PipeConnection> connection,
                               uint32_t role, DWORD timeout, HANDLE cancel) {
  PipeRegistration result;
  if (!connection || (role != FanyImePipeRole::ToTsf &&
                      role != FanyImePipeRole::ToTsfWorkerThread))
    return result;
  auto endpoint = std::make_shared<Endpoint>();
  if (!endpoint->cancel)
    return result;
  endpoint->generation = next_generation();
  if (!endpoint->generation)
    return result;
  auto handshake = verify_reverse(connection->handle(), role, timeout, cancel);
  result.io = std::move(handshake.io);
  if (handshake.status != HandshakeStatus::Verified) {
    if (handshake.status == HandshakeStatus::TransportError)
      result.status = RegistryStatus::TransportError;
    return result;
  }
  endpoint->connection = std::move(connection);
  endpoint->peer = std::move(handshake.peer);
  auto client = lookup(handshake.client_id, true);
  if (!client) {
    result.status = RegistryStatus::Capacity;
    return result;
  }
  std::lock_guard lock(client->mutex);
  if (client->retired) {
    result.status = RegistryStatus::Stale;
    return result;
  }
  if (client->endpoints[role] &&
      client->endpoints[role]->generation > endpoint->generation) {
    result.status = RegistryStatus::Stale;
    return result;
  }
  // A changed reverse endpoint invalidates the protocol/focus chain. The new
  // client must establish Main again; old queued work cannot target this pipe.
  DWORD error = ERROR_SUCCESS;
  if (!endpoint->peer->matches(endpoint->connection->handle(),
                               handshake.client_id, error)) {
    result.io = {IoStatus::Disconnected, error, 0, false, {}};
    retire(handshake.client_id, client);
    return result;
  }
  result.io = write_frame(endpoint->connection->handle(),
                          *pipe_ready_bytes(role), timeout, cancel);
  if (!result.io.complete()) {
    result.status = RegistryStatus::TransportError;
    retire(handshake.client_id, client);
    return result;
  }
  client->clear(FanyImePipeRole::Main);
  client->clear(role);
  client->endpoints[role] = std::move(endpoint);
  result.ticket = ticket(handshake.client_id, *client);
  result.status = RegistryStatus::Ready;
  return result;
}
PipeRegistration
PipeRegistry::register_main(std::unique_ptr<PipeConnection> connection,
                            const FanyImeNamedpipeData &hello,
                            uint32_t capabilities, DWORD timeout,
                            HANDLE cancel) {
  PipeRegistration result;
  if (!connection)
    return result;
  auto client = lookup(hello.client_id, false);
  if (!client)
    return result;
  auto endpoint = std::make_shared<Endpoint>();
  if (!endpoint->cancel)
    return result;
  endpoint->generation = next_generation();
  if (!endpoint->generation)
    return result;
  std::lock_guard lock(client->mutex);
  if (client->retired || !client->endpoints[1] || !client->endpoints[2])
    return result;
  auto &reply = client->endpoints[1];
  auto &worker = client->endpoints[2];
  DWORD error = ERROR_SUCCESS;
  if (!reply->peer->matches(connection->handle(), hello.client_id, error))
    return result;
  if (!reply->peer->matches(worker->connection->handle(), hello.client_id,
                            error))
    return result;
  if (client->endpoints[0] &&
      client->endpoints[0]->generation > endpoint->generation) {
    result.status = RegistryStatus::Stale;
    return result;
  }
  auto handshake = negotiate_main(
      connection->handle(), reply->connection->handle(), *reply->peer,
      hello.client_id, hello, capabilities, timeout, cancel);
  result.io = std::move(handshake.io);
  if (handshake.status != HandshakeStatus::Ready) {
    if (handshake.status == HandshakeStatus::TransportError)
      result.status = RegistryStatus::TransportError;
    // A protocol frame may already have reached the existing reverse pipe.
    // Fail the whole transport chain; never let old key replies follow it.
    for (uint32_t role = 0; role < 3; ++role)
      client->clear(role);
    retire(hello.client_id, client);
    return result;
  }
  endpoint->connection = std::move(connection);
  endpoint->peer = reply->peer;
  client->clear(0);
  client->endpoints[0] = std::move(endpoint);
  result.ticket = ticket(hello.client_id, *client);
  result.status = RegistryStatus::Ready;
  return result;
}
IoResult PipeRegistry::read_main(const PipeTicket &value, DWORD timeout) {
  auto client = lookup(value.client, false);
  if (!client)
    return stale();
  std::shared_ptr<Endpoint> endpoint;
  {
    std::lock_guard lock(client->mutex);
    if (!current(value, *client))
      return stale();
    endpoint = client->endpoints[0];
  }
  IoResult result;
  {
    std::lock_guard io_lock(endpoint->read_mutex);
    result = timeout == INFINITE
                 ? read_frame_until_cancel(endpoint->connection->handle(),
                                           sizeof(FanyImeNamedpipeData),
                                           endpoint->cancel)
                 : read_frame(endpoint->connection->handle(),
                              sizeof(FanyImeNamedpipeData), timeout,
                              endpoint->cancel);
  }
  {
    std::lock_guard lock(client->mutex);
    if (!current(value, *client))
      return stale();
    DWORD error = ERROR_SUCCESS;
    if (!endpoint->peer->matches(endpoint->connection->handle(), value.client,
                                 error)) {
      client->clear(0);
      return {IoStatus::Disconnected, error, 0, false, {}};
    }
  }
  if (result.complete()) {
    FanyImeNamedpipeData packet{};
    std::memcpy(&packet, result.frame.data(), sizeof(packet));
    if (!valid_main_frame(packet, value.client))
      result = {IoStatus::MalformedFrame, ERROR_INVALID_DATA,
                result.transferred, false, {}};
  }
  if (!result.complete())
    remove(value, 0);
  return result;
}
IoResult PipeRegistry::send(const PipeTicket &value, uint32_t role,
                            const std::vector<uint8_t> &frame, DWORD timeout) {
  if ((role != 1 && role != 2) ||
      frame.size() != (role == 1
                           ? sizeof(FanyImeNamedpipeDataToTsf)
                           : sizeof(FanyImeNamedpipeDataToTsfWorkerThread)))
    return {IoStatus::InvalidArgument, ERROR_INVALID_PARAMETER, 0, false, {}};
  auto client = lookup(value.client, false);
  if (!client)
    return stale();
  std::lock_guard lock(client->mutex);
  if (!current(value, *client))
    return stale();
  auto endpoint = client->endpoints[role];
  DWORD error = ERROR_SUCCESS;
  if (!endpoint->peer->matches(endpoint->connection->handle(), value.client,
                               error)) {
    client->clear(0);
    client->clear(role);
    return {IoStatus::Disconnected, error, 0, false, {}};
  }
  auto result = write_frame(endpoint->connection->handle(), frame, timeout,
                            endpoint->cancel);
  if (!result.complete()) {
    client->clear(0);
    client->clear(role);
  }
  return result;
}
bool PipeRegistry::remove(const PipeTicket &value, uint32_t role) {
  if (role > 2 || !value.generations[role])
    return false;
  auto client = lookup(value.client, false);
  if (!client)
    return false;
  std::lock_guard lock(client->mutex);
  if (client->retired || !client->endpoints[role] ||
      client->endpoints[role]->generation != value.generations[role])
    return false;
  client->clear(0);
  client->clear(role);
  retire(value.client, client);
  return true;
}
void PipeRegistry::shutdown() {
  std::unordered_map<uint64_t, std::shared_ptr<Client>> clients;
  {
    std::lock_guard lock(mutex_);
    stopped_ = true;
    clients.swap(clients_);
  }
  for (auto &[id, client] : clients) {
    (void)id;
    std::lock_guard lock(client->mutex);
    client->retired = true;
    for (uint32_t role = 0; role < 3; ++role)
      client->clear(role);
  }
}
} // namespace msime::windows
