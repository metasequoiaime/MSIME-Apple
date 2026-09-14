#include "../ToolbarLayout.h"

#include <cassert>
#include <cmath>

using namespace msime::windows;

namespace {
bool near(double a, double b) { return std::fabs(a - b) < 1e-9; }

// The shipped icon size has to reproduce the geometry that was hard-coded
// before, or every existing user's toolbar changes size on upgrade.
void default_size_is_unchanged() {
  const auto metrics = toolbar_metrics(24.0);
  assert(near(metrics.cell, 72.0));
  assert(near(metrics.height, 52.0));
  assert(near(metrics.handle, 8.0));
  // Ten buttons at the old 16 + 72 * n.
  assert(near(toolbar_bar_width(10, metrics), 736.0));
  assert(near(toolbar_bar_width(3, metrics), 232.0));
}

// The gap this closes: the icon size setting used to change only the glyph,
// leaving it in a cell that never grew.
void bar_follows_icon_size() {
  const auto small_icons = toolbar_metrics(16.0);
  const auto large = toolbar_metrics(32.0);
  assert(small_icons.cell < 72.0);
  assert(large.cell > 72.0);
  assert(small_icons.height < 52.0);
  assert(large.height > 52.0);
  // A bar of the same button count is strictly wider with larger icons.
  assert(toolbar_bar_width(5, large) > toolbar_bar_width(5, small_icons));
}

// An implausible size must not produce a degenerate or enormous window.
void out_of_range_size_keeps_shipped_geometry() {
  for (double size : {0.0, -12.0, 4.0, 1e9}) {
    const auto metrics = toolbar_metrics(size);
    assert(near(metrics.cell, 72.0));
    assert(near(metrics.height, 52.0));
  }
  const auto nan_size = toolbar_metrics(std::nan(""));
  assert(near(nan_size.cell, 72.0));
}

// The point of the shared helper: drawing, hover and click all ask the same
// function, so the highlighted button is always the one that gets clicked.
void hit_testing_agrees_with_the_drawn_cells() {
  for (double size : {16.0, 24.0, 40.0}) {
    const auto metrics = toolbar_metrics(size);
    constexpr size_t buttons = 6;
    for (size_t i = 0; i < buttons; ++i) {
      const auto box = toolbar_cell(i, metrics);
      // Both edges of the drawn cell, and its middle, route to that button.
      for (double x : {box.left + 0.01, (box.left + box.right) / 2.0,
                       box.right - 0.01}) {
        const auto hit = toolbar_button_at(x, buttons, metrics);
        assert(hit && *hit == i);
      }
    }
    // Cells tile without gaps or overlap.
    for (size_t i = 1; i < buttons; ++i)
      assert(near(toolbar_cell(i - 1, metrics).right,
                  toolbar_cell(i, metrics).left));
  }
}

// The drag strip is not a button, and neither is the trailing margin; both
// used to be guarded by open-coded bounds at each call site.
void non_button_regions_select_nothing() {
  const auto metrics = toolbar_metrics(24.0);
  assert(!toolbar_button_at(0.0, 6, metrics));
  assert(!toolbar_button_at(metrics.handle - 0.01, 6, metrics));
  assert(!toolbar_button_at(-50.0, 6, metrics));
  // Past the last button, inside the bar's trailing margin.
  const auto past = toolbar_cell(5, metrics).right + 0.01;
  assert(past < toolbar_bar_width(6, metrics));
  assert(!toolbar_button_at(past, 6, metrics));
  // An empty toolbar has nothing to hit anywhere.
  assert(!toolbar_button_at(100.0, 0, metrics));
}

// Every button drawn must fit inside the window the sizing code asks for,
// which is what kept the last button from being clipped.
void buttons_fit_within_the_bar() {
  for (double size : {12.0, 24.0, 48.0}) {
    const auto metrics = toolbar_metrics(size);
    for (size_t count = 1; count <= 10; ++count) {
      const auto last = toolbar_cell(count - 1, metrics);
      assert(last.right <= toolbar_bar_width(count, metrics));
      assert(last.bottom <= metrics.height);
      assert(last.top > 0.0);
    }
  }
}
} // namespace

int main() {
  default_size_is_unchanged();
  bar_follows_icon_size();
  out_of_range_size_keeps_shipped_geometry();
  hit_testing_agrees_with_the_drawn_cells();
  non_button_regions_select_nothing();
  buttons_fit_within_the_bar();
  return 0;
}
