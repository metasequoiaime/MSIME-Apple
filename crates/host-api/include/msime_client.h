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
 * Creation acquires cooperative shared access to user_data and dictionaries until
 * destroy. It fails immediately while a participating maintenance writer holds
 * exclusive access. Existing sessions are never cancelled for maintenance.
 * Linux hosts may provide absolute online_provider_socket and
 * translation_provider_socket paths for user-managed Unix-socket services;
 * translation may reuse the online socket when omitted.
 * Do not delete .msime-dictionary-access.lock files. Legacy/external writers do
 * not participate; preparation/upgrades still require stopped sessions.
 */
char *msime_client_create(const uint8_t *options, size_t length);
/* Management JSON (<=65536 bytes), trusted native caller only:
 * {options: <same HostOptions as create>, action: {operation:"list",offset:0,limit:100}}
 * or action:{operation:"edit",previous:null|Entry,replacement:null|Entry,request_id:"..."}.
 * Batch import: action:{operation:"import",kind:"pinyin"|"wubi"|"quick_phrase"|"english",
 * format:"standard"|"windows"|"rime"|"hans",text:"word<TAB>code<TAB>weight\\n",request_id:"..."}.
 * Standard rows are word, code, weight; Windows rows are code, word, weight. Rime rows are
 * word, code, optional weight and may include YAML front matter between --- and ...; Rime's
 * metadata weights (for example c=3 d=0.12) use the default 10000. Omitted weights use 10000.
 * The hans format is pinyin-only and accepts one pure Han phrase per line; Engine resolves
 * each phrase to its highest-ranked canonical pinyin and uses weight 10000.
 * Import accepts at most 1000 rows and returns {applied}; rows are committed
 * with deterministic receipt IDs derived from request_id so retries are safe.
 * Export: action:{operation:"export",kind,format:"standard"|"windows",offset,limit} returns
 * {text,has_more}; use pages of at most 1000 rows. Standard output is word, code, weight.
 * Entry:{kind:"pinyin"|"wubi"|"quick_phrase"|"english",key,value,weight}.
 * List returns {entries,has_more}; edit returns {applied:true}. Errors are redacted.
 * Native host owns/authorizes paths; never accept arbitrary webview paths or log payloads.
 * Run on a worker thread. Edit returns busy until all participating sessions are
 * destroyed, then holds exclusive access; recreate sessions after success.
 * Do not automatically cancel user input to obtain access. Retry ambiguous writes
 * with the identical nonempty request ID and content.
 */
char *msime_client_dictionary(const uint8_t *request, size_t length);
/* Snapshot lifecycle. Version is a redacted SHA-256 binding the canonical
 * resource/user/cache/dictionary paths and one consistent Engine journal.
 * Prepare/discard are native-only; a prepared handle is not active until a
 * future activation transaction publishes it. The prepare callback returns
 * one UTF-8 JSON record into the supplied buffer, 0 only at verified EOF, and
 * a negative value for cancellation, truncation, or checksum failure. */
typedef intptr_t (*msime_client_snapshot_next)(void *context, uint8_t *buffer, size_t capacity);
char *msime_client_snapshot_version(const uint8_t *options, size_t length);
char *msime_client_snapshot_prepare(const uint8_t *request, size_t length,
                                     msime_client_snapshot_next next, void *context);
char *msime_client_snapshot_discard(uint64_t handle);
char *msime_client_snapshot_activate(uint64_t handle, const uint8_t *expected_version, size_t length);
/* Load PreferencesStore from an absolute UTF-8 directory, without a session.
 * May block on disk/file lock: use a worker thread. Returns PreferencesSnapshot.
 * Missing file returns shared defaults; malformed/future files return errors.
 * Creates the directory/lock file if absent, never overwrites preference contents.
 */
