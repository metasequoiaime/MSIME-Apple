#import "ChineseTextConversion.h"

#include "msime_client.h"

NSString *MetasequoiaChineseOutputString(NSString *text, BOOL traditionalOutput) {
    if (!traditionalOutput || text.length == 0) return text;
    // The shared OpenCC s2t tables, the same phrase-level conversion the reference server ships. A character table cannot tell 头发 (頭髮) from 发展 (發展); CFStringTransform was one.
    const char *utf8 = text.UTF8String;
    if (!utf8) return text;
    char *converted = msime_client_simplified_to_traditional(reinterpret_cast<const uint8_t *>(utf8), strlen(utf8));
    if (!converted) return text;
    NSString *result = [NSString stringWithUTF8String:converted];
    msime_client_string_free(converted);
    return result ?: text;
}
