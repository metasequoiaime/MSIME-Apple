#pragma once
#include "msime_client.h"
#include <cstddef>
#include <cstdint>
#include <string>
namespace msime::tsf {
class EngineSessionAdapter final {
public:
  ~EngineSessionAdapter();
  bool create(const std::string &, std::string *);
  void destroy() noexcept;
  bool valid() const noexcept { return session_ != 0; }
  bool character(uint8_t, bool, std::string *, std::string *);
  bool command(uint32_t, std::string *, std::string *);
  bool select(uint64_t, std::size_t, std::string *, std::string *);
  bool select_edge(uint64_t, std::size_t, uint8_t, std::string *, std::string *);
  bool view(std::string *, std::string *) const;
  bool punctuation(uint8_t, std::string *, std::string *);
  bool focus(bool, std::string *, std::string *);
  bool chinese_punctuation(bool, std::string *, std::string *);
  bool character_width(bool, std::string *, std::string *);
  bool english_mode(bool, std::string *, std::string *);
  bool dedicated_english(bool, std::string *, std::string *);
  bool paired_punctuation(bool, std::string *, std::string *);
  bool punctuation_lock(uint8_t, std::string *, std::string *);
  bool update_preferences(const std::string &, std::string *, std::string *);
private:
  bool response(char *, std::string *, std::string *) const;
  uint64_t session_ = 0;
};
}