char *msime_client_load_preferences(const uint8_t *directory, size_t length);
/* Private aggregate typing statistics. JSON request (<=65536 bytes):
 * {directory:absolute path,action:{operation:"load"|"reset"}}
 * {directory,action:{operation:"set_enabled",enabled:bool}}
 * {directory,action:{operation:"record",text,source,day:"YYYY-MM-DD"}}.
 * Record classifies committed text in memory and persists only aggregate counts;
 * text is never returned or stored. May block on disk/file lock: use a worker.
 */
char *msime_client_typing_statistics(const uint8_t *request, size_t length);
/* Scan an absolute UTF-8 skin root and return the catalog the settings page
 * sees: {packages:[...],issues:[...]}. Reads the directory: use a worker.
 * An unreadable root is an empty catalog; an invalid package becomes an issue
 * and is never returned as renderable. Presenters must still check that a
 * package supports the layout and theme before adopting its colors.
 * Keys are camelCase, the same document the settings page consumes. */
char *msime_client_skin_catalog(const uint8_t *directory, size_t length);
/* Read saved history only; disabled preferences return an empty entries array. */
char *msime_client_load_clipboard_history(const uint8_t *directory, size_t length);
/* JSON {directory,text}; removes exact saved entry, not the system clipboard. */
char *msime_client_remove_clipboard_history(const uint8_t *request, size_t length);
/* JSON {directory,text}; capture under the shared preference/history locks. */
char *msime_client_capture_clipboard_history(const uint8_t *request, size_t length);
/* Same validation as load_preferences; ok:true,value:null means lock busy.
 * Does not wait for the writer lock. Disk I/O may still block: use a worker.
 * Busy is not missing/corrupt and must not reset preferences to defaults. */
char *msime_client_try_load_preferences(const uint8_t *directory, size_t length);
/* Compare-and-swap save of PreferencesSnapshot.preferences. The snapshot's
 * format_version is validated; expected_revision must match the store. */
char *msime_client_save_preferences(const uint8_t *directory, size_t directory_length,
                                    uint64_t expected_revision,
                                    const uint8_t *snapshot, size_t snapshot_length);
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
/* Clear the current session's Engine candidate cache and refresh its view. */
char *msime_client_reset_cache(uint64_t session);
char *msime_client_voice_start(uint64_t session);
char *msime_client_voice_cancel(uint64_t session);
char *msime_client_voice_apply(uint64_t session, uint64_t generation,
                               const uint8_t *text, size_t length);
/* Pure DeepLX-compatible descriptor builder (no network I/O). Request <=16 KiB:
 * {config:{enabled,endpoint,api_key},text,source_language,target_language}.
 * Returns null if disabled; otherwise {url,method,headers,body,timeout_ms,max_response_bytes}.
 * Descriptor can contain credentials: never log it. Host enforces timeout/size,
 * rejects redirects and checks HTTP status before parsing. Text <=40 scalars. */
char *msime_client_custom_translation_http_request(const uint8_t *request, size_t length);
/* Provider body <=1 MiB. Returns translation string <=4096 bytes or null when
 * malformed/no result. No session mutation; host validates original identity. */
char *msime_client_parse_custom_translation_response(const uint8_t *body, size_t length);
/* Apply JSON [{"text":"candidate","translation":"gloss"}] for a candidate generation. */
char *msime_client_apply_translations(uint64_t session, uint64_t generation,
                                      const uint8_t *translations, size_t length);
/* Resolve copied candidates against the packaged offline English dictionary.
 * JSON request: {generation,candidates:[{text,source}]}; the generation is
 * echoed for the host to pass to apply_translations on the session thread.
 * This function owns no session handle and may run on a worker thread. */
char *msime_client_candidate_gloss_request(const uint8_t *request, size_t request_length,
                                           const uint8_t *resources, size_t resources_length);
