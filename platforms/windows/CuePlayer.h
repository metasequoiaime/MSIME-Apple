#pragma once

#include <string>

struct ma_engine;
struct ma_sound;

class CuePlayer final {
public:
  CuePlayer();
  ~CuePlayer();
  CuePlayer(const CuePlayer &) = delete;
  CuePlayer &operator=(const CuePlayer &) = delete;

  bool init(const std::wstring &start_path, const std::wstring &end_path);
  void shutdown();
  void play_start();
  void play_end();

private:
  bool load_sound(const std::wstring &path, ma_sound *sound, bool *loaded,
                 const char *label);
  bool play_sound(ma_sound *sound, bool loaded, const char *label);
  static std::string utf8(const std::wstring &value);

  ma_engine *engine_ = nullptr;
  ma_sound *start_sound_ = nullptr;
  ma_sound *end_sound_ = nullptr;
  bool engine_initialized_ = false;
  bool start_loaded_ = false;
  bool end_loaded_ = false;
};
