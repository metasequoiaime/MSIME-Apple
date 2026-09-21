#include "CandidateTranslationPolicy.h"

#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using namespace msime::windows;
namespace {
void require(bool value, int line) {
  if (!value)
    throw std::runtime_error("candidate translation merge failed at line " +
                             std::to_string(line));
}
#define REQUIRE(value) require((value), __LINE__)
using Answered = std::vector<std::pair<std::string, std::string>>;
using Texts = std::vector<std::string>;
} // namespace

int main() {
  try {
    // The whole point of the rule: a candidate the packaged dictionary already
    // answered is not sent to a provider. The worker appends provider answers
    // to the same list, so asking again both spends a request and can leave one
    // candidate carrying two glosses.
    const Answered local{{"你好", "hello"}};
    REQUIRE(untranslated_texts(local, Texts{"你好", "世界"}) == Texts{"世界"});
    REQUIRE(untranslated_texts(local, Texts{"你好"}).empty());

    // With nothing answered locally - no packaged gloss for this page, which is
    // the ordinary case for Chinese words - every planned candidate is asked
    // about, in the plan's order.
    REQUIRE(untranslated_texts(Answered{}, Texts{"世界", "你好"}) ==
            (Texts{"世界", "你好"}));

    // A text planned twice is asked about once. The caller walks the result
    // against a provider batch and would otherwise send a duplicate.
    REQUIRE(untranslated_texts(Answered{}, Texts{"你好", "你好"}) ==
            Texts{"你好"});

    // An entry with no gloss is not an answer. Nobody has translated that
    // candidate, so the provider is still the only chance it has.
    //
    // This half cannot be reached from the worker's own producer today: the
    // shared candidate gloss request drops empty glosses before the worker sees
    // them. It is this function's contract rather than a second line of
    // defence, and it is asserted here because the function is what a future
    // caller reads - not because the assertion can go red from that producer.
    REQUIRE(untranslated_texts(Answered{{"你好", ""}}, Texts{"你好"}) ==
            Texts{"你好"});

    // An entry for some other text answers nothing here.
    REQUIRE(untranslated_texts(Answered{{"世界", "world"}}, Texts{"你好"}) ==
            Texts{"你好"});

    // Empty plan entries are dropped rather than asked about: an empty text is
    // not a candidate, and the provider request would be rejected anyway.
    REQUIRE(untranslated_texts(Answered{}, Texts{"", "你好", ""}) ==
            Texts{"你好"});

    // Nothing planned means nothing to ask, whatever is already answered.
    REQUIRE(untranslated_texts(local, Texts{}).empty());

    // The senses split, which shares this header. Both separators, and the
    // first non-empty sense is what Ctrl+Enter commits.
    REQUIRE(first_translation_sense("hello; hi") == "hello");
    REQUIRE(first_translation_sense("；世界") == "世界");
    REQUIRE(first_translation_sense("   ").empty());

    std::cout << "candidate translation merge policy ok\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
