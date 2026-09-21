//! The punctuation the reference's guide names by hand, typed against the real dictionary.
//!
//! The guide's 标点与以词定字 section lists six marks that are not simply the ASCII key's Chinese
//! twin: `\` gives 、, a backtick gives ·, and four shifted keys give ……, ——, 《 and 》. They come
//! from the Engine's table rather than from any host, which is exactly why nothing checked them
//! here: the shared tests use a synthetic engine, and the host tests never leave the host.
//!
//! usage: punctuation_table <verified-dictionary-directory>

use msime_engine_bridge::{prepare_options, Session};
use msime_input_runtime::{Action, Runtime};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: punctuation_table <verified-dictionary-directory>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "punctuation-table-probe",
    )?;
    options.chinese_punctuation = true;

    // The guide's own list, in its own order.
    let expected = [
        ('\\', "、"),
        ('`', "·"),
        ('^', "……"),
        ('_', "——"),
        ('<', "《"),
        ('>', "》"),
    ];
    for (typed, mark) in expected {
        let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
        runtime.focus(true)?;
        let result = runtime.dispatch(Action::Punctuation(typed as u8))?;
        assert_eq!(
            result.commit.as_deref(),
            Some(mark),
            "{typed} committed {:?}",
            result.commit
        );
    }

    // With Chinese punctuation off none of them is rewritten. The Engine declines the key rather
    // than committing an ASCII twin - typing the raw character is the host's job from there - so the
    // check is that nothing Chinese comes back, which is what that switch means.
    options.chinese_punctuation = false;
    for (typed, mark) in expected {
        let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
        runtime.focus(true)?;
        let result = runtime.dispatch(Action::Punctuation(typed as u8))?;
        assert_ne!(
            result.commit.as_deref(),
            Some(mark),
            "{typed} still produced {mark} with Chinese punctuation off"
        );
        if let Some(commit) = result.commit.as_deref() {
            assert!(
                commit.is_ascii(),
                "{typed} with Chinese punctuation off committed {commit:?}"
            );
        }
    }

    println!("punctuation table: 、 · …… —— 《 》 all arrive as the guide describes, and stay ASCII when Chinese punctuation is off");
    Ok(())
}
