#ifndef MSIME_CLIENT_H
#define MSIME_CLIENT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

/* ABI 1. All functions return owned, NUL-terminated UTF-8 JSON. Free exactly once
 * using msime_client_string_free, including error responses. Never use free().
 * Responses: {"ok":true,"value":...} or {"ok":false,"error":"..."}.
 * Creation returns a View; its session field is the handle. Handles are confined
 * to their creating thread. Dispatch, focus, view and destroy on that thread.
 * Text and candidate values are copied; no Engine pointers escape.
 */
uint32_t msime_client_abi_version(void);
/* Worker-thread bootstrap: {resources: absolute path, state_root: absolute path}.
 * Verifies pinned resources, delegates working data preparation to Engine and
 * returns HostOptions. Maximum 16384 bytes; no session may use state_root during
 * preparation. Caller publishes the returned config atomically after success.
 */
char *msime_client_prepare_host(const uint8_t *options, size_t length);
/* options is a readable UTF-8 buffer of length bytes; maximum 16384 bytes.
 * Object: api_version=1, resources/user_data/cache/dictionaries (absolute paths),
 * preferences={scheme, candidate_page_size, learning, chinese_punctuation,
 *              shuangpin_profile?}. Missing profile defaults to xiaohe; allowed
 * profiles: xiaohe, ziranma, shoudao, microsoft. Unknown values are rejected.
 * Optional preferences_directory is bootstrap metadata for host file monitoring;
 * session creation itself does not monitor or load it.
 * The host must prepare and validate its dictionary generation before creation.
 */
char *msime_client_create(const uint8_t *options, size_t length);
/* Load PreferencesStore from an absolute UTF-8 directory, without a session.
 * May block on disk/file lock: use a worker thread. Returns PreferencesSnapshot.
 * Missing file returns shared defaults; malformed/future files return errors.
 * Creates the directory/lock file if absent, never overwrites preference contents.
 */
char *msime_client_load_preferences(const uint8_t *directory, size_t length);
/* Same validation as load_preferences; ok:true,value:null means lock busy.
 * Does not wait for the writer lock. Disk I/O may still block: use a worker.
 * Busy is not missing/corrupt and must not reset preferences to defaults. */
char *msime_client_try_load_preferences(const uint8_t *directory, size_t length);
/* Call on the session thread with a PreferencesSnapshot JSON buffer (<=16384):
 * {format_version:1, revision, preferences:{...}}. Revision order is per session;
 * identical retries are allowed, older/conflicting snapshots are rejected.
 * Returns {revision, deferred, view}. Active composition defers application until
 * a successful dispatch/focus leaves it idle. Newer snapshots replace pending ones.
 * Build failure retains the old session and pending snapshot for retry; dispatch
 * reports retry failure in diagnostic without losing completed input.
 * Does not read/write preferences files; the host supplies an already loaded snapshot.
 */
char *msime_client_update_preferences(uint64_t session, const uint8_t *snapshot, size_t length);
char *msime_client_focus(uint64_t session, bool focused);
// Live per-session mode, not a persisted preference. Preserves composition and
// candidate generation; remains authoritative across preference replacement.
char *msime_client_set_chinese_punctuation(uint64_t session, bool enabled);
char *msime_client_character(uint64_t session, uint8_t ascii, bool shift);
// Explicit native punctuation: finish the highlighted composition, then translate.
// Invalid non-punctuation bytes fail without modifying the session.
char *msime_client_punctuation(uint64_t session, uint8_t ascii);
enum MsimeCommand {
    MSIME_BACKSPACE = 0, MSIME_COMMIT_CANDIDATE = 1, MSIME_COMMIT_RAW = 2,
    MSIME_CANCEL = 3, MSIME_MOVE_LEFT = 4, MSIME_MOVE_RIGHT = 5,
    MSIME_MOVE_HOME = 6, MSIME_MOVE_END = 7, MSIME_DELETE_FORWARD = 8,
    MSIME_FINISH_COMPOSITION = 9,
    MSIME_NEXT_PAGE = 100, MSIME_PREVIOUS_PAGE = 101,
    MSIME_NEXT_CANDIDATE = 102, MSIME_PREVIOUS_CANDIDATE = 103,
    // Move highlight within the current page, without editing or committing.
    MSIME_FIRST_CANDIDATE_ON_PAGE = 104, MSIME_LAST_CANDIDATE_ON_PAGE = 105
};
char *msime_client_command(uint64_t session, uint32_t command);
/* Pass the generation and global index from the displayed candidate's id. */
char *msime_client_select(uint64_t session, uint64_t generation, size_t index);
enum MsimeCandidateEdge { MSIME_FIRST_HAN = 0, MSIME_LAST_HAN = 1 };
/* Engine selects one Han character and clears composition on success.
 * A candidate without Han text is unhandled and keeps composition; no fallback
 * punctuation or candidate commit is manufactured. Uses the same current-page
 * identity checks as select. Invalid edge values fail before state changes.
 */
char *msime_client_select_edge(uint64_t session, uint64_t generation, size_t index, uint8_t edge);
/* View.local_mode is the Engine-owned mode, not a preedit-prefix heuristic:
 * View.microsoft_shuangpin reports the applied Engine configuration, never a
 * newer deferred preference. Hosts use it with mode, editing text and caret.
 * none, unicode, date_time, quick_phrase, emoji, kaomoji, super_jianpin,
 * temporary_english, temporary_japanese. Treat unknown as unusable state.
 */
char *msime_client_view(uint64_t session);
char *msime_client_destroy(uint64_t session);
/* value must be NULL or a still-owned pointer returned by this library. */
void msime_client_string_free(char *value);

#ifdef __cplusplus
}
#endif
#endif
