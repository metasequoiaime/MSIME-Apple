//! Exercise shared input routing against the locked production dictionary.
use msime_engine_bridge::{prepare_options, Session};
use msime_input_runtime::{Action, Runtime};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::env::args_os()
        .nth(1)
        .ok_or("usage: runtime_dictionary <verified-dictionary-directory>")?;
    let resources = std::fs::canonicalize(resources)?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "runtime-integration-probe",
    )?;
    let mut runtime = Runtime::new(Session::new(&options)?, 5)?;
    runtime.focus(true)?;
    for byte in b"nihao" {
        runtime.dispatch(Action::Character {
            value: *byte,
            shift: false,
        })?;
    }
    let page = runtime.dispatch(Action::NextPage)?.view;
    assert_eq!(page.page, 1, "probe requires a second candidate page");
    let expected = page.candidates[1].text.clone();
    let selected = runtime.dispatch(Action::Character {
        value: b'2',
        shift: false,
    })?;
    assert!(selected.handled);
    assert_eq!(selected.commit.as_deref(), Some(expected.as_str()));
    // A candidate may consume only the first segment; Engine owns the remainder.
    let finished = runtime.dispatch(Action::Finish)?;
    assert!(finished.view.editing_text.is_empty());
    let idle = runtime.dispatch(Action::Character {
        value: b'2',
        shift: false,
    })?;
    assert!(!idle.handled);
    // Numeric Unicode input must remain owned by Engine, even with candidates visible.
    runtime.dispatch(Action::Character {
        value: b'U',
        shift: true,
    })?;
    for byte in b"4e2d" {
        let result = runtime.dispatch(Action::Character {
            value: *byte,
            shift: false,
        })?;
        assert!(result.handled && result.commit.is_none());
    }
    let result = runtime.dispatch(Action::SelectHighlighted)?;
    assert_eq!(result.commit.as_deref(), Some("中"));
    drop(runtime);
    for chinese in [true, false] {
        options.chinese_punctuation = chinese;
        let mut runtime = Runtime::new(Session::new(&options)?, 5)?;
        runtime.focus(true)?;
        // Obtain Engine's whole-composition result for the highlighted second page.
        for byte in b"nihao" {
            runtime.dispatch(Action::Character {
                value: *byte,
                shift: false,
            })?;
        }
        runtime.dispatch(Action::NextPage)?;
        let expected = runtime.dispatch(Action::Finish)?.commit.unwrap();
        for byte in b"nihao" {
            runtime.dispatch(Action::Character {
                value: *byte,
                shift: false,
            })?;
        }
        runtime.dispatch(Action::NextPage)?;
        let result = runtime.dispatch(Action::Character {
            value: b',',
            shift: false,
        })?;
        assert_eq!(
            result.commit,
            Some(format!("{expected}{}", if chinese { "，" } else { "," }))
        );
        assert!(result.handled && result.view.editing_text.is_empty());
        let idle = runtime.dispatch(Action::Character {
            value: b',',
            shift: false,
        })?;
        assert_eq!(idle.handled, chinese);
        assert_eq!(idle.commit.as_deref(), chinese.then_some("，"));
        if chinese {
            for expected_quote in ["“", "”"] {
                let quote = runtime.dispatch(Action::Character {
                    value: b'"',
                    shift: true,
                })?;
                assert_eq!(quote.commit.as_deref(), Some(expected_quote));
            }
        }
    }
    println!(
        "shared runtime: number selection, Unicode, highlighted punctuation and ASCII mode passed"
    );
    Ok(())
}
