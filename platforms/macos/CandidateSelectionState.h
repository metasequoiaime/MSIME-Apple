#pragma once
#include "CandidatePageSize.h"
#include <metasequoia/session.h>
#include <cstddef>
#include <optional>
#include <string>
#include <utility>
namespace metasequoia::mac {
class CandidateSelectionState {
public:
    static constexpr size_t candidates_per_page = 9;
    void begin_navigation() { accepts_selection_changes_ = true; selected_candidate_.reset(); }
    void update(size_t index, std::string word) { if (accepts_selection_changes_) selected_candidate_ = Selection{index, std::move(word)}; }
    void reset() { accepts_selection_changes_ = false; selected_candidate_.reset(); }
    std::optional<size_t> selected_index() const { return selected_candidate_ ? std::optional<size_t>(selected_candidate_->index) : std::nullopt; }
    std::optional<size_t> live_selected_index(const SessionSnapshot &snapshot) const {
        if (!selected_candidate_ || selected_candidate_->index >= snapshot.candidates.size() || snapshot.candidates[selected_candidate_->index].word != selected_candidate_->word) return std::nullopt;
        return selected_candidate_->index;
    }
    KeyResult commit(Session &session) const {
        if (const auto index = live_selected_index(session.snapshot())) { const auto selected = session.select(*index); if (selected.handled) return selected; }
        return session.command(Command::CommitCandidate);
    }
    KeyResult commit_number(Session &session, char character, size_t page_size = candidates_per_page) const {
        if (character < '1' || character > '9') return {};
        page_size = NormalizeCandidatePageSize(page_size);
        const size_t offset = static_cast<size_t>(character - '1');
        if (offset >= page_size) return {};
        const auto snapshot = session.snapshot();
        if (!selected_candidate_ || selected_candidate_->index >= snapshot.candidates.size() || snapshot.candidates[selected_candidate_->index].word != selected_candidate_->word) return session.candidate_key(character);
        return session.select(selected_candidate_->index / page_size * page_size + offset);
    }
private:
    struct Selection { size_t index; std::string word; };
    bool accepts_selection_changes_ = false;
    std::optional<Selection> selected_candidate_;
};
}
