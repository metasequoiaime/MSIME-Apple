#pragma once

#include "CandidatePageSize.h"
#include <metasequoia/session.h>

#include <cstddef>
#include <optional>
#include <string>
#include <utility>

namespace metasequoia::mac
{
class CandidateSelectionState
{
  public:
    static constexpr size_t candidates_per_page = 9;

    void begin_navigation()
    {
        accepts_selection_changes_ = true;
        selected_candidate_.reset();
    }

    void update(size_t candidate_index, std::string candidate)
    {
        if (accepts_selection_changes_)
        {
            selected_candidate_ = Selection{candidate_index, std::move(candidate)};
        }
    }

    void reset()
    {
        accepts_selection_changes_ = false;
        selected_candidate_.reset();
    }

    std::optional<size_t> selected_index() const
    {
        return selected_candidate_.has_value() ? std::optional<size_t>(selected_candidate_->index) : std::nullopt;
    }

    // A tracked index only means something while the candidate list still holds the same word at
    // it. The list is rebuilt on every keystroke, so an index kept across one is not the candidate
    // the user was looking at.
    std::optional<size_t> live_selected_index(const SessionSnapshot &snapshot) const
    {
        if (!selected_candidate_.has_value())
        {
            return std::nullopt;
        }
        const auto &candidates = snapshot.candidates;
        if (selected_candidate_->index < candidates.size()
            && candidates[selected_candidate_->index].word == selected_candidate_->word)
        {
            return selected_candidate_->index;
        }
        return std::nullopt;
    }

    KeyResult commit(Session &session) const
    {
        if (const auto index = live_selected_index(session.snapshot()))
        {
            const KeyResult selected = session.select(*index);
            if (selected.handled)
            {
                return selected;
            }
        }
        return session.command(Command::CommitCandidate);
    }

    KeyResult commit_number(Session &session, char character, size_t pageSize = candidates_per_page) const
    {
        if (character < '1' || character > '9')
        {
            return {};
        }

        pageSize = NormalizeCandidatePageSize(pageSize);
        const size_t candidateOffset = static_cast<size_t>(character - '1');
        if (candidateOffset >= pageSize)
        {
            return {};
        }

        const auto snapshot = session.snapshot();
        const auto &candidates = snapshot.candidates;
        if (!selected_candidate_.has_value() || selected_candidate_->index >= candidates.size()
            || candidates[selected_candidate_->index].word != selected_candidate_->word)
        {
            return session.candidate_key(character);
        }

        const size_t pageStart = selected_candidate_->index / pageSize * pageSize;
        return session.select(pageStart + candidateOffset);
    }

  private:
    struct Selection
    {
        size_t index;
        std::string word;
    };

    bool accepts_selection_changes_ = false;
    std::optional<Selection> selected_candidate_;
};
} // namespace metasequoia::mac
