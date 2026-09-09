//! Read-only verification of an already downloaded, pinned resource set.
use msime_client_core::resources::{ResourceSet, ResourceStore};
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let directory = std::env::args_os()
        .nth(1)
        .ok_or("usage: verify_resources <resource-directory>")?;
    let directory = std::fs::canonicalize(directory)?;
    let specification: ResourceSet = serde_json::from_str(include_str!(
        "../../../resources/desktop-dictionary.lock.json"
    ))?;
    ResourceStore::new(&directory).verify(&directory, &specification)?;
    for artifact in specification.artifacts {
        println!("{}", artifact.name);
    }
    Ok(())
}
