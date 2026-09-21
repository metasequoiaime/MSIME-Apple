#pragma once

#include <cstddef>
#include <string>
#include <string_view>

namespace msime::linux_host {

// The composition as the user should see it while a phrase is being assembled.
//
// Picking a candidate that covers only part of the input leaves the Engine composing the rest and
// hands back the piece that was picked. With `phrase_preedit` requested, the runtime holds that
// piece in `view.phrase_prefix` instead of committing it, and the host draws it ahead of the
// reading - which is what the reference does, prepending `word_for_creating_word` and moving the
// caret past it. A host that asks for the piece and does not draw it shows nothing at all for text
// the user already chose, so the two go together (`scripts/test-phrase-preedit-hosts.py`).
//
// The caret is the reason this is a function rather than a `+`. The runtime's `caret_position` is a
// byte offset into the reading, which is ASCII; the prefix is not, and the two front ends count
// their cursors differently - fcitx5 takes a byte offset into the string it was given, while IBus
// takes a position in Unicode scalars. Both are produced here so neither has to convert, and so
// the conversion is tested once.
struct PhrasePreedit
{
    std::string text;
    std::size_t caret_bytes = 0;
    std::size_t caret_scalars = 0;
};

// Scalars, not bytes: the count of UTF-8 lead bytes, which is what a well-formed string has one of
// per character. Malformed input cannot make this exceed the byte length.
inline std::size_t utf8_scalar_count(std::string_view text)
{
    std::size_t count = 0;
    for (unsigned char byte : text)
        if ((byte & 0xC0u) != 0x80u)
            ++count;
    return count;
}

// Whether the composition on screen should be the kana rather than the letters that produced it.
//
// A Japanese composition is かな: that is what the user means, what the candidates are for, and
// what Enter commits. The Engine hands over both, `editing_text` for the romaji and `reading` for
// the kana, and every other scheme leaves the reading empty.
//
// The exception is a caret the user has moved into the middle of the letters. The Engine's offset
// is an offset into the romaji and there is no map from it into the kana, so rather than draw the
// caret somewhere it does not belong, that case keeps showing what the caret belongs to. Typing
// never reaches it - the caret sits at the end until an arrow key moves it.
inline bool composition_shows_reading(std::string_view reading, std::size_t caret,
                                      std::size_t editing_length)
{
    return !reading.empty() && caret >= editing_length;
}

inline PhrasePreedit compose_phrase_preedit(std::string_view prefix, std::string_view editing,
                                            std::size_t caret)
{
    // A caret past the end of the reading is the Engine and the host disagreeing about a
    // composition that has already moved on; clamping keeps the cursor inside the string rather
    // than handing a toolkit an offset it will read past.
    if (caret > editing.size())
        caret = editing.size();
    PhrasePreedit composed;
    composed.text.reserve(prefix.size() + editing.size());
    composed.text.append(prefix);
    composed.text.append(editing);
    composed.caret_bytes = prefix.size() + caret;
    composed.caret_scalars = utf8_scalar_count(prefix) + utf8_scalar_count(editing.substr(0, caret));
    return composed;
}

} // namespace msime::linux_host
