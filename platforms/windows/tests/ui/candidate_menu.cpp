#include "CandidateMenu.h"
#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Candidate menu test failed at line " +
                             std::to_string(line));
}
} // namespace
#define require(...) require_at((__VA_ARGS__), __LINE__)

int main() {
  try {
    // Same eligibility the IBus host applies before calling the shared entry
    // points: Japanese has no persistable entry, and only these sources can be
    // written back to the user dictionary.
    require(candidate_actions_available(0, 0));
    require(candidate_actions_available(0, 1));
    require(candidate_actions_available(0, 4));
    require(!candidate_actions_available(candidate_scheme_japanese, 0));
    require(!candidate_actions_available(0, 2)); // cloud
    require(!candidate_actions_available(0, 3)); // AI
    require(!candidate_actions_available(0, 5));

    // Reference order and labels (candidate_presenter.cpp:688-737):
    // 置顶, 第 1..5 位, 取消固定, then 删除 when it applies.
    const auto free_candidate = candidate_menu_items(true, 0, "我们");
    require(free_candidate.size() == 1 + candidate_fix_slots + 1 + 1);
    require(free_candidate[0].command == CandidateMenuCommand::Pin);
    require(free_candidate[0].label == "置顶");
    require(free_candidate[1].command == CandidateMenuCommand::Fix);
    require(free_candidate[1].position == 1);
    require(free_candidate[1].label == "第 1 位");
    require(free_candidate[5].position == candidate_fix_slots);
    require(free_candidate[6].command == CandidateMenuCommand::Clear);
    require(free_candidate.back().command == CandidateMenuCommand::Remove);
    require(free_candidate.back().label == "删除");
    // Nothing is fixed yet, so releasing a slot is offered but disabled.
    require(!free_candidate[6].available);
    for (const auto &item : free_candidate)
      require(!item.checked);

    // The reference OMITS the delete row for a single code point rather than
    // showing it disabled, so one character cannot be deleted by mistake.
    require(candidate_code_points("我") == 1);
    require(candidate_code_points("我们") == 2);
    // A non-BMP character is one code point, not two.
    require(candidate_code_points("𠮷") == 1);
    const auto single = candidate_menu_items(true, 0, "我");
    require(single.size() == free_candidate.size() - 1);
    for (const auto &item : single)
      require(item.command != CandidateMenuCommand::Remove);
    require(candidate_menu_items(true, 0, "𠮷").size() == single.size());
    // The reference rule is codePoints != 1, so empty text keeps the delete row.
    // A real candidate is never empty; this pins the rule rather than a guess.
    require(candidate_code_points("") == 0);
    require(candidate_menu_items(true, 0, "").size() == free_candidate.size());

    // A candidate fixed to slot 3 marks that row and enables release.
    const auto fixed = candidate_menu_items(true, 3, "我们");
    require(fixed[3].position == 3 && fixed[3].checked);
    require(!fixed[1].checked && !fixed[2].checked);
    require(fixed[6].command == CandidateMenuCommand::Clear && fixed[6].available);

    // An ineligible candidate keeps its rows visible but inert.
    const auto inert = candidate_menu_items(false, 3, "我们");
    require(inert.size() == free_candidate.size());
    for (const auto &item : inert)
      require(!item.available);

    // Geometry and hit testing.
    const CandidateMenuMetrics metrics;
    const auto size = candidate_menu_size(free_candidate.size(), metrics);
    require(size.width == metrics.width);
    require(size.height ==
            metrics.padding * 2.0 +
                metrics.row_height * static_cast<double>(free_candidate.size()));
    const auto first = candidate_menu_hit(10.0, metrics.padding + 1.0,
                                          free_candidate, metrics);
    require(first && *first == 0);
    const auto second = candidate_menu_hit(
        10.0, metrics.padding + metrics.row_height + 1.0, free_candidate, metrics);
    require(second && *second == 1);
    // Outside the card in either axis.
    require(!candidate_menu_hit(-1.0, 10.0, free_candidate, metrics));
    require(!candidate_menu_hit(10.0, -1.0, free_candidate, metrics));
    require(!candidate_menu_hit(size.width, 10.0, free_candidate, metrics));
    require(!candidate_menu_hit(10.0, size.height, free_candidate, metrics));
    // A disabled row swallows the click rather than acting on it.
    const auto clear_row = candidate_menu_row(6, free_candidate.size(), metrics);
    require(!candidate_menu_hit(10.0, clear_row.top + 1.0, free_candidate, metrics));
    const auto enabled_clear =
        candidate_menu_hit(10.0, clear_row.top + 1.0, fixed, metrics);
    require(enabled_clear && *enabled_clear == 6);

    std::cout << "Candidate menu: rows, eligibility and hit test\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}
