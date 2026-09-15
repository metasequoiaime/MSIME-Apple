#include "../ToolbarLayout.h"

#include <cassert>
#include <cmath>

using namespace msime::windows;

namespace {
bool near(double a, double b) { return std::fabs(a - b) < 1e-9; }

// The shipped geometry, pinned. The struct's defaults are what an
// out-of-range icon size falls back to, so they have to agree with what the
// shipped size actually produces or the fallback bar is a different shape
// from the real one.
void shipped_size_matches_the_struct_defaults() {
  const auto metrics = toolbar_metrics(24.0, false);
  const ToolbarMetrics fallback;
  assert(near(metrics.cell, 48.0));
  assert(near(metrics.height, 52.0));
  assert(near(metrics.handle, 8.0));
  assert(near(metrics.cell, fallback.cell));
  assert(near(metrics.height, fallback.height));
  // Eight buttons - the shipped set - at 16 + 48 * n.
  assert(near(toolbar_content_width(8, metrics), 400.0));
  assert(near(toolbar_content_width(3, metrics), 160.0));
}

// What the user sees as the gap between two buttons is the cell minus the
// glyph in it. Three icon widths per cell left two thirds of the bar empty and
// read as scattered marks rather than a row of controls; the pitch was cut to
// two. Bounded on both sides: below roughly 1.5 the hover pills touch and the
// icons run together, above 2.5 the spacing is back to where it started.
void the_gap_around_an_icon_stays_proportionate() {
  for (double size : {12.0, 16.0, 24.0, 48.0, 64.0}) {
    const auto metrics = toolbar_metrics(size, false);
    const double padding = metrics.cell - size; // Both sides together.
    assert(padding > size * 0.4);
    assert(padding < size * 1.5);
  }
}

// The gap this closes: the icon size setting used to change only the glyph,
// leaving it in a cell that never grew.
void bar_follows_icon_size() {
  const auto shipped = toolbar_metrics(24.0, false);
  const auto small_icons = toolbar_metrics(16.0, false);
  const auto large = toolbar_metrics(32.0, false);
  assert(small_icons.cell < shipped.cell);
  assert(large.cell > shipped.cell);
  assert(small_icons.height < shipped.height);
  assert(large.height > shipped.height);
  // A bar of the same button count is strictly wider with larger icons.
  assert(toolbar_content_width(5, large) > toolbar_content_width(5, small_icons));
}

// An implausible size must not produce a degenerate or enormous window.
void out_of_range_size_keeps_shipped_geometry() {
  const ToolbarMetrics shipped;
  for (double size : {0.0, -12.0, 4.0, 1e9}) {
    const auto metrics = toolbar_metrics(size, false);
    assert(near(metrics.cell, shipped.cell));
    assert(near(metrics.height, shipped.height));
  }
  const auto nan_size = toolbar_metrics(std::nan(""), false);
  assert(near(nan_size.cell, shipped.cell));
}

// The point of the shared helper: drawing, hover and click all ask the same
// function, so the highlighted button is always the one that gets clicked.
void hit_testing_agrees_with_the_drawn_cells() {
  const auto check = [](double size, bool shadow) {
    const auto metrics = toolbar_metrics(size, shadow);
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
  };
  for (double size : {16.0, 24.0, 40.0}) {
    check(size, false);
    check(size, true);
  }
}

// The drag strip is not a button, and neither is the trailing margin; both
// used to be guarded by open-coded bounds at each call site.
void non_button_regions_select_nothing() {
  for (bool shadow : {false, true}) {
    const auto metrics = toolbar_metrics(24.0, shadow);
    const auto card = toolbar_card(6, metrics);
    assert(!toolbar_button_at(0.0, 6, metrics));
    assert(!toolbar_button_at(card.left, 6, metrics));
    assert(!toolbar_button_at(card.left + metrics.handle - 0.01, 6, metrics));
    assert(!toolbar_button_at(-50.0, 6, metrics));
    // Past the last button, inside the bar's trailing margin.
    const auto past = toolbar_cell(5, metrics).right + 0.01;
    assert(past < card.right);
    assert(!toolbar_button_at(past, 6, metrics));
    // An empty toolbar has nothing to hit anywhere.
    assert(!toolbar_button_at(100.0, 0, metrics));
  }
}

// The shadow grows the window and insets the bar. Getting only half of that
// right is what would put the drawn buttons and the clicks out of step.
void shadow_pads_the_window_without_resizing_the_bar() {
  const auto plain = toolbar_metrics(24.0, false);
  const auto shadowed = toolbar_metrics(24.0, true);
  // The bar itself is untouched; only the window around it grows.
  assert(near(plain.cell, shadowed.cell));
  assert(near(plain.height, shadowed.height));
  assert(near(toolbar_content_width(6, plain),
              toolbar_content_width(6, shadowed)));
  assert(toolbar_window_width(6, shadowed) > toolbar_window_width(6, plain));
  assert(toolbar_window_height(shadowed) > toolbar_window_height(plain));
  // Without a shadow the window is exactly the bar, so nothing moves for a
  // caller that turns it off.
  assert(near(toolbar_window_width(6, plain), toolbar_content_width(6, plain)));
  assert(near(toolbar_window_height(plain), plain.height));
  assert(near(toolbar_card(6, plain).left, 0.0));
  assert(near(toolbar_card(6, plain).top, 0.0));

  // With the shadow on, the bar is inset by exactly the margin, leaving room
  // on every side for the shadow to fall outside it.
  const auto card = toolbar_card(6, shadowed);
  assert(card.left > 0.0 && card.top > 0.0);
  assert(near(card.left, shadowed.shadow.left));
  assert(near(card.top, shadowed.shadow.top));
  assert(near(toolbar_window_width(6, shadowed) - card.right,
              shadowed.shadow.right));
  assert(near(toolbar_window_height(shadowed) - card.bottom,
              shadowed.shadow.bottom));
  assert(shadowed.shadow.scale > 0.0);
  // A disabled shadow must draw nothing rather than a zero-size blur.
  assert(near(plain.shadow.scale, 0.0));
}

// The drag strip is the bar's left edge, not the window's - the shadow margin
// outside it belongs to whatever is behind the toolbar.
void drag_strip_excludes_the_shadow_margin() {
  const auto metrics = toolbar_metrics(24.0);
  const auto card = toolbar_card(6, metrics);
  assert(!toolbar_is_drag_strip(0.0, metrics));
  assert(!toolbar_is_drag_strip(card.left - 0.01, metrics));
  assert(toolbar_is_drag_strip(card.left, metrics));
  assert(toolbar_is_drag_strip(card.left + metrics.handle - 0.01, metrics));
  // The first button is not a drag handle; dragging from it would eat clicks.
  assert(!toolbar_is_drag_strip(toolbar_cell(0, metrics).left, metrics));
  // Nothing is both a drag strip and a button.
  for (double x = -20.0; x < 600.0; x += 0.5)
    assert(!(toolbar_is_drag_strip(x, metrics) &&
             toolbar_button_at(x, 6, metrics).has_value()));
}

// Every button drawn must fit inside the window the sizing code asks for,
// which is what kept the last button from being clipped.
void buttons_fit_within_the_bar() {
  const auto check = [](double size, bool shadow) {
    const auto metrics = toolbar_metrics(size, shadow);
    for (size_t count = 1; count <= 10; ++count) {
      const auto last = toolbar_cell(count - 1, metrics);
      const auto card = toolbar_card(count, metrics);
      // Inside the bar, and the bar inside the window.
      assert(last.right <= card.right);
      assert(last.bottom <= card.bottom);
      assert(last.top >= card.top);
      assert(card.right <= toolbar_window_width(count, metrics));
      assert(card.bottom <= toolbar_window_height(metrics));
    }
  };
  for (double size : {12.0, 24.0, 48.0}) {
    check(size, false);
    check(size, true);
  }
}
} // namespace

int main() {
  shipped_size_matches_the_struct_defaults();
  the_gap_around_an_icon_stays_proportionate();
  bar_follows_icon_size();
  out_of_range_size_keeps_shipped_geometry();
  hit_testing_agrees_with_the_drawn_cells();
  non_button_regions_select_nothing();
  shadow_pads_the_window_without_resizing_the_bar();
  drag_strip_excludes_the_shadow_margin();
  buttons_fit_within_the_bar();
  return 0;
}
