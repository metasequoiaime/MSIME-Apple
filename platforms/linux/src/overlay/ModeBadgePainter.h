#pragma once
#include <cairo/cairo.h>
#include <pango/pangocairo.h>

#include <string>

namespace msime::linux_host {

// 徽章的绘制：圆角底板、产品 logo、一个「中」或「英」。
//
// 放在这里是为了让 Wayland 与 X11 两个后端共用同一份画法——它们的差别只在把像素交给谁，
// 画什么不该有两份，否则两个会话类型下的观感迟早对不上。
inline void paint_mode_badge(cairo_t *cairo, int width, int height, const std::string &text,
                             const std::string &icon_path, bool light_theme, int icon_size,
                             int icon_left) {
  cairo_set_operator(cairo, CAIRO_OPERATOR_SOURCE);
  cairo_set_source_rgba(cairo, 0, 0, 0, 0);
  cairo_paint(cairo);
  cairo_set_operator(cairo, CAIRO_OPERATOR_OVER);

  // 圆角底板。深浅跟随共享偏好的候选主题，与面板观感一致。
  const double radius = 14.0;
  const double w = width, h = height;
  cairo_new_sub_path(cairo);
  cairo_arc(cairo, w - radius, radius, radius, -1.5708, 0);
  cairo_arc(cairo, w - radius, h - radius, radius, 0, 1.5708);
  cairo_arc(cairo, radius, h - radius, radius, 1.5708, 3.1416);
  cairo_arc(cairo, radius, radius, radius, 3.1416, 4.7124);
  cairo_close_path(cairo);
  if (light_theme)
    cairo_set_source_rgba(cairo, 0.96, 0.97, 0.98, 0.96);
  else
    cairo_set_source_rgba(cairo, 0.125, 0.129, 0.141, 0.96);
  cairo_fill_preserve(cairo);
  cairo_set_source_rgba(cairo, light_theme ? 0.85 : 0.22, light_theme ? 0.87 : 0.23,
                        light_theme ? 0.91 : 0.25, 1.0);
  cairo_set_line_width(cairo, 1.0);
  cairo_stroke(cairo);

  // logo。读不到就只画文字：提示缺一半也比不显示强。
  double text_left = icon_left;
  if (!icon_path.empty()) {
    if (auto *logo = cairo_image_surface_create_from_png(icon_path.c_str())) {
      if (cairo_surface_status(logo) == CAIRO_STATUS_SUCCESS) {
        const double source_w = cairo_image_surface_get_width(logo);
        const double source_h = cairo_image_surface_get_height(logo);
        if (source_w > 0 && source_h > 0) {
          const double scale = icon_size / (source_w > source_h ? source_w : source_h);
          cairo_save(cairo);
          cairo_translate(cairo, icon_left, (height - source_h * scale) / 2.0);
          cairo_scale(cairo, scale, scale);
          cairo_set_source_surface(cairo, logo, 0, 0);
          cairo_paint(cairo);
          cairo_restore(cairo);
          text_left = icon_left + source_w * scale + 12;
        }
      }
      cairo_surface_destroy(logo);
    }
  }

  auto *layout = pango_cairo_create_layout(cairo);
  auto *font = pango_font_description_from_string("Noto Sans CJK SC 26");
  pango_layout_set_font_description(layout, font);
  pango_font_description_free(font);
  pango_layout_set_text(layout, text.c_str(), -1);
  int text_w = 0, text_h = 0;
  pango_layout_get_pixel_size(layout, &text_w, &text_h);
  cairo_move_to(cairo, text_left, (height - text_h) / 2.0);
  if (light_theme)
    cairo_set_source_rgb(cairo, 0.13, 0.13, 0.14);
  else
    cairo_set_source_rgb(cairo, 0.96, 0.97, 0.98);
  pango_cairo_show_layout(cairo, layout);
  g_object_unref(layout);

}

}  // namespace msime::linux_host
