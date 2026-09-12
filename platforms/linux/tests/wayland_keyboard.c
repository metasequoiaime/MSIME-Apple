// Synthetic test driver. Protocol XML: wtype d71be3a7b3f93b534a2823fd68cabd7ac2a02359,
// protocol/virtual-keyboard-unstable-v1.xml; its MIT notice is retained there.
#define _POSIX_C_SOURCE 200809L
#include <wayland-client.h>
#include "virtual-keyboard-client.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *manager;
static void global(void *data, struct wl_registry *registry, uint32_t name,
                   const char *interface, uint32_t version) {
  (void)data; (void)version;
  if (!strcmp(interface, "wl_seat"))
    seat = wl_registry_bind(registry, name, &wl_seat_interface, 1);
  if (!strcmp(interface, "zwp_virtual_keyboard_manager_v1"))
    manager = wl_registry_bind(registry, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}
static void removed(void *data, struct wl_registry *registry, uint32_t name) {
  (void)data; (void)registry; (void)name;
}
struct mapping { const char *name; unsigned code; };
static const struct mapping keys[] = {
  {"Escape",1}, {"1",2}, {"2",3}, {"3",4}, {"4",5}, {"5",6},
  {"6",7}, {"7",8}, {"8",9}, {"9",10}, {"0",11}, {"BackSpace",14},
  {"q",16}, {"w",17}, {"e",18}, {"r",19}, {"i",23}, {"o",24},
  {"Return",28}, {"a",30}, {"h",35}, {"apostrophe",40}, {"Shift_L",42},
  {"x",45}, {"n",49}, {"space",57}, {"F1",59}, {"Multi_key",127},
  {"dead_circumflex",200}, {"U1F600",201}
};
int main(void) {
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) return 2;
  struct wl_registry *registry = wl_display_get_registry(display);
  const struct wl_registry_listener listener = {global, removed};
  wl_registry_add_listener(registry, &listener, NULL);
  if (wl_display_roundtrip(display) < 0 || !seat || !manager) return 3;
  struct zwp_virtual_keyboard_v1 *keyboard =
    zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(manager, seat);
  char path[] = "/tmp/msime-test-keymap.XXXXXX";
  int fd = mkstemp(path);
  if (fd < 0) return 4;
  unlink(path);
  FILE *map = fdopen(fd, "w+");
  if (!map) return 5;
  fputs("xkb_keymap { xkb_keycodes { minimum=8; maximum=255;\n", map);
  for (size_t i=0; i<sizeof(keys)/sizeof(keys[0]); ++i)
    fprintf(map, "<K%u> = %u;\n", keys[i].code, keys[i].code+8);
  fputs("}; xkb_types { include \"complete\" }; xkb_compatibility { include \"complete\" }; xkb_symbols {\n", map);
  for (size_t i=0; i<sizeof(keys)/sizeof(keys[0]); ++i)
    fprintf(map, "key <K%u> { [%s] };\n", keys[i].code, keys[i].name);
  fputs("}; };", map);
  fputc(0, map); fflush(map);
  zwp_virtual_keyboard_v1_keymap(keyboard, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, (uint32_t)ftell(map));
  if (wl_display_roundtrip(display) < 0) return 6;
  fclose(map);
  puts("ready"); fflush(stdout);
  char line[64]; uint32_t time = 0;
  while (fgets(line, sizeof(line), stdin)) {
    line[strcspn(line, "\n")] = 0;
    size_t i;
    for (i=0; i<sizeof(keys)/sizeof(keys[0]); ++i)
      if (!strcmp(keys[i].name, line)) break;
    if (i == sizeof(keys)/sizeof(keys[0])) return 7;
    zwp_virtual_keyboard_v1_key(keyboard, ++time, keys[i].code, WL_KEYBOARD_KEY_STATE_PRESSED);
    zwp_virtual_keyboard_v1_key(keyboard, ++time, keys[i].code, WL_KEYBOARD_KEY_STATE_RELEASED);
    if (wl_display_roundtrip(display) < 0) return 8;
    puts("sent"); fflush(stdout);
  }
  zwp_virtual_keyboard_v1_destroy(keyboard);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