// Live per-session mode, not a persisted preference. Preserves composition and
// candidate generation; remains authoritative across preference replacement.
char *msime_client_set_chinese_punctuation(uint64_t session, bool enabled);
char *msime_client_set_character_width(uint64_t session, bool fullwidth);
char *msime_client_set_english_mode(uint64_t session, bool enabled);
/* Engine-owned quanpin nine-key mode. Call only after finishing composition.
 * View.nine_key and View.nine_key_spellings are authoritative. Enabling for
 * another scheme or changing mode during composition is rejected.
 * View.touch_keyboard_layout is the applied host presentation preference; a
 * Japanese nine-key host uses it without enabling Engine quanpin nine-key. */
char *msime_client_set_nine_key_mode(uint64_t session, bool enabled);
char *msime_client_set_paired_punctuation(uint64_t session, bool enabled);
char *msime_client_set_punctuation_lock(uint64_t session, uint8_t lock);
char *msime_client_set_candidate_page_size(uint64_t session, uint8_t size);
char *msime_client_character(uint64_t session, uint8_t ascii, bool shift);
// Explicit native punctuation: finish the highlighted composition, then translate.
// Invalid non-punctuation bytes fail without modifying the session.
char *msime_client_punctuation(uint64_t session, uint8_t ascii);
// Finish the highlighted composition, then append the literal ASCII mark.
// Hosts use this for platform smart-punctuation decisions based on editor
// context; invalid non-punctuation bytes fail without modifying the session.
char *msime_client_punctuation_ascii(uint64_t session, uint8_t ascii);
enum MsimeCommand {
    MSIME_BACKSPACE = 0, MSIME_COMMIT_CANDIDATE = 1, MSIME_COMMIT_RAW = 2,
    MSIME_CANCEL = 3, MSIME_MOVE_LEFT = 4, MSIME_MOVE_RIGHT = 5,
    MSIME_MOVE_HOME = 6, MSIME_MOVE_END = 7, MSIME_DELETE_FORWARD = 8,
    MSIME_FINISH_COMPOSITION = 9,
    MSIME_NEXT_PAGE = 100, MSIME_PREVIOUS_PAGE = 101,
    MSIME_NEXT_CANDIDATE = 102, MSIME_PREVIOUS_CANDIDATE = 103,
    MSIME_FIRST_CANDIDATE_ON_PAGE = 104, MSIME_LAST_CANDIDATE_ON_PAGE = 105
};
char *msime_client_command(uint64_t session, uint32_t command);
/* Pass the generation and global index from the displayed candidate's id. */
char *msime_client_select(uint64_t session, uint64_t generation, size_t index);
/* Select any entry copied by msime_client_all_candidates for this exact
 * generation. Normal select remains restricted to the current View page. */
char *msime_client_select_any_candidate(uint64_t session, uint64_t generation, size_t index);
char *msime_client_pin_candidate(uint64_t session, uint64_t generation, size_t index);
char *msime_client_remove_candidate(uint64_t session, uint64_t generation, size_t index);
/* Fix a dictionary candidate to slot 1..5 for the current input context. */
char *msime_client_fix_candidate_position(uint64_t session, uint64_t generation, size_t index,
                                          uint8_t position);
/* Clear a previously fixed dictionary candidate position. */
char *msime_client_clear_candidate_position(uint64_t session, uint64_t generation, size_t index);
/* Select an entry from View.nine_key_spellings. The generation rejects stale UI. */
char *msime_client_choose_nine_key_spelling(uint64_t session, uint64_t generation, size_t index);
enum MsimeCandidateEdge { MSIME_FIRST_HAN = 0, MSIME_LAST_HAN = 1 };
/* Engine selects one Han character and clears composition on success.
 * A candidate without Han text is unhandled and keeps composition; no fallback
 * punctuation or candidate commit is manufactured. Uses the same current-page
 * identity checks as select. Invalid edge values fail before state changes.
 */
char *msime_client_select_edge(uint64_t session, uint64_t generation, size_t index, uint8_t edge);
/* On-demand {session,generation,preedit,candidates:[Candidate...]}. Unlike View,
 * candidates contains the complete cached Engine generation with global IDs. */
