//! The Engine owns handwriting recognition; macOS only locates packaged data.
use std::path::{Path, PathBuf};

pub(crate) fn bundled_model(executable: &Path) -> Option<PathBuf> {
    if !executable.is_absolute() {
        return None;
    }
    let directory = executable.parent()?;
    if directory.file_name()? != "MacOS" {
        return None;
    }
    let contents = directory.parent()?;
    if contents.file_name()? != "Contents" {
        return None;
    }
    let model = contents.join("Resources/handwriting/handwriting-zh_CN.model");
    model.is_file().then_some(model)
}

#[cfg(test)]
mod tests {
    use super::*;
    use msime_input_runtime::{HandwritingPoint, HandwritingQuery};

    #[test]
    fn relocated_bundle_uses_the_fixed_engine_model_for_real_single_character_recognition() {
        let root = tempfile::tempdir().unwrap();
        let executable = root.path().join("Synthetic.app/Contents/MacOS/synthetic");
        assert!(bundled_model(&executable).is_none());
        let resource = root
            .path()
            .join("Synthetic.app/Contents/Resources/handwriting");
        std::fs::create_dir_all(&resource).unwrap();
        let model = resource.join("handwriting-zh_CN.model");
        let source = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../vendor/MSIME-Engine/handwriting/models/handwriting-zh_CN.model");
        std::fs::copy(source, &model).unwrap();
        let resolved = bundled_model(&executable).expect("packaged model");
        assert_eq!(resolved, model);
        assert!(bundled_model(Path::new("Synthetic.app/Contents/MacOS/synthetic")).is_none());
        assert!(bundled_model(&root.path().join("synthetic")).is_none());
        let query = HandwritingQuery {
            language: "zh-CN".into(),
            // Synthetic 中, the same ordered-stroke fixture used by the Engine.
            strokes: vec![
                vec![(35., 40.), (35., 105.)],
                vec![(35., 40.), (125., 40.), (125., 105.)],
                vec![(35., 105.), (125., 105.)],
                vec![(80., 15.), (80., 140.)],
            ]
            .into_iter()
            .map(|stroke| {
                stroke
                    .into_iter()
                    .map(|(x, y)| HandwritingPoint { x, y })
                    .collect()
            })
            .collect(),
        };
        let candidates =
            msime_host_api::handwriting_local_candidates(resolved.to_str().unwrap(), &query)
                .unwrap();
        assert!(candidates.iter().any(|candidate| candidate == "中"));
        assert!(candidates.len() <= 12);
    }

    #[test]
    fn macos_bundle_declares_model_licenses_and_pinned_provenance() {
        let configuration: serde_json::Value =
            serde_json::from_str(include_str!("../tauri.macos.conf.json")).unwrap();
        let resources = configuration["bundle"]["resources"].as_object().unwrap();
        for name in [
            "handwriting-zh_CN.model",
            "HandwritingModel-LICENSE.txt",
            "Zinnia-LICENSE.txt",
            "provenance.json",
        ] {
            assert!(resources
                .values()
                .any(|path| path == &format!("handwriting/{name}")));
        }
        assert_eq!(configuration["bundle"]["active"], true);
    }
}
