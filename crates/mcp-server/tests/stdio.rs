//! The server as an agent sees it: the built binary spoken to over stdio by the SDK's own client, against a synthetic dictionary and state directory.

use rmcp::model::{CallToolRequestParams, CallToolResult};
use rmcp::service::RunningService;
use rmcp::{RoleClient, ServiceExt};
use serde_json::{json, Value};
use std::path::Path;
use std::process::Stdio;
use std::time::Duration;
use tokio::process::{Child, Command};

/// A data root the Engine opens: the smallest dictionary it accepts, as the host-api tests build it, and a runtime-options document pointing at it.
fn fixture(root: &Path) -> std::path::PathBuf {
    let tables = "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER);
                  CREATE TABLE wubi86(key TEXT,value TEXT,weight INTEGER);
                  CREATE TABLE quick_parases(key TEXT,value TEXT,weight INTEGER);
                  CREATE INDEX idx_quick_parases_key_weight ON quick_parases(key,weight DESC);";
    for name in ["resources", "dictionaries"] {
        let path = root.join(name);
        std::fs::create_dir(&path).unwrap();
        rusqlite::Connection::open(path.join("msime.db"))
            .unwrap()
            .execute_batch(tables)
            .unwrap();
    }
    std::fs::create_dir(root.join("user")).unwrap();
    let text = root.to_str().unwrap();
    let options = root.join("runtime-options.json");
    let document = json!({
        "api_version": 1,
        "resources": format!("{text}/resources"),
        "user_data": format!("{text}/user"),
        "cache": format!("{text}/cache"),
        "dictionaries": format!("{text}/dictionaries"),
        "preferences": msime_client_core::preferences::Preferences::default(),
        "preferences_directory": text,
    });
    std::fs::write(&options, serde_json::to_vec_pretty(&document).unwrap()).unwrap();
    options
}

async fn start(options: &Path, allow_write: bool) -> (RunningService<RoleClient, ()>, Child) {
    let mut command = Command::new(env!("CARGO_BIN_EXE_msime-mcp"));
    command.arg("--options").arg(options);
    if allow_write {
        command.arg("--allow-write");
    }
    // The test machine's own input method must not leak in.
    for name in [
        "MSIME_CLIENT_HOST_OPTIONS",
        "MSIME_IBUS_OPTIONS",
        "MSIME_CLIENT_STATE_DIR",
    ] {
        command.env_remove(name);
    }
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .kill_on_drop(true)
        .spawn()
        .unwrap();
    let transport = (child.stdout.take().unwrap(), child.stdin.take().unwrap());
    (().serve(transport).await.unwrap(), child)
}

async fn call(
    client: &RunningService<RoleClient, ()>,
    name: &'static str,
    arguments: Value,
) -> CallToolResult {
    let Value::Object(arguments) = arguments else {
        panic!("arguments must be an object");
    };
    client
        .call_tool(CallToolRequestParams::new(name).with_arguments(arguments))
        .await
        .unwrap()
}

/// The structured result of a call that succeeded.
async fn ok(
    client: &RunningService<RoleClient, ()>,
    name: &'static str,
    arguments: Value,
) -> Value {
    let result = call(client, name, arguments).await;
    assert_ne!(
        result.is_error,
        Some(true),
        "{name} failed: {:?}",
        result.content
    );
    result.structured_content.expect("a structured result")
}

/// The text of a call that the server refused.
async fn refused(
    client: &RunningService<RoleClient, ()>,
    name: &'static str,
    arguments: Value,
) -> String {
    let result = call(client, name, arguments).await;
    assert_eq!(result.is_error, Some(true), "{name} should have failed");
    serde_json::to_string(&result.content).unwrap()
}

/// Writes are spaced a second apart by the server.
async fn after_write_interval() {
    tokio::time::sleep(Duration::from_millis(1100)).await;
}

async fn tool_names(client: &RunningService<RoleClient, ()>) -> Vec<String> {
    let mut names: Vec<String> = client
        .list_all_tools()
        .await
        .unwrap()
        .into_iter()
        .map(|tool| tool.name.to_string())
        .collect();
    names.sort();
    names
}

