#pragma once

#include <cstdint>

// Platform-neutral boundary for routing a TSF key into the shared client.
// The TSF adapter owns focus identity; the client owns input semantics.
struct ClientFocusLease {
    std::uint64_t client = 0;
    std::uint64_t epoch = 0;
    std::uint64_t token = 0;
};

struct ClientKeyEvent {
    ClientFocusLease lease;
    std::uint32_t virtual_key = 0;
    std::uint32_t scan_code = 0;
    std::uint32_t modifiers = 0;
    char16_t character = 0;
    bool ui_less = false;
};

class IClientKeyRouter {
  public:
    virtual ~IClientKeyRouter() = default;
    virtual bool dispatch(const ClientKeyEvent &event) = 0;
    virtual bool cancel(const ClientFocusLease &lease) = 0;
};
