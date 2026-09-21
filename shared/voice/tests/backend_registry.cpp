// The on-device recognizer's backends have to still be registered when the libraries are linked in
// rather than loaded.
//
// Static archives are the configuration this product ships (see shared/voice/CMakeLists.txt), and a
// backend that the registry never hears about is the quietest possible failure: whisper runs, results
// come back, and every one of them was computed on the CPU. Nothing else notices - the symbols are in
// the binary either way, the build succeeds, and the recognizer answers.
//
// So the assertion is on the registry, not on the symbols: ask it what it has.

#include <cstdio>
#include <cstring>

#include "ggml-backend.h"

int main() {
  const size_t count = ggml_backend_reg_count();
  if (count == 0) {
    std::fprintf(stderr, "no ggml backends are registered\n");
    return 1;
  }
  bool metal = false;
  bool cpu = false;
  for (size_t index = 0; index < count; ++index) {
    ggml_backend_reg_t reg = ggml_backend_reg_get(index);
    const char *name = reg ? ggml_backend_reg_name(reg) : nullptr;
    if (!name) {
      continue;
    }
    std::printf("registered backend: %s\n", name);
    // ggml registers the Metal backend under the short spelling, not "Metal".
    metal = metal || std::strcmp(name, "MTL") == 0 || std::strcmp(name, "Metal") == 0;
    cpu = cpu || std::strcmp(name, "CPU") == 0;
  }
  if (!cpu) {
    std::fprintf(stderr, "the CPU backend is not registered\n");
    return 1;
  }
#if defined(__APPLE__)
  if (!metal) {
    std::fprintf(stderr,
                 "the Metal backend is not registered; recognition would fall back to the CPU\n");
    return 1;
  }
#endif
  return 0;
}
