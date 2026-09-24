#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <cstdint>
#include <memory>
#include <windows.h>

namespace msime::windows {
// Server-side binding of a connected local pipe to its client process.
// The caller owns the pipe, prevents concurrent disconnect/close/reconnect,
// and must enforce its DACL and PIPE_REJECT_REMOTE_CLIENTS before this check.
// Bind while the client is live, before publishing any route. This is neither
// protocol negotiation nor proof of which thread inside that process sent a
// message.
class PipePeer final {
public:
  static std::unique_ptr<PipePeer> bind(HANDLE pipe, uint64_t client_id,
                                        DWORD &error);
  ~PipePeer();
  PipePeer(const PipePeer &) = delete;
  PipePeer &operator=(const PipePeer &) = delete;
  // Recheck a main/reverse endpoint against the retained process identity.
  // Call under the route/endpoint lifetime guard, before publishing or sending.
  bool matches(HANDLE pipe, uint64_t client_id, DWORD &error) const;

private:
  PipePeer(HANDLE process, uint64_t client_id, DWORD session)
      : process_(process), client_id_(client_id), session_(session) {}
  HANDLE process_;
  uint64_t client_id_;
  DWORD session_;
};
// Session-less endpoints (the Aux pipe) have no client id to bind, so these
// read the connected client straight off the server end of the pipe.
// The client's process id, provided it runs in this Server's session.
bool pipe_client_in_session(HANDLE pipe, ULONG &pid, DWORD &error);
// True only for a full desktop process of this user: same session and user
// SID, not in an AppContainer, and at least medium integrity. Any failure to
// tell is a rejection.
bool pipe_client_is_desktop_user(HANDLE pipe, DWORD &error);
} // namespace msime::windows
