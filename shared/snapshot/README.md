# Apple snapshot validation

Source: MSIME-Apple develop, fixed commit 6250e7437d547fa27246695f38e45e890ae26f4b,
shared/backend/BackendSnapshotClient.swift and Tests/BackendSnapshotTests.swift.

Preserves bounded NDJSON framing, checksum, field and cross-record validation,
private prepared copies and verified-EOF staging stream. Only the account/network
extension is excluded; its failure type is replaced with a local error.
Tests exclude the network restore test because transport is not migrated yet.

Run locally: `swift test --package-path shared/snapshot`.
No CI is added. No network requests, credentials, or Engine mutations are performed.
This package is a migration component; the macOS snapshot UI and host activation
are not yet wired to it. It does not prove end-to-end snapshot support.
