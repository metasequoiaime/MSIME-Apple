#include "msime_client.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void success(char *value) {
    assert(value && strstr(value, "\"ok\":true"));
    msime_client_string_free(value);
}

int main(int argc, char **argv) {
    assert(argc == 2);
    assert(msime_client_abi_version() == 1);
    char options[4096];
    int length = snprintf(options, sizeof(options),
        "{\"api_version\":1,\"resources\":\"%s/resources\",\"user_data\":\"%s/user\",\"cache\":\"%s/cache\",\"dictionaries\":\"%s/dictionaries\",\"preferences\":{\"scheme\":\"quanpin\",\"candidate_page_size\":5,\"learning\":false,\"chinese_punctuation\":true}}",
        argv[1], argv[1], argv[1], argv[1]);
    assert(length > 0 && (size_t)length < sizeof(options));
    char *created = msime_client_create((const uint8_t *)options, (size_t)length);
    assert(created && strstr(created, "\"ok\":true"));
    const char *field = strstr(created, "\"session\":");
    assert(field);
    uint64_t handle = strtoull(field + strlen("\"session\":"), NULL, 10);
    msime_client_string_free(created);
    success(msime_client_focus(handle, true));
    success(msime_client_character(handle, 'U', true));
    const char *code = "4e2d";
    for (size_t i = 0; i < strlen(code); ++i) success(msime_client_character(handle, (uint8_t)code[i], false));
    char *result = msime_client_command(handle, MSIME_COMMIT_CANDIDATE);
    assert(result && strstr(result, "\"commit\":\"中\""));
    msime_client_string_free(result);
    for (uint8_t edge = MSIME_FIRST_HAN; edge <= MSIME_LAST_HAN; ++edge) {
        success(msime_client_character(handle, 'U', true));
        for (size_t i = 0; i < strlen(code); ++i) success(msime_client_character(handle, (uint8_t)code[i], false));
        char *view = msime_client_view(handle);
        assert(view && strstr(view, "\"ok\":true"));
        const char *generation_field = strstr(view, "\"generation\":");
        assert(generation_field);
        uint64_t generation = strtoull(generation_field + strlen("\"generation\":"), NULL, 10);
        msime_client_string_free(view);
        result = msime_client_select_edge(handle, generation, 0, edge);
        assert(result && strstr(result, "\"ok\":true") && strstr(result, "\"commit\":\"中\""));
        msime_client_string_free(result);
    }
    success(msime_client_destroy(handle));
    puts("native C consumer: Unicode input, commit and Han edge selection passed");
    return 0;
}
