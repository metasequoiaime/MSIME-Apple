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
  bool view(std::string *, std::string *) const;
private:
  bool response(char *, std::string *, std::string *) const;
  uint64_t session_ = 0;
};
}
