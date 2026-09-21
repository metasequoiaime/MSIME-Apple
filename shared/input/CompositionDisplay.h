#pragma once

#include <cstddef>
#include <string_view>

namespace msime::input {

// Whether the composition on screen should be the kana rather than the letters that produced it.
//
// A Japanese composition is かな: that is what the user means, what the candidates are for, and what
// Enter commits. The Engine hands over both - `editing_text` for the romaji and `reading` for the
// kana - and every other scheme leaves the reading empty, so this answers for all of them.
//
// The exception is a caret the user has moved into the middle of the letters. The Engine's offset
// is an offset into the romaji and there is no map from it into the kana, so rather than draw the
// caret somewhere it does not belong, that case keeps showing what the caret belongs to. Typing
// never reaches it - the caret sits at the end until an arrow key moves it.
//
// Every host asks the same question, and the hosts that ask it are written in three different
// languages against three different toolkits; what they can share is this line and its reason.
inline bool composition_shows_reading(std::string_view reading, std::size_t caret,
                                      std::size_t editing_length)
{
    return !reading.empty() && caret >= editing_length;
}

} // namespace msime::input
