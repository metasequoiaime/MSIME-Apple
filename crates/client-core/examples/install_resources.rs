//! Development bootstrap for the reviewed desktop dictionary release.
//! Does not activate a generation or modify an installed input method.
use msime_client_core::resources::{ResourceSet, ResourceStore};
use std::io::Read;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = std::env::args_os()
        .nth(1)
        .ok_or("usage: install_resources <resource-cache-directory>")?;
    let specification: ResourceSet = serde_json::from_str(include_str!(
        "../../../resources/desktop-dictionary.lock.json"
    ))?;
    let client = reqwest::blocking::Client::builder()
        .https_only(true)
        .connect_timeout(std::time::Duration::from_secs(15))
        .timeout(std::time::Duration::from_secs(300))
        .build()?;
    // Engine-sourced artifacts come from the pinned checkout rather than the dictionary release.
    // fetch_engine.py has already verified that tree against engine-lock.json, and install()
    // checks this artifact's own SHA-256 either way.
    let engine = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../vendor/MSIME-Engine");
    let destination = ResourceStore::new(root).install(&specification, |artifact| {
        eprintln!("Verifying {}", artifact.name);
        if !artifact.engine_path.is_empty() {
            let path = engine.join(&artifact.engine_path);
            let file = std::fs::File::open(&path).map_err(|error| {
                std::io::Error::other(format!(
                    "{}: {error}; run scripts/fetch_engine.py first",
                    path.display()
                ))
            })?;
            return Ok(Box::new(file) as Box<dyn Read>);
        }
        let response = client
            .get(&artifact.url)
            .send()
            .and_then(|response| response.error_for_status())
            .map_err(std::io::Error::other)?;
        Ok(Box::new(response) as Box<dyn Read>)
    })?;
    println!("{}", destination.display());
    Ok(())
}
