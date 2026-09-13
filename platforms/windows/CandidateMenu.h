#pragma once
#include <cstddef>
#include <string>
#include <cstdint>
#include <optional>
#include <string>
#include <stdexcept>
#include <vector>

namespace msime::windows {
// The candidate right-click menu, mirroring the rows the IBus host already
// offers (platforms/linux/ClientEngine.cpp:1701-1725). This header decides what
// the menu offers for a given candidate; drawing and routing stay outside, so
// the rules are testable without a desktop or an Engine.
enum class CandidateMenuCommand { Pin, Remove, Fix, Clear };

struct CandidateMenuItem {
  CandidateMenuCommand command;
  // 1..5 for Fix, 0 otherwise.
  uint8_t position = 0;
  std::string label;
  // A row that cannot apply is shown disabled rather than silently doing
  // nothing, matching the shipped menu which never hides its entries.
  bool available = true;
  // The slot this candidate is currently fixed to is shown selected.
  bool checked = false;
};

// Slots the Engine accepts for a fixed candidate.
inline constexpr uint8_t candidate_fix_slots = 5;

// Japanese input has no persistable user-dictionary entry, and only these
// candidate sources can be written back. Same rule the IBus host applies
// before calling the shared entry points (ClientEngine.cpp:3142-3145).
inline constexpr int candidate_scheme_japanese = 3;
inline bool candidate_actions_available(int scheme, int source) {
  if (scheme == candidate_scheme_japanese)
    return false;
  return source == 0 || source == 1 || source == 4;
}

// Count Unicode code points, pairing surrogates, the way the reference does
// before deciding whether 删除 applies (candidate_presenter.cpp:665-673).
inline size_t candidate_code_points(const std::string &utf8) {
  size_t points = 0;
  for (unsigned char unit : utf8)
    // Continuation bytes belong to the code point already counted.
    if ((unit & 0xc0) != 0x80)
      ++points;
  return points;
}

// The reference OMITS the delete row for a single-code-point candidate rather
// than showing it disabled (candidate_presenter.cpp:674 showDelete, gated at
// :707), so a single character can never be deleted from the user dictionary by
// mistake. Everything else keeps the reference order: 置顶, 第 1..5 位,
// 取消固定, 删除.
inline std::vector<CandidateMenuItem> candidate_menu_items(bool actionable,
                                                           int fixed_position,
                                                           const std::string &text) {
  std::vector<CandidateMenuItem> items;
  items.push_back({CandidateMenuCommand::Pin, 0, "置顶", actionable, false});
  for (uint8_t slot = 1; slot <= candidate_fix_slots; ++slot)
    items.push_back({CandidateMenuCommand::Fix, slot,
                     "第 " + std::to_string(slot) + " 位", actionable,
                     fixed_position == slot});
  // Releasing a slot only means anything while one is held.
  items.push_back({CandidateMenuCommand::Clear, 0, "取消固定",
                   actionable && fixed_position > 0, false});
  if (candidate_code_points(text) != 1)
    items.push_back({CandidateMenuCommand::Remove, 0, "删除", actionable, false});
  return items;
}

struct CandidateMenuMetrics {
  double width = 168.0;
  double row_height = 26.0;
  double padding = 4.0;
};
struct CandidateMenuSize {
  double width, height;
};
inline CandidateMenuSize candidate_menu_size(size_t rows,
                                             const CandidateMenuMetrics &m) {
  if (rows == 0 || rows > 16 || m.width <= 0.0 || m.row_height <= 0.0 ||
      m.padding < 0.0)
    throw std::invalid_argument("Invalid candidate menu metrics");
  return {m.width, m.padding * 2.0 + m.row_height * static_cast<double>(rows)};
}
struct CandidateMenuRow {
  double top, bottom;
};
inline CandidateMenuRow candidate_menu_row(size_t index, size_t rows,
                                           const CandidateMenuMetrics &m) {
  if (index >= rows)
    throw std::invalid_argument("Invalid candidate menu row");
  const double top = m.padding + m.row_height * static_cast<double>(index);
  return {top, top + m.row_height};
}
inline std::optional<size_t>
candidate_menu_hit(double x, double y,
                   const std::vector<CandidateMenuItem> &items,
                   const CandidateMenuMetrics &m) {
  if (items.empty())
    return std::nullopt;
  const auto size = candidate_menu_size(items.size(), m);
  if (x < 0.0 || y < 0.0 || x >= size.width || y >= size.height)
    return std::nullopt;
  for (size_t index = 0; index < items.size(); ++index) {
    const auto row = candidate_menu_row(index, items.size(), m);
    if (y >= row.top && y < row.bottom)
      // A disabled row swallows the click rather than acting on it.
      return items[index].available ? std::optional<size_t>(index)
                                    : std::nullopt;
  }
  return std::nullopt;
}
} // namespace msime::windows
