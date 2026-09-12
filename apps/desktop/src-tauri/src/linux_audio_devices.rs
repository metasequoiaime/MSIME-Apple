use serde::Serialize;
use serde_json::Value;
use std::time::Duration;

#[derive(Serialize)]
pub struct CaptureDevice {
    backend: &'static str,
    id: String,
    label: String,
}

fn add(devices: &mut Vec<CaptureDevice>, backend: &'static str, id: &str, label: &str) {
    if devices.len() >= 256 || id.is_empty() || id.len() > 512 || id.chars().count() > 128
        || id.chars().any(char::is_control)
        || devices.iter().any(|device| device.backend == backend && device.id == id)
    {
        return;
    }
    let label: String = label.chars().filter(|c| !c.is_control()).take(160).collect();
    devices.push(CaptureDevice { backend, id: id.to_owned(), label: if label.is_empty() { id.to_owned() } else { label } });
}

fn output(program: &str, args: &[&str]) -> Option<String> {
    crate::linux_process::read_text(program, args, 1024 * 1024, Duration::from_secs(2))
}

pub fn list() -> Vec<CaptureDevice> {
    let mut devices = Vec::new();
    if let Some(Value::Array(sources)) = output("pactl", &["--format=json", "list", "sources"])
        .and_then(|text| serde_json::from_str(&text).ok())
    {
        for source in sources {
            let Some(id) = source.get("name").and_then(Value::as_str) else { continue };
            // Monitor sources record playback, rather than microphone input.
            if id.ends_with(".monitor") { continue; }
            add(&mut devices, "pulse", id, source.get("description").and_then(Value::as_str).unwrap_or(id));
        }
    }
    if let Some(Value::Array(nodes)) = output("pw-dump", &[])
        .and_then(|text| serde_json::from_str(&text).ok())
    {
        for node in nodes {
            if node.get("type").and_then(Value::as_str) != Some("PipeWire:Interface:Node") { continue; }
            let props = &node["info"]["props"];
            if !matches!(props["media.class"].as_str(), Some("Audio/Source" | "Audio/Source/Virtual")) { continue; }
            let Some(id) = props["node.name"].as_str() else { continue };
            let label = props["node.description"].as_str().or_else(|| props["node.nick"].as_str()).unwrap_or(id);
            add(&mut devices, "pipewire", id, label);
        }
    }
    if let Some(text) = output("arecord", &["-L"]) {
        let mut lines = text.lines().peekable();
        while let Some(line) = lines.next() {
            if line.is_empty() || line.starts_with(char::is_whitespace) || line == "null" { continue; }
            let label = lines.peek().filter(|next| next.starts_with(char::is_whitespace)).map(|next| next.trim()).unwrap_or(line);
            add(&mut devices, "alsa", line, label);
        }
    }
    devices
}
