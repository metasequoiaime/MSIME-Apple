#pragma once

#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <string>

// Candidate snapshots outlive the Engine response and are copied by vector
// growth and the presenter. Unlike the composition's borrowed CStringRange,
// each candidate text owns its storage with ordinary value semantics.
class CCandidateText
{
  public:
    void Set(const wchar_t *text, std::size_t length)
    {
        if (!text && length) throw std::invalid_argument("Missing candidate text");
        std::wstring value = length ? std::wstring(text, length) : std::wstring();
        _text.swap(value);
    }
    const wchar_t *Get() const { return _text.c_str(); }
    std::size_t GetLength() const { return _text.size(); }
    void Clear() { _text.clear(); }
    std::wstring ToWString() const { return _text; }

  private:
    std::wstring _text;
};

struct CCandidateListItem
{
    CCandidateText _ItemString;
    CCandidateText _FindKeyCode;
    uint64_t _EngineSession = 0;
    uint64_t _EngineGeneration = 0;
    std::size_t _EngineIndex = 0;
    bool _EngineHighlighted = false;
    bool MatchesEngineView(uint64_t session, uint64_t generation) const
    {
        return _EngineSession != 0 && _EngineGeneration != 0 &&
               _EngineSession == session && _EngineGeneration == generation;
    }
};
