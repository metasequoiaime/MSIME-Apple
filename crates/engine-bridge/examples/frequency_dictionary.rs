//! Exercise frequency policies on isolated copies of the locked dictionary.
use msime_engine_bridge::{prepare_options, Session};

fn candidates(session: &mut Session) -> Result<Vec<String>, cxx::Exception> {
    session.character(b'n', false)?;
    session.character(b'i', false)?;
    Ok(session.snapshot()?.candidates)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: frequency_dictionary <verified-resources>")?,
    )?;
    for (mode, learning) in [
        ("disabled", true),
        ("pin", true),
        ("halve", true),
        ("linear", true),
        ("promote", true),
        ("promote", false),
    ] {
        let temporary = tempfile::tempdir()?;
        let mut options = prepare_options(
            resources.to_str().unwrap(),
            temporary.path().join("user").to_str().unwrap(),
            temporary.path().join("cache").to_str().unwrap(),
            "frequency-fixture",
        )?;
        options.learning = learning;
        options.helpcode = false;
        options.mixed_english = false;
        options.frequency_mode = mode.into();
        options.frequency_trigger_count = 2;
        options.frequency_linear_step = 2;
        let mut session = Session::new(&options)?;
        let before = candidates(&mut session)?
            .iter()
            .position(|word| word == "拟")
            .ok_or("fixture candidate missing")?;
        assert!(before > 0);
        let first = session.select(before)?;
        assert!(first.has_commit && first.commit == "拟" && first.diagnostic.is_empty());
        let middle = candidates(&mut session)?
            .iter()
            .position(|word| word == "拟")
            .unwrap();
        assert_eq!(middle, before, "threshold must delay ranking changes");
        let second = session.select(middle)?;
        assert!(second.has_commit && second.commit == "拟" && second.diagnostic.is_empty());
        drop(session);
        // Reopen to ensure the new order is persisted, not just a view mutation.
        let mut reopened = Session::new(&options)?;
        let after = candidates(&mut reopened)?
            .iter()
            .position(|word| word == "拟")
            .unwrap();
        let expected = match mode {
            _ if !learning => before,
            "disabled" => before,
            "pin" => 0,
            "halve" => before / 2,
            "linear" => before.saturating_sub(2),
            "promote" => before - 1,
            _ => unreachable!(),
        };
        assert_eq!(after, expected, "{mode} persisted the wrong candidate rank");
        println!("{mode}, learning={learning}: threshold and persisted candidate order passed ({before} -> {after})");
    }
    Ok(())
}
