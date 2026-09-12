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
    msime_client_key_event event = {{1, 2, 3}, 0x41, 30, 0x0f, 'a', false};
    assert(msime_client_key_event_valid(&event));
    event.lease.token = 0;
    assert(!msime_client_key_event_valid(&event));
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
    char *nine_key = msime_client_set_nine_key_mode(handle, true);
    assert(nine_key && strstr(nine_key, "\"nine_key\":true"));
    msime_client_string_free(nine_key);
    success(msime_client_set_nine_key_mode(handle, false));
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
    success(msime_client_character(handle, 'T', true));
    success(msime_client_character(handle, 'r', false));
    success(msime_client_character(handle, 'q', false));
    char *all_candidates = msime_client_all_candidates(handle);
    assert(all_candidates && strstr(all_candidates, "\"ok\":true") && strstr(all_candidates, "\"preedit\":\"Trq\""));
    const char *generation_field = strstr(all_candidates, "\"generation\":");
    assert(generation_field);
    uint64_t generation = strtoull(generation_field + strlen("\"generation\":"), NULL, 10);
    msime_client_string_free(all_candidates);
    result = msime_client_select_any_candidate(handle, generation, 5);
    assert(result && strstr(result, "\"ok\":true") && strstr(result, "\"commit\":"));
    msime_client_string_free(result);
    success(msime_client_destroy(handle));
    puts("native C consumer: input, edge and complete-candidate selection passed");
    return 0;
}
