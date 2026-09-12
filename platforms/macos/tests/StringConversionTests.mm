#include "../src/StringConversion.h"

#include <stdexcept>
#include <string>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}
} // namespace

int main()
{
    @autoreleasepool
    {
        Require([MetasequoiaStringFromUtf8("") isEqualToString:@""], "An empty UTF-8 string did not remain empty.");
        Require([MetasequoiaStringFromUtf8("水杉 input") isEqualToString:@"水杉 input"],
                "Valid UTF-8 text changed during conversion.");

        const std::string embeddedNull("a\0b", 3);
        NSString *embeddedNullString = MetasequoiaStringFromUtf8(embeddedNull);
        Require(embeddedNullString != nil && embeddedNullString.length == 3 &&
                    [embeddedNullString characterAtIndex:1] == 0,
                "An embedded NUL truncated UTF-8 conversion.");

        const std::string invalidLead("valid\xfftext", 10);
        NSString *invalidLeadString = MetasequoiaStringFromUtf8(invalidLead);
        Require(invalidLeadString != nil && [invalidLeadString isEqualToString:@"valid�text"],
                "An invalid UTF-8 lead byte was not replaced safely.");

        const std::string truncatedSequence("end\xe4\xb8", 5);
        NSString *truncatedString = MetasequoiaStringFromUtf8(truncatedSequence);
        Require(truncatedString != nil && [truncatedString isEqualToString:@"end�"],
                "A truncated UTF-8 sequence was not replaced safely.");

        NSArray<NSString *> *uniqueValues = @[ @"first", invalidLeadString, @"last" ];
        Require(MetasequoiaUniqueStringIndex(uniqueValues, invalidLeadString) == 1,
                "A uniquely displayed sanitized candidate did not retain its array index.");
        Require(MetasequoiaUniqueStringIndex(uniqueValues, @"missing") == NSNotFound,
                "A missing display candidate unexpectedly resolved to an index.");
        Require(MetasequoiaUniqueStringIndex(@[ invalidLeadString, truncatedString ], @"valid�text") == 0,
                "Different sanitized candidates were not compared by their complete display text.");
        Require(MetasequoiaUniqueStringIndex(@[ invalidLeadString, invalidLeadString ], invalidLeadString) ==
                    NSNotFound,
                "An ambiguous sanitized candidate resolved to the wrong engine index.");

        NSAttributedString *firstCollision = MetasequoiaIndexedCandidateString(@"乾", 0);
        NSAttributedString *secondCollision = MetasequoiaIndexedCandidateString(@"乾", 1);
        Require([firstCollision.string isEqualToString:secondCollision.string],
                "The collision fixture did not preserve identical visible text.");
        Require(MetasequoiaCandidateIndex(firstCollision) == 0 && MetasequoiaCandidateIndex(secondCollision) == 1,
                "Identical visible candidates did not preserve distinct engine identities.");
        Require(MetasequoiaCandidateIndex([[NSAttributedString alloc] initWithString:@"乾"]) == NSNotFound,
                "An unindexed candidate unexpectedly resolved to an engine identity.");
        NSAttributedString *translated = MetasequoiaCandidateStringByAddingTranslation(firstCollision, @"dry; heaven");
        Require([translated.string isEqualToString:@"乾"] && MetasequoiaCandidateIndex(translated) == 0 &&
                    [MetasequoiaCandidateTranslation(translated) isEqualToString:@"dry; heaven"],
                "A candidate gloss did not travel with the original engine identity.");
        Require(MetasequoiaCandidateStringByAddingTranslation(firstCollision, @"") == firstCollision &&
                    MetasequoiaCandidateTranslation(firstCollision) == nil,
                "An empty gloss still annotated the candidate.");
    }
    return 0;
}
