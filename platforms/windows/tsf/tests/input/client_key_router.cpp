#include "../../Key/ClientKeyRouter.h"
#include <cassert>

int main() {
    ClientFocusLease lease = client_focus_lease(7, 11, 19);
    assert(valid_client_focus_lease(lease));
    assert(same_client_focus_lease(lease, {7, 11, 19}));
    assert(!same_client_focus_lease(lease, {7, 11, 20}));
    assert(!valid_client_focus_lease({7, 0, 19}));
    const ClientKeyEvent event{lease, 0x41, 0x36, 3, u'A', true};
    assert(event.lease.client == 7 && event.lease.epoch == 11 && event.lease.token == 19);
    assert(event.virtual_key == 0x41 && event.scan_code == 0x36 && event.modifiers == 3);
    assert(event.character == u'A' && event.ui_less);
}
