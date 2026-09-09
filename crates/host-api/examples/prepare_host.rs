use std::io::Write;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 2 {
        return Err(
            "usage: prepare_host <verified-resource-directory> <new-host-state-directory>".into(),
        );
    }
    let state = std::path::Path::new(&args[1]);
    let document =
        msime_host_api::prepare_host_configuration(std::path::Path::new(&args[0]), state)?;
    let mut temporary = tempfile::NamedTempFile::new_in(state)?;
    temporary.write_all(document.as_bytes())?;
    temporary.as_file().sync_all()?;
    let path = state.join("runtime-options.json");
    temporary.persist(&path)?;
    println!("{}", std::fs::canonicalize(path)?.display());
    Ok(())
}
