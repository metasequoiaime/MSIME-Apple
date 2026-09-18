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
} // namespace msime::windows
