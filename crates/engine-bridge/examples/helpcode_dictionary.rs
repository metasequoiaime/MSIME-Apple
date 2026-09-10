//! Validate helpcode filtering with synthetic tables and the locked dictionary.
//! Never modifies the supplied resource generation or redistributes upstream tables.
use msime_engine_bridge::{prepare_options, Session};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let source = std::env::args_os()
        .nth(1)
        .ok_or("usage: helpcode_dictionary <verified-resources>")?;
    let source = std::fs::canonicalize(source)?;
    let temporary = tempfile::tempdir()?;
    let resources = temporary.path().join("resources");
    std::fs::create_dir_all(resources.join("helpcodes"))?;
    for name in [
        "msime.db",
        "english.db",
        "others.db",
        "dict_japanese.dat",
        "dictionary-manifest.json",
        "mozc_dictionary_oss_README.txt",
    ] {
        std::fs::copy(source.join(name), resources.join(name))?;
    }
    let schemas = [
        ("lantian", "helpcode.txt"),
        ("ziranma", "zrm_helpcode_big_unique.txt"),
        ("shouyou2_0", "shouyou2_0_helpcode.txt"),
        ("shouyouplus", "shouyouplus_helpcode.txt"),
        ("xiaohe", "xiaohe_helpcode.txt"),
    ];
    for (index, (_, name)) in schemas.iter().enumerate() {
        // Reverse the mapping in alternate tables so schema selection is observable.
        let table = if index % 2 == 0 {
            "你=ab\n拟=cd\n"
        } else {
            "你=cd\n拟=ab\n"
        };
        std::fs::write(resources.join("helpcodes").join(name), table)?;
    }
    let mut options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "synthetic-helpcode-probe",
    )?;
    for scheme in [0, 1] {
        options.scheme = scheme;
        for (index, (schema, _)) in schemas.iter().enumerate() {
            options.helpcode_schema = (*schema).into();
            for enabled in [true, false] {
                options.helpcode = enabled;
                let mut session = Session::new(&options)?;
                session.character(b'n', false)?;
                session.character(b'i', false)?;
                let before = session.snapshot()?.candidates;
                assert!(before.iter().any(|word| word == "你"));
                assert!(before.iter().any(|word| word == "拟"));
                let result = session.character(b'A', true)?;
                if enabled {
                    assert!(result.handled);
                    let expected = if index % 2 == 0 { "你" } else { "拟" };
                    assert_eq!(
                        session.snapshot()?.candidates.first().map(String::as_str),
                        Some(expected)
                    );
                } else {
                    assert!(!result.handled);
                    assert_eq!(session.snapshot()?.candidates, before);
                }
            }
        }
    }
    println!(
        "Synthetic helpcode filtering: five schemas, both pinyin schemes, enabled/disabled passed"
    );
    Ok(())
}