#[tokio::test]
async fn read_only_by_default() {
    let directory = tempfile::tempdir().unwrap();
    let options = fixture(directory.path());
    let (client, _child) = start(&options, false).await;

    let info = client.peer_info().unwrap();
    assert_eq!(info.server_info.as_ref().unwrap().name, "msime");
    assert_eq!(
        tool_names(&client).await,
        [
            "get_preferences",
            "get_typing_statistics",
            "list_quick_phrases"
        ]
    );
    let page = ok(&client, "list_quick_phrases", json!({})).await;
    assert_eq!(page, json!({ "phrases": [], "has_more": false }));
    // A write tool that is not offered cannot be called either.
    assert!(client
        .call_tool(
            CallToolRequestParams::new("edit_quick_phrases")
                .with_arguments(json!({ "edits": [] }).as_object().unwrap().clone())
        )
        .await
        .is_err());
    client.cancel().await.unwrap();
}

#[tokio::test]
#[cfg(not(windows))]
async fn an_agent_manages_quick_phrases_and_preferences() {
    let directory = tempfile::tempdir().unwrap();
    let options = fixture(directory.path());
    let (client, _child) = start(&options, true).await;
    assert_eq!(tool_names(&client).await.len(), 5);

    // Quick phrases: add, list, replace, remove, with a failure in the middle of a batch.
    let outcome = ok(
        &client,
        "edit_quick_phrases",
        json!({ "edits": [
            { "op": "add", "code": "yx", "text": "someone@example.com" },
            { "op": "add", "code": "dz", "text": "合成地址" },
        ]}),
    )
    .await;
    assert_eq!(outcome, json!({ "applied": 2 }));
    let page = ok(&client, "list_quick_phrases", json!({ "code_prefix": "y" })).await;
    assert_eq!(
        page,
        json!({ "phrases": [{ "code": "yx", "text": "someone@example.com" }], "has_more": false })
    );
    // Too soon after the last write.
    assert!(refused(
        &client,
        "edit_quick_phrases",
        json!({ "edits": [{ "op": "remove", "code": "dz", "text": "合成地址" }] })
    )
    .await
    .contains("one a second"));

    after_write_interval().await;
    let outcome = ok(
        &client,
        "edit_quick_phrases",
        json!({ "edits": [
            { "op": "replace", "previous": { "code": "yx", "text": "someone@example.com" }, "replacement": { "code": "yx", "text": "other@example.com" } },
            { "op": "remove", "code": "zz", "text": "不存在" },
            { "op": "remove", "code": "dz", "text": "合成地址" },
        ]}),
    )
    .await;
    assert_eq!(outcome["applied"], 1);
    assert_eq!(outcome["failed_index"], 1);
    assert!(outcome["error"].as_str().unwrap().contains("not found"));
    let page = ok(&client, "list_quick_phrases", json!({})).await;
    assert_eq!(page["phrases"].as_array().unwrap().len(), 2);
    assert!(page["phrases"]
        .as_array()
        .unwrap()
        .contains(&json!({ "code": "yx", "text": "other@example.com" })));

    // Preferences: read, change with the revision, refuse a stale one.
    let before = ok(&client, "get_preferences", json!({})).await;
    let revision = before["revision"].as_u64().unwrap();
    after_write_interval().await;
    let after = ok(
        &client,
        "update_preferences",
        json!({ "expected_revision": revision, "candidate_page_size": 7, "scheme": "wubi" }),
    )
    .await;
    assert_eq!(after["candidate_page_size"], 7);
    assert_eq!(after["scheme"], "wubi");
    assert_eq!(after["revision"], revision + 1);
    assert_eq!(ok(&client, "get_preferences", json!({})).await, after);
    after_write_interval().await;
    assert!(refused(
        &client,
        "update_preferences",
        json!({ "expected_revision": revision, "candidate_page_size": 5 })
    )
    .await
    .contains("changed since"));
    // Only the allowlist can be named; the SDK reports anything else as a failed call the agent can read and correct.
    assert!(refused(
        &client,
        "update_preferences",
        json!({ "expected_revision": revision + 1, "learning": false })
    )
    .await
    .contains("unknown field `learning`"));
    assert_eq!(ok(&client, "get_preferences", json!({})).await, after);
    assert_eq!(ok(&client, "get_preferences", json!({})).await, after);

    // Statistics: nothing recorded yet, and off until the user turns them on.
    let statistics = ok(&client, "get_typing_statistics", json!({ "days": 3 })).await;
    assert_eq!(statistics["enabled"], false);
    assert_eq!(statistics["days"], json!([]));
    assert!(
        !refused(&client, "get_typing_statistics", json!({ "days": 0 }))
            .await
            .is_empty()
    );

    client.cancel().await.unwrap();
}
