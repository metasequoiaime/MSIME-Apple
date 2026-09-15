#pragma once

#include "ClientKeyRouter.h"
#include "../../TsfFocusLeaseProtocol.h"

// Adapter-side gate for the future versioned TSF lease transport. It keeps
// authentication before the shared router and never mutates the event.
class AuthenticatedClientKeyRouter final {
public:
    AuthenticatedClientKeyRouter(IClientKeyRouter &router,
                                 std::uint64_t client,
                                 std::uint64_t epoch,
                                 std::uint64_t token)
        : router_(router), authenticator_(client, epoch, token) {}

    void update_lease(std::uint64_t client, std::uint64_t epoch,
                      std::uint64_t token) {
        authenticator_.update(client, epoch, token);
    }

    bool dispatch(const msime::windows::TsfFocusLeaseFrame &frame,
                  const ClientKeyEvent &event) {
        const auto request = msime::windows::decode_tsf_focus_lease(frame);
        if (!authenticator_.authenticate(frame) ||
            request.client != event.lease.client ||
            request.epoch != event.lease.epoch ||
            request.token != event.lease.token) {
            return false;
        }
        return router_.dispatch(event);
    }

private:
    IClientKeyRouter &router_;
    msime::windows::TsfFocusLeaseAuthenticator authenticator_;
};
