//! The document side of a candidate window rendered as HTML.
//!
//! The reference offers two renderers for its candidate window: Direct2D, which is what this
//! repository has, and a WebView2 document, chosen by `ui_backend`. The document's markup lives in
//! `packages/ui/src/upstream/candidate-themes/` here already - an outer page per orientation and a
//! body fragment per appearance - and the two contracts that turn a keystroke's candidates into
//! that markup are in this module rather than in a host, because nothing in them is
//! Windows-specific.
//!
//! The rest of that renderer is a WebView2 host window and is not here. What is missing and why is
//! recorded in `docs/windows-parity.md`.

/// Split the payload a host writes into a candidate document.
///
/// Slot 0 is the preedit and slots 1-9 are the candidates on the current page, joined with `,`.
/// Kaomoji legitimately contain ASCII commas - `(・∀・)` is tame, but `¯\_(ツ)_/¯` has siblings that
/// do not survive a naive split - so a writer escapes a literal comma as `\u{f000}`, a private-use
/// code point no candidate can contain, and this restores it.
///
/// The trailing-field rule follows the reference's `std::getline` loop rather than a plain split: a
/// payload ending in `,` yields no final empty field, because the stream reaches end-of-input with
/// nothing extracted. `a,,b` still yields three fields, the middle one empty - that is a real empty
/// slot, not an artefact.
pub fn split_candidate_payload(payload: &str) -> Vec<String> {
    if payload.is_empty() {
        return Vec::new();
    }
    let mut fields: Vec<String> = payload
        .split(',')
        .map(|field| field.replace('\u{f000}', ","))
        .collect();
    if payload.ends_with(',') {
        fields.pop();
    }
    fields
}

/// Fill a candidate body fragment with one page's payload.
///
/// The fragment carries `{0}`-`{9}` where the text goes and `<!--nAnchor-->` before the markup for
/// slot `n`. Fewer candidates than slots is the normal case, so the result is cut at the anchor of
/// the first unused slot: the rows that would have been empty are not emitted at all, rather than
/// emitted blank and hidden by CSS.
///
/// A fragment without the anchor for that slot is left whole, which is what the reference's
/// `find` + `substr` does with a missing marker. Only the outer page is a full document, and this
/// is never applied to it - it contains the renderer's JavaScript, whose braces are not placeholders.
pub fn inflate_candidate_template(template: &str, payload: &str) -> String {
    let fields = split_candidate_payload(payload);
    let mut result = String::with_capacity(template.len());
    let mut rest = template;
    while let Some(start) = rest.find('{') {
        result.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        let slot = after
            .strip_prefix(|c: char| c.is_ascii_digit())
            .and_then(|tail| tail.strip_prefix('}'))
            .map(|tail| (after.as_bytes()[0] - b'0') as usize);
        match slot {
            Some(index) => {
                result.push_str(fields.get(index).map(String::as_str).unwrap_or(""));
                rest = &after[2..];
            }
            None => {
                result.push('{');
                rest = after;
            }
        }
    }
    result.push_str(rest);

    if fields.len() < 10 {
        let anchor = format!("<!--{}Anchor-->", fields.len());
        if let Some(position) = result.find(&anchor) {
            result.truncate(position);
        }
    }
    result
}

