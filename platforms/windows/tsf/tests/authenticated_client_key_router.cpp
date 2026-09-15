#include "../Key/AuthenticatedClientKeyRouter.h"
#include <cassert>

class Router final : public IClientKeyRouter {
public:
    bool dispatch(const ClientKeyEvent &event) override {
        ++calls;
        last = event;
        return true;
    }
    bool cancel(const ClientFocusLease &) override { return true; }
    int calls = 0;
    ClientKeyEvent last{};
};

int main() {
    Router router;
    AuthenticatedClientKeyRouter guarded(router, 7, 11, 19);
    const ClientKeyEvent event{client_focus_lease(7, 11, 19), 0x41, 0x1e, 0, u'A', false};
    msime::windows::TsfFocusLeaseRequest request;
    request.client = 7;
    request.epoch = 11;
    request.token = 19;
    const auto frame = msime::windows::encode_tsf_focus_lease(request);
    assert(guarded.dispatch(frame, event));
    assert(router.calls == 1);
    guarded.update_lease(7, 11, 20);
    assert(!guarded.dispatch(frame, event));
    assert(router.calls == 1);
}