char *msime_client_all_candidates(uint64_t session);
/* View.local_mode is the Engine-owned mode, not a preedit-prefix heuristic:
 * View.microsoft_shuangpin reports the applied Engine configuration, never a
 * newer deferred preference. Hosts use it with mode, editing text and caret.
 * none, unicode, date_time, quick_phrase, emoji, kaomoji, super_jianpin,
 * temporary_english, temporary_japanese. Treat unknown as unusable state.
 */
char *msime_client_view(uint64_t session);
/* Return a copied OnlineQuery JSON object, or null when the current composition
 * is not eligible for an online provider. Linux responses may include the
 * validated ai_assistant provider/model/prompt configuration (never its token).
 * The document also carries the validated cloud_candidates preference so a
 * user-owned provider can distinguish cloud suggestions from AI suggestions.
 * The caller may perform provider work off-thread and pass the unchanged
 * document back to apply_online_candidate. */
char *msime_client_online_query(uint64_t session);
/* Return null or {generation,target_language,candidates:[{text}],
 * custom_translation:{enabled,endpoint,api_key}|null} for visible candidate
 * translations. The optional custom provider fields are present only when
 * enabled in validated preferences and are intended for the user-owned Linux
 * translation service.
 */
char *msime_client_translation_query(uint64_t session);
/* Build the bounded HTTPS cloud URL for an eligible OnlineQuery. The native
 * host performs network I/O and applies the copied result separately. */
char *msime_client_cloud_request_url(const uint8_t *query, size_t query_length);
/* Parse a host-fetched response using the shared cloud parser. Returns
 * {applied,view}; no-result/malformed provider documents do not mutate input.
 * Query <=16 KiB, response <=256 KiB. Stale queries and disabled cloud
 * preferences (including a pending disable) cannot apply candidates. */
char *msime_client_apply_cloud_response(uint64_t session,
                                      const uint8_t *query, size_t query_length,
                                      const uint8_t *body, size_t body_length);
/* Linux: perform one bounded request to a user-owned Unix-socket provider.
 * Call from a worker thread with a copied query; returns null value when no
 * candidate is available. Credentials and network policy stay in that service. */
char *msime_client_online_provider_request(const uint8_t *query,
                                           size_t query_length,
                                           const uint8_t *socket_path,
                                           size_t socket_length);
/* Linux: forward one validated account-backed dictionary operation to a
 * user-owned Unix-socket provider. The provider owns credentials and sync. */
char *msime_client_cloud_dictionary_provider_request(const uint8_t *request,
                                                     size_t request_length,
                                                     const uint8_t *socket_path,
                                                     size_t socket_length);
/* Linux: forward one validated cloud clipboard operation to a user-owned
 * Unix-socket provider. The provider owns credentials and retention policy. */
char *msime_client_cloud_clipboard_provider_request(const uint8_t *request,
                                                    size_t request_length,
                                                    const uint8_t *socket_path,
                                                    size_t socket_length);
char *msime_client_translation_provider_request(const uint8_t *query,
                                                size_t query_length,
                                                const uint8_t *socket_path,
                                                size_t socket_length);
/* Linux handwriting panel adapter. The query is a bounded JSON object with
 * language and normalized stroke arrays; the user-owned socket returns
 * {candidates:[...]} and owns recognizer/model policy. */
char *msime_client_handwriting_provider_request(const uint8_t *query,
                                                size_t query_length,
                                                const uint8_t *socket_path,
                                                size_t socket_length);
/* Run the optional offline Engine recognizer against a trusted packaged model.
 * The model path must be absolute; response is {candidates:[...]} or an error. */
char *msime_client_handwriting_local_request(const uint8_t *query,
                                             size_t query_length,
                                             const uint8_t *model_path,
                                             size_t model_length);
/* Linux standalone emoji panel adapter. The query contains search/category
 * text and a bounded result limit; the socket returns {items:[...]}. */
