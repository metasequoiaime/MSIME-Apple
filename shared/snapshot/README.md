# Apple snapshot validation

Source: MSIME-Apple develop, fixed commit 6250e7437d547fa27246695f38e45e890ae26f4b, shared/backend/clients/BackendSnapshotClient.swift and Tests/BackendSnapshotTests.swift.

This package owns the platform-neutral half of the dictionary snapshot contract: bounded NDJSON framing, checksum, field and cross-record validation, private prepared copies, a verified-EOF staging stream, and the restore upload client. An ambiguous replacement is never retried automatically. The account/network extension is excluded; its failure type is replaced with a local error.

Run locally: `swift test --package-path shared/snapshot`. No network requests, credentials, or Engine mutations are performed by the tests.

Snapshot preparation and activation inside the macOS input method go through `shared/apple-bridge/DictionarySnapshotBridge` and the host-api snapshot interface, not through this package; see `platforms/macos/LOCAL_SNAPSHOT_INTEGRATION.md` for that side of the contract.
