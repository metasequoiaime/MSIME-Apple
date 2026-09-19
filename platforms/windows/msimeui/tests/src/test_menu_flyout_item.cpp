#include "tests/includes/test_framework.h"

#include "msimeui/Controls.h"
#include "msimeui/Layout.h"
#include "msimeui/Window.h"

#include <memory>

using namespace msimeui;

namespace
{
// Counts how many copies of the click handler exist, so the test can ask the
// one question that matters: was the callable still alive while its own
// operator() was running?
//
// Observing that directly beats trying to catch the access violation. The crash
// only reproduces when the freed block happens to be recycled before the
// handler reads its captures back, which depends on the allocator and on
// whether the compiler reloaded the captures at all — in the shipped binary the
// 删除 lambda did and 置顶 did not. Reading freed memory would also make the
// test itself undefined behaviour. This probe touches only statics after the
// teardown, so it is deterministic and well-defined either way.
struct HandlerProbe
{
    static int live;
    static int liveDuringCall;

    explicit HandlerProbe(std::shared_ptr<Popup> *slot) : slot_(slot)
    {
        ++live;
    }

    HandlerProbe(const HandlerProbe &other) : slot_(other.slot_)
    {
        ++live;
    }

    HandlerProbe &operator=(const HandlerProbe &) = delete;

    ~HandlerProbe()
    {
        --live;
    }

    void operator()() const
    {
        // What CandidatePresenter::CloseContextMenu does: the handler releases
        // the last reference to the item it was invoked from, which destroys the
        // std::function holding this probe.
        slot_->reset();
        liveDuringCall = live;
    }

  private:
    std::shared_ptr<Popup> *slot_;
};

int HandlerProbe::live = 0;
int HandlerProbe::liveDuringCall = -1;
} // namespace

// Every candidate context-menu action closes the menu and then posts a message.
// Closing it destroys the MenuFlyoutItem, and with it the std::function being
// executed, so the handler body went on to read its captures out of freed
// storage the teardown had already recycled — an access violation inside the
// server's candidate window.
TEST_CASE(menu_flyout_item_click_handler_outlives_the_menu_it_closes)
{
    // Never Create()d: the item only needs a Window to convert pixels to DIPs,
    // which falls back to 96 dpi without an HWND.
    Window window(L"msimeui-tests-menu", L"", 100, 100);

    auto stack = std::make_shared<StackPanel>(0.0f);
    auto item = std::make_shared<MenuFlyoutItem>(L"删除");
    stack->AddChild(item);
    auto popup = std::make_shared<Popup>(stack);

    HandlerProbe::liveDuringCall = -1;
    item->SetOnClick(HandlerProbe{&popup});
    REQUIRE(HandlerProbe::live == 1);

    // Hand ownership entirely to the popup, so closing it really is the last
    // reference going away — as it is when the menu lives only in the scene and
    // in CandidatePresenter::Impl.
    MenuFlyoutItem *raw = item.get();
    std::weak_ptr<MenuFlyoutItem> watch = item;
    item.reset();
    stack.reset();

    raw->Attach(&window);
    raw->Arrange({0.0f, 0.0f, 120.0f, 24.0f});

    const POINT point{10, 10};
    REQUIRE(raw->OnMouseDown(point, 0));
    REQUIRE(raw->OnMouseUp(point, 0));

    // The premise: the handler really did destroy the item it ran from. Without
    // these the test could pass for the wrong reason.
    REQUIRE(popup == nullptr);
    REQUIRE(watch.expired());

    // The invariant: OnMouseUp holds its own reference to the handler, so a
    // live copy remained for the whole call even though the item's copy went
    // away mid-flight.
    REQUIRE(HandlerProbe::liveDuringCall >= 1);

    REQUIRE(HandlerProbe::live == 0);
}
