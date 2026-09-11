//! Verify independent local-mode entry gates with isolated production resources.
use msime_engine_bridge::{prepare_options, Session};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: local_modes_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "local-modes-fixture",
    )?;
    let modes = [
        (b'U', "unicode"),
        (b'T', "date_time"),
        (b'K', "quick_phrase"),
        (b'E', "emoji"),
        (b'M', "kaomoji"),
        (b'J', "super_jianpin"),
        (b'Y', "temporary_english"),
        (b'R', "temporary_japanese"),
    ];
    for (index, (letter, name)) in modes.into_iter().enumerate() {
        let mut enabled = Session::new(&options)?;
        enabled.character(letter, true)?;
        assert_eq!(enabled.snapshot()?.local_mode, name);
        let mut disabled = options.clone();
        match index {
            0 => disabled.local_unicode = false,
            1 => disabled.local_date_time = false,
            2 => disabled.local_quick_phrase = false,
            3 => disabled.local_emoji = false,
            4 => disabled.local_kaomoji = false,
            5 => disabled.local_super_jianpin = false,
            6 => disabled.local_temporary_english = false,
            7 => disabled.local_temporary_japanese = false,
            _ => unreachable!(),
        }
        let mut session = Session::new(&disabled)?;
        session.character(letter, true)?;
        assert_eq!(session.snapshot()?.local_mode, "none");
        let (other_letter, other_name) = modes[(index + 1) % modes.len()];
        let mut other = Session::new(&disabled)?;
        other.character(other_letter, true)?;
        assert_eq!(other.snapshot()?.local_mode, other_name);
        println!("{name}: enabled entry and disabled fallback passed");
    }
    Ok(())
}