char *msime_client_emoji_provider_request(const uint8_t *query,
                                          size_t query_length,
                                          const uint8_t *socket_path,
                                          size_t socket_length);
/* Query the verified local others.db Emoji catalog. Resources is an absolute
 * generation directory containing others.db; no provider socket is needed.
 * Optional offset is a nonnegative SQL row offset (default 0); limit is 1..255.
 * Optional group filters a catalog subdivision; list_groups:true returns
 * {groups:[name,...]} in catalog order instead of an item page.
 * list_symbol_groups:true returns {symbol_groups:[{parent,title},...]}.
 * Optional parent narrows symbols to a parent category before paging.
 * Advance offset by limit, not returned item count: each page deduplicates text. */
char *msime_client_emoji_catalog_request(const uint8_t *query,
                                         size_t query_length,
                                         const uint8_t *resources,
                                         size_t resources_length);
/* Linux voice adapter. The user-owned socket captures audio and runs ASR,
 * returning {text}; the query contains language and the active generation. */
char *msime_client_voice_provider_request(const uint8_t *query,
                                          size_t query_length,
                                          const uint8_t *socket_path,
                                          size_t socket_length);
typedef void (*msime_client_voice_update_callback)(const uint8_t *text,
                                                   size_t text_length,
                                                   bool final,
                                                   void *context);
/* Stream newline-delimited provider updates. The callback runs on the caller
 * thread and receives bounded interim/final UTF-8 text; context is untouched. */
char *msime_client_voice_provider_stream(
    const uint8_t *query, size_t query_length, const uint8_t *socket_path,
    size_t socket_length, msime_client_voice_update_callback callback,
    void *context);
/* Optional phase notifications: 0=recording, 1=recognizing, 2=polishing.
 * Both callbacks run synchronously on the caller thread and must not throw. */
typedef void (*msime_client_voice_status_callback)(uint8_t phase, void *context);
char *msime_client_voice_provider_stream_events(
    const uint8_t *query, size_t query_length, const uint8_t *socket_path,
    size_t socket_length, msime_client_voice_update_callback callback,
    msime_client_voice_status_callback status_callback, void *context);
/* Normalized microphone level in [0, 1]; never transcript text or audio.
 * Callback runs synchronously on the caller thread and must not throw. */
typedef void (*msime_client_voice_level_callback)(float level, void *context);
char *msime_client_voice_provider_stream_feedback(
    const uint8_t *query, size_t query_length, const uint8_t *socket_path,
    size_t socket_length, msime_client_voice_update_callback callback,
    msime_client_voice_status_callback status_callback,
    msime_client_voice_level_callback level_callback, void *context);
/* Request cancellation of a provider capture session by generation. */
char *msime_client_voice_provider_cancel(const uint8_t *socket_path,
                                         size_t socket_length,
                                         uint64_t generation);
/* Ask the provider to finish capture and deliver the final stream result. */
char *msime_client_voice_provider_stop(const uint8_t *socket_path,
                                       size_t socket_length,
                                       uint64_t generation);
/* Apply a UTF-8 cloud (source=0) or AI (source=1) result for a copied query. */
char *msime_client_apply_online_candidate(uint64_t session,
                                           const uint8_t *query,
                                           size_t query_length,
                                           const uint8_t *candidate,
                                           size_t candidate_length,
                                           uint8_t source);
/* Apply a JSON array of UTF-8 strings for one source (cloud=0, AI=1).
 * Buffers are borrowed for the call; at most 16384 bytes each. */
char *msime_client_apply_online_candidates(uint64_t session,
                                          const uint8_t *query,
                                          size_t query_length,
                                          const uint8_t *candidates,
                                          size_t candidates_length,
                                          uint8_t source);
char *msime_client_destroy(uint64_t session);
/* value must be NULL or a still-owned pointer returned by this library. */
void msime_client_string_free(char *value);

#ifdef __cplusplus
}
#endif
#endif