/// Inline the shared contract scripts into a renderer page.
///
/// The pages load `schema.js` and `runtime.js` from a virtual host. Inlining them removes a
/// round trip through the host's resource handler for two files that never change during a session.
///
/// `None` when either script is empty or either tag is absent: a page that does not declare the
/// imports is a custom or legacy one, and rewriting it on a guess would be worse than leaving it to
/// fetch as written.
///
/// `</` inside a script's source is escaped to `<\/`. That sequence is what would otherwise close
/// the surrounding `script` element early - the parser does not care that it is inside a JavaScript
/// string literal - and the backslash is invisible to JavaScript, which reads `\/` as `/`.
pub fn inline_protocol_scripts(html: &str, schema: &str, runtime: &str) -> Option<String> {
    const SCHEMA_TAG: &str = r#"<script src="https://msime-contracts/schema.js"></script>"#;
    const RUNTIME_TAG: &str = r#"<script src="https://msime-contracts/runtime.js"></script>"#;
    if schema.is_empty() || runtime.is_empty() {
        return None;
    }
    if !html.contains(SCHEMA_TAG) || !html.contains(RUNTIME_TAG) {
        return None;
    }
    let inline = |source: &str| format!("<script>{}</script>", source.replace("</", "<\\/"));
    Some(
        html.replacen(SCHEMA_TAG, &inline(schema), 1)
            .replacen(RUNTIME_TAG, &inline(runtime), 1),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payload_fields_follow_the_reference_split() {
        assert_eq!(split_candidate_payload(""), Vec::<String>::new());
        assert_eq!(split_candidate_payload("ni"), vec!["ni"]);
        assert_eq!(split_candidate_payload("ni,你,拟"), vec!["ni", "你", "拟"]);
        // A trailing separator is not a trailing empty slot.
        assert_eq!(split_candidate_payload("ni,你,"), vec!["ni", "你"]);
        // An empty slot between two filled ones is real and is kept.
        assert_eq!(split_candidate_payload("ni,,拟"), vec!["ni", "", "拟"]);
        // A lone separator is one empty field, then end of input.
        assert_eq!(split_candidate_payload(","), vec![""]);
    }

    #[test]
    fn escaped_commas_come_back_as_commas() {
        // The case the escape exists for: a kaomoji containing ASCII commas.
        let payload = "hehe,(\u{f000}_\u{f000}),^_^";
        assert_eq!(
            split_candidate_payload(payload),
            vec!["hehe", "(,_,)", "^_^"]
        );
    }

    #[test]
    fn a_full_page_fills_every_slot_and_keeps_the_whole_fragment() {
        let template = "<!--0Anchor-->{0}<!--1Anchor-->{1}<!--2Anchor-->{2}";
        assert_eq!(
            inflate_candidate_template(template, "ni,你,拟,泥,逆,腻,匿,溺,昵,妮"),
            "<!--0Anchor-->ni<!--1Anchor-->你<!--2Anchor-->拟"
        );
    }

    #[test]
    fn a_short_page_is_cut_at_the_first_unused_slot() {
        let template = "<!--0Anchor-->{0}<!--1Anchor-->{1}<!--2Anchor-->{2}<!--3Anchor-->{3}";
        // Preedit plus two candidates: slot 3 onwards is never emitted.
        assert_eq!(
            inflate_candidate_template(template, "ni,你,拟"),
            "<!--0Anchor-->ni<!--1Anchor-->你<!--2Anchor-->拟"
        );
    }

    #[test]
    fn a_fragment_without_the_anchor_is_left_whole() {
        // The reference's find/substr leaves the string alone when the marker is absent, and a
        // renderer page that never declared the anchor is not one to truncate on a guess.
        let template = "{0}|{1}|{2}";
        assert_eq!(inflate_candidate_template(template, "ni,你"), "ni|你|");
    }

    #[test]
    fn braces_that_are_not_slots_survive() {
        // The body fragments carry no JavaScript, but a skin author's fragment may carry braces,
        // and dropping them would corrupt the markup rather than fail loudly.
        let template = "<style>.row {color: red}</style>{0}<!--1Anchor-->";
        assert_eq!(
            inflate_candidate_template(template, "ni"),
            "<style>.row {color: red}</style>ni"
        );
    }

    /// The fragment this repository actually ships, not a synthetic one.
    ///
    /// The tests above pin the rules; this one pins that the rules match the file. The fragment was
    /// vendored from the reference, so a mismatch would mean the contract drifted from the markup -
    /// and nothing else in this repository reads that file today, so nothing else would notice.
    #[test]
    fn the_vendored_fragment_renders_a_page_of_candidates() {
        let fragment = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join(
            "../../packages/ui/src/upstream/candidate-themes/vertical_candidate_window_dark.html",
        );
        let template = std::fs::read_to_string(&fragment)
            .unwrap_or_else(|error| panic!("{}: {error}", fragment.display()));

        let page = inflate_candidate_template(&template, "ni,你,拟,泥");
        assert!(page.contains(r#"<div class="text">ni<span class="cursor"></span></div>"#));
        for (number, candidate) in [("1", "你"), ("2", "拟"), ("3", "泥")] {
            assert!(
                page.contains(&format!(
                    r#"<span class="cand-no">{number}</span><span class="cand-content">{candidate}</span>"#
                )),
                "candidate {number} is missing from the rendered page"
            );
        }
        // Four fields means slots 4-9 are unused, so their rows are cut rather than left blank.
        assert!(!page.contains(r#"<span class="cand-no">4</span>"#));
        assert!(!page.contains("Anchor-->\n<div class=\"row-wrapper\">\n  <div class=\"row cand\">\n    <div class=\"text\"><span class=\"cand-no\">5</span>"));
        // Nothing unfilled is left behind either.
        assert!(!page.contains("{0}") && !page.contains("{4}"));
    }

    #[test]
    fn scripts_are_inlined_only_when_both_tags_are_there() {
        let page = concat!(
            "<html><head>",
            r#"<script src="https://msime-contracts/schema.js"></script>"#,
            r#"<script src="https://msime-contracts/runtime.js"></script>"#,
            "</head></html>"
        );
        let inlined = inline_protocol_scripts(page, "const schema = 1;", "const runtime = 2;")
            .expect("both tags present");
        assert!(inlined.contains("<script>const schema = 1;</script>"));
        assert!(inlined.contains("<script>const runtime = 2;</script>"));
        assert!(!inlined.contains("msime-contracts"));

        // Either script empty, or either tag missing: leave the page to fetch as written.
        assert!(inline_protocol_scripts(page, "", "const runtime = 2;").is_none());
        assert!(inline_protocol_scripts(page, "const schema = 1;", "").is_none());
        assert!(inline_protocol_scripts("<html></html>", "a", "b").is_none());
    }

    #[test]
    fn an_end_tag_inside_a_script_cannot_close_it_early() {
        let page = concat!(
            r#"<script src="https://msime-contracts/schema.js"></script>"#,
            r#"<script src="https://msime-contracts/runtime.js"></script>"#
        );
        // The source contains the one sequence that would end the element early, in the spelling a
        // parser acts on regardless of the JavaScript string it sits inside.
        let inlined = inline_protocol_scripts(page, r#"const tag = "</script>";"#, "x")
            .expect("both tags present");
        assert!(inlined.contains(r#"const tag = "<\/script>";"#));
        // Exactly the two elements this inlined, and no third one opened by the escape.
        assert_eq!(inlined.matches("<script>").count(), 2);
        assert_eq!(inlined.matches("</script>").count(), 2);
    }
}
