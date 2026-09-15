#pragma once

#include <cstdint>

// Platform-neutral boundary for routing a TSF key into the shared client.
// The TSF adapter owns focus identity; the client owns input semantics.
struct ClientFocusLease {
    std::uint64_t client = 0;
    std::uint64_t epoch = 0;
    std::uint64_t token = 0;
};

constexpr ClientFocusLease client_focus_lease(std::uint64_t client,
                                              std::uint64_t epoch,
                                              std::uint64_t token) {
    return {client, epoch, token};
}

constexpr bool valid_client_focus_lease(const ClientFocusLease &lease) {
    return lease.client != 0 && lease.epoch != 0 && lease.token != 0;
}

constexpr bool same_client_focus_lease(const ClientFocusLease &left,
                                       const ClientFocusLease &right) {
    return left.client == right.client && left.epoch == right.epoch &&
           left.token == right.token;
}

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
