use std::path::PathBuf;
use std::process::ExitCode;

fn usage() {
    eprintln!("Usage: MetasequoiaImeDictionaryReplay.exe --data-dir <directory>");
}

fn main() -> ExitCode {
    let mut args = std::env::args_os().skip(1);
    let Some(flag) = args.next() else {
        usage();
        return ExitCode::from(2);
    };
    if flag != "--data-dir" {
        usage();
        return ExitCode::from(2);
    }
    let Some(directory) = args.next() else {
        usage();
        return ExitCode::from(2);
    };
    if args.next().is_some() {
        usage();
        return ExitCode::from(2);
    }

    let directory = PathBuf::from(directory);
    if !directory.is_absolute() {
        eprintln!("The data directory must be an absolute path.");
        return ExitCode::from(2);
    }
    let user_db = directory.join("msime_user.db");
    let main_db = directory.join("msime.db");
    let english_db = directory.join("english.db");
    let Some(user_db) = user_db.to_str() else {
        eprintln!("The data directory is not valid UTF-8.");
        return ExitCode::from(2);
    };
    let Some(main_db) = main_db.to_str() else {
        eprintln!("The data directory is not valid UTF-8.");
        return ExitCode::from(2);
    };
    let Some(english_db) = english_db.to_str() else {
        eprintln!("The data directory is not valid UTF-8.");
        return ExitCode::from(2);
    };
    let (applied, skipped, failed, error) =
        msime_engine_bridge::replay_user_dictionary(user_db, main_db, english_db);
    if !error.is_empty() || failed != 0 {
        eprintln!("User dictionary replay failed.");
        return ExitCode::from(1);
    }
    println!("Applied {applied} user dictionary operations; skipped {skipped}.");
    ExitCode::SUCCESS
}
