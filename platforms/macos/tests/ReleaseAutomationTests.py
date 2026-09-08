import base64
import hashlib
import json
import os
import textwrap
import subprocess
import tempfile
import unittest
from pathlib import Path


MACOS_ROOT = Path(__file__).resolve().parents[1]
BASE_SHA = "1" * 40
HEAD_SHA = "2" * 40
SIGNING_SECRETS = (
    "MACOS_DEVELOPER_ID_CERTIFICATE_BASE64",
    "MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD",
    "MACOS_SIGNING_KEYCHAIN_PASSWORD",
    "MACOS_NOTARY_APPLE_ID",
    "MACOS_NOTARY_TEAM_ID",
    "MACOS_NOTARY_APP_SPECIFIC_PASSWORD",
    "MACOS_DEVELOPER_ID_APPLICATION",
    "MACOS_DEVELOPER_ID_INSTALLER",
)


class BuildNumberTests(unittest.TestCase):
    def run_step(self, step, prefix="", **values):
        workflow = (MACOS_ROOT.parents[1] / ".github/workflows/release.yml").read_text()
        body = workflow.split("      - name: " + step + "\n", 1)[1]
        body = body.split("\n      - name:", 1)[0].split("        run: |\n", 1)[1]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            environment = dict(os.environ, GITHUB_OUTPUT=str(output),
                               GITHUB_RUN_NUMBER="123", GITHUB_RUN_ATTEMPT="1",
                               REQUESTED_TAG="")
            environment.update(values)
            result = subprocess.run(["bash", "-e", "-c", prefix + "\n" + textwrap.dedent(body)],
                                    env=environment, text=True, capture_output=True)
            return result, output.read_text() if output.exists() else ""

    def test_build_increases_across_runs_rollover_and_retries(self):
        builds = []
        for run, attempt in [(99, 1), (99, 2), (100, 1), (101, 1)]:
            result, output = self.run_step("Allocate build number",
                                         GITHUB_RUN_NUMBER=str(run),
                                         GITHUB_RUN_ATTEMPT=str(attempt))
            self.assertEqual(result.returncode, 0, result.stderr)
            builds.append(tuple(map(int, output.strip().split("=")[1].split("."))))
        self.assertEqual(builds, sorted(set(builds)))
        self.assertGreater(builds[0], (491, 0, 0))

    def test_manual_build_draft_preserves_its_build(self):
        result, output = self.run_step("Allocate build number",
                                     REQUESTED_TAG="v0.48.6-build.2.23.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "value=2.23.1\n")

    def test_push_creates_unique_draft_at_exact_source_commit(self):
        result, output = self.run_step(
            "Create automatic build draft",
            prefix='cat() { printf "0.48.6\\n"; }; gh() { printf "%s\\n" "$*"; }',
            BUILD_NUMBER="2.23.1", GITHUB_SHA=HEAD_SHA)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("release create v0.48.6-build.2.23.1 --target " + HEAD_SHA, result.stdout)
        self.assertIn("--draft --prerelease", result.stdout)
        self.assertEqual(output, "release_created=true\ntag_name=v0.48.6-build.2.23.1\ntarget_sha=" + HEAD_SHA + "\n")

    def test_manual_version_bump_and_draft_selection_are_exclusive(self):
        for bump, tag, valid in [("true", "", True), ("false", "v0.48.6", True),
                                 ("true", "v0.48.6", False), ("false", "", False)]:
            result, _ = self.run_step("Validate invocation", GITHUB_REF="refs/heads/main",
                                     GITHUB_EVENT_NAME="workflow_dispatch",
                                     BUMP_VERSION=bump, REQUESTED_TAG=tag)
            self.assertEqual(result.returncode == 0, valid)
        result, _ = self.run_step("Validate invocation", GITHUB_REF="refs/heads/develop",
                                 GITHUB_EVENT_NAME="push")
        self.assertNotEqual(result.returncode, 0)

    def test_ios_uses_ci_build_and_rejects_tag_mismatch(self):
        root = MACOS_ROOT.parents[1]
        for name in ("package_ios_archive.sh", "package_ios_testflight.sh"):
            script = (root / "platforms/ios/scripts" / name).read_text()
            fragment = script.split("# CI supplies the shared build.", 1)[1]
            fragment = "# CI supplies the shared build." + fragment.split("marketing_version=", 1)[0]
            for tag, supplied, expected in [
                ("v0.48.6-build.1001.23.1", "1001.23.1", "1001.23.1"),
                ("v0.48.6", "1001.24.1", "1001.24.1"),
                ("v0.48.6-build.1001.23.1", "1001.24.1", None),
            ]:
                result = subprocess.run(
                    ["bash", "-eu", "-c", fragment + '\nprintf "%s" "$build_number"'],
                    env=dict(os.environ, tag_name=tag, METASEQUOIA_BUILD_NUMBER=supplied),
                    text=True, capture_output=True)
                if expected is None:
                    self.assertNotEqual(result.returncode, 0, name)
                    self.assertIn("does not match", result.stderr)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, expected, name)

    def test_invalid_build_is_rejected(self):
        for tag in ["v0.48.6-build.1.100.1", "v0.48.6-build.x", "v0.48.6-build.0.1.1"]:
            result, output = self.run_step("Allocate build number", REQUESTED_TAG=tag)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output, "")


class ReleaseAutomationTests(unittest.TestCase):
    ALL_GREEN = '[{"conclusion":"SUCCESS"},{"conclusion":"SUCCESS"},{"conclusion":"SUCCESS"}]'

    def run_merge(self, current_base=BASE_SHA, ci_exit_code="0", check_rollup=None):
        check_rollup = self.ALL_GREEN if check_rollup is None else check_rollup
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            log = temporary / "gh.log"
            output = temporary / "github-output"
            fake_gh = temporary / "gh"
            fake_gh.write_text(
                """#!/bin/zsh
set -euo pipefail
print -r -- "$*" >> "$FAKE_GH_LOG"
if [[ "$*" == *statusCheckRollup* ]]; then
    print -r -- "$FAKE_CHECK_ROLLUP"
elif [[ "$1 $2" == "pr view" ]]; then
    print -r -- "{\\"number\\":42,\\"state\\":\\"OPEN\\",\\"isDraft\\":false,\\"headRefName\\":\\"release-please--branches--main--components--MetasequoiaImeApple\\",\\"headRefOid\\":\\"$FAKE_HEAD_SHA\\",\\"baseRefName\\":\\"main\\",\\"baseRefOid\\":\\"$FAKE_BASE_SHA\\",\\"title\\":\\"chore(main): release 1.2.3\\"}"
elif [[ "$1 $2" == "workflow run" ]]; then
    exit 0
elif [[ "$1 $2" == "run list" ]]; then
    print -r -- "9001"
elif [[ "$1 $2" == "run watch" ]]; then
    exit "$FAKE_CI_EXIT_CODE"
elif [[ "$1" == "api" ]]; then
    print -r -- "$FAKE_CURRENT_BASE"
elif [[ "$1 $2" == "pr merge" ]]; then
    exit 0
else
    print -u2 -- "Unexpected gh invocation: $*"
    exit 64
fi
"""
            )
            fake_gh.chmod(0o755)
            release_pr = {
                "headBranchName": "release-please--branches--main--components--MetasequoiaImeApple",
                "number": 42,
            }
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{temporary}:{environment['PATH']}",
                    "GH_REPO": "metasequoiaime/MSIME-Apple",
                    "RELEASE_PR": json.dumps(release_pr),
                    "GITHUB_OUTPUT": str(output),
                    "FAKE_GH_LOG": str(log),
                    "FAKE_BASE_SHA": BASE_SHA,
                    "FAKE_CURRENT_BASE": current_base,
                    "FAKE_CI_EXIT_CODE": ci_exit_code,
                    "FAKE_CHECK_ROLLUP": check_rollup,
                    "FAKE_HEAD_SHA": HEAD_SHA,
                    "METASEQUOIA_RELEASE_CI_MAX_POLLS": "1",
                    "METASEQUOIA_RELEASE_CI_POLL_INTERVAL": "0",
                }
            )
            result = subprocess.run(
                [MACOS_ROOT / "scripts/merge-release-pr.sh"],
                capture_output=True,
                text=True,
                env=environment,
            )
            return result, log.read_text() if log.exists() else "", output.read_text() if output.exists() else ""

    def test_release_pull_request_merges_only_after_its_ci_run_passes(self):
        result, calls, output = self.run_merge()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("workflow run ci.yml", calls)
        self.assertLess(calls.index("workflow run ci.yml"), calls.index("run watch 9001"))
        self.assertLess(calls.index("run watch 9001"), calls.index("pr merge 42"))
        self.assertIn(f"--match-head-commit {HEAD_SHA}", calls)
        self.assertEqual(output, "merged=true\n")

    def test_release_pull_request_stays_open_when_main_advances_during_ci(self):
        result, calls, output = self.run_merge(current_base="3" * 40)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("run watch 9001", calls)
        self.assertNotIn("pr merge 42", calls)
        self.assertEqual(output, "merged=false\n")

    def test_release_pull_request_is_not_merged_when_its_own_checks_fail(self):
        # main requires the pull_request checks, which are separate runs from the dispatched one this
        # script watches. Merging on the dispatched run alone would be refused by branch protection.
        result, calls, output = self.run_merge(
            check_rollup='[{"conclusion":"SUCCESS"},{"conclusion":"FAILURE"}]'
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("run watch 9001", calls)
        self.assertNotIn("pr merge 42", calls)
        self.assertIn("failing check", result.stderr)

    def test_release_pull_request_stays_open_when_ci_fails(self):
        result, calls, output = self.run_merge(ci_exit_code="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("run watch 9001", calls)
        self.assertNotIn("pr merge 42", calls)
        self.assertEqual(output, "")


class ReleaseBranchPromotionTests(unittest.TestCase):
    def run_promotion(
        self,
        current_base=BASE_SHA,
        current_base_after_ci=None,
        current_head_after_ci=HEAD_SHA,
        changed_files=None,
        ci_exit_code="0",
        previous_release_sha="0" * 40,
        commit_message="chore(main): release 1.2.3",
        parent_shas=None,
        compare_status="ahead",
        head_cmake=None,
    ):
        changed_files = changed_files or [
            ".release-please-manifest.json",
            "CHANGELOG.md",
            "CMakeLists.txt",
            "version.txt",
        ]
        parent_shas = parent_shas or [BASE_SHA]
        base_contents = {
            "version.txt": "1.2.2\n",
            ".release-please-manifest.json": '{\n  ".": "1.2.2"\n}\n',
            "CMakeLists.txt": "cmake_minimum_required(VERSION 3.25)\nproject(MetasequoiaImeApple VERSION 1.2.2 LANGUAGES CXX)\n",
            "CHANGELOG.md": "# Changelog\n\n## [1.2.2](https://example.invalid/1.2.2)\n\n* previous\n",
        }
        head_contents = {
            "version.txt": "1.2.3\n",
            ".release-please-manifest.json": '{\n  ".": "1.2.3"\n}\n',
            "CMakeLists.txt": head_cmake
            or "cmake_minimum_required(VERSION 3.25)\nproject(MetasequoiaImeApple VERSION 1.2.3 LANGUAGES CXX)\n",
            "CHANGELOG.md": "# Changelog\n\n## [1.2.3](https://example.invalid/1.2.3)\n\n* current\n\n"
            "## [1.2.2](https://example.invalid/1.2.2)\n\n* previous\n",
        }
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            log = temporary / "gh.log"
            output = temporary / "github-output"
            fake_gh = temporary / "gh"
            fake_gh.write_text(
                """#!/bin/zsh
set -euo pipefail
print -r -- "$*" >> "$FAKE_GH_LOG"
case "$*" in
  "api repos/$GH_REPO/git/ref/heads/main --jq .object.sha")
    count=$(cat "$FAKE_MAIN_REF_COUNT" 2>/dev/null || print -r -- 0)
    if ((count == 0)); then print -r -- "$FAKE_CURRENT_BASE"; else print -r -- "$FAKE_CURRENT_BASE_AFTER_CI"; fi
    print -r -- $((count + 1)) > "$FAKE_MAIN_REF_COUNT"
    ;;
  "api repos/$GH_REPO/git/ref/heads/$RELEASE_BRANCH --jq .object.sha")
    count=$(cat "$FAKE_RELEASE_REF_COUNT" 2>/dev/null || print -r -- 0)
    if ((count == 0)); then print -r -- "$FAKE_HEAD_SHA"; else print -r -- "$FAKE_HEAD_AFTER_CI"; fi
    print -r -- $((count + 1)) > "$FAKE_RELEASE_REF_COUNT"
    ;;
  "api repos/$GH_REPO/git/commits/$FAKE_HEAD_SHA")
    print -r -- "$FAKE_COMMIT_JSON"
    ;;
  "api repos/$GH_REPO/compare/$FAKE_BASE_SHA...$FAKE_HEAD_SHA")
    print -r -- "$FAKE_COMPARE_JSON"
    ;;
  "api repos/$GH_REPO/contents/version.txt?ref=$FAKE_BASE_SHA --jq .content")
    print -r -- "$FAKE_BASE_VERSION_TXT"
    ;;
  "api repos/$GH_REPO/contents/version.txt?ref=$FAKE_HEAD_SHA --jq .content")
    print -r -- "$FAKE_HEAD_VERSION_TXT"
    ;;
  "api repos/$GH_REPO/contents/.release-please-manifest.json?ref=$FAKE_BASE_SHA --jq .content")
    print -r -- "$FAKE_BASE_RELEASE_PLEASE_MANIFEST_JSON"
    ;;
  "api repos/$GH_REPO/contents/.release-please-manifest.json?ref=$FAKE_HEAD_SHA --jq .content")
    print -r -- "$FAKE_HEAD_RELEASE_PLEASE_MANIFEST_JSON"
    ;;
  "api repos/$GH_REPO/contents/CMakeLists.txt?ref=$FAKE_BASE_SHA --jq .content")
    print -r -- "$FAKE_BASE_CMAKELISTS_TXT"
    ;;
  "api repos/$GH_REPO/contents/CMakeLists.txt?ref=$FAKE_HEAD_SHA --jq .content")
    print -r -- "$FAKE_HEAD_CMAKELISTS_TXT"
    ;;
  "api repos/$GH_REPO/contents/CHANGELOG.md?ref=$FAKE_BASE_SHA --jq .content")
    print -r -- "$FAKE_BASE_CHANGELOG_MD"
    ;;
  "api repos/$GH_REPO/contents/CHANGELOG.md?ref=$FAKE_HEAD_SHA --jq .content")
    print -r -- "$FAKE_HEAD_CHANGELOG_MD"
    ;;
  "workflow run ci.yml --repo $GH_REPO --ref $RELEASE_BRANCH --field mac_only=true")
    ;;
  "run list --repo $GH_REPO --workflow ci.yml --branch $RELEASE_BRANCH --event workflow_dispatch --limit 20 --json databaseId,headSha --jq "*)
    print -r -- "9001"
    ;;
  "run watch 9001 --repo $GH_REPO --exit-status --interval 10")
    exit "$FAKE_CI_EXIT_CODE"
    ;;
  "api --method PATCH repos/$GH_REPO/git/refs/heads/main -f sha=$FAKE_HEAD_SHA -F force=false")
    print -r -- "{}"
    ;;
  *)
    print -u2 -- "Unexpected gh invocation: $*"
    exit 64
    ;;
esac
"""
            )
            fake_gh.chmod(0o755)
            compare_json = {"status": compare_status, "ahead_by": 1, "behind_by": 0,
                            "files": [{"filename": filename} for filename in changed_files]}
            encoded = {
                f"FAKE_{side.upper()}_{name.strip('.').upper().replace('.', '_').replace('-', '_')}":
                base64.b64encode(contents[name].encode()).decode()
                for side, contents in (("base", base_contents), ("head", head_contents))
                for name in contents
            }
            environment = os.environ.copy()
            current_base_after_ci = current_base_after_ci or current_base
            environment.update(
                {
                    "PATH": f"{temporary}:{environment['PATH']}",
                    "GH_REPO": "metasequoiaime/MSIME-Apple",
                    "GITHUB_SHA": BASE_SHA,
                    "GITHUB_OUTPUT": str(output),
                    "RELEASE_BRANCH": "release-please--branches--main--components--MetasequoiaImeApple",
                    "EXPECTED_PREVIOUS_RELEASE_SHA": previous_release_sha,
                    "FAKE_GH_LOG": str(log),
                    "FAKE_BASE_SHA": BASE_SHA,
                    "FAKE_CURRENT_BASE": current_base,
                    "FAKE_CURRENT_BASE_AFTER_CI": current_base_after_ci,
                    "FAKE_HEAD_SHA": HEAD_SHA,
                    "FAKE_HEAD_AFTER_CI": current_head_after_ci,
                    "FAKE_MAIN_REF_COUNT": str(temporary / "main-ref-count"),
                    "FAKE_RELEASE_REF_COUNT": str(temporary / "release-ref-count"),
                    "FAKE_CI_EXIT_CODE": ci_exit_code,
                    "FAKE_COMPARE_JSON": json.dumps(compare_json),
                    "FAKE_COMMIT_JSON": json.dumps(
                        {
                            "message": commit_message,
                            "author": {
                                "name": "github-actions[bot]",
                                "email": "41898282+github-actions[bot]@users.noreply.github.com",
                            },
                            "committer": {"name": "GitHub", "email": "noreply@github.com"},
                            "parents": [{"sha": sha} for sha in parent_shas],
                        }
                    ),
                    **encoded,
                }
            )
            result = subprocess.run(
                [MACOS_ROOT / "scripts/promote-release-branch.sh"],
                capture_output=True,
                text=True,
                env=environment,
            )
            return result, log.read_text() if log.exists() else "", output.read_text() if output.exists() else ""

    def test_valid_release_commit_fast_forwards_main(self):
        result, calls, output = self.run_promotion()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("workflow run ci.yml", calls)
        self.assertLess(calls.index("run watch 9001"), calls.index("git/refs/heads/main -f sha="))
        self.assertIn(f"git/refs/heads/main -f sha={HEAD_SHA} -F force=false", calls)
        self.assertEqual(output, f"promoted=true\ntarget_sha={HEAD_SHA}\ntag_name=v1.2.3\n")

    def test_unexpected_release_file_is_rejected(self):
        result, calls, output = self.run_promotion(changed_files=["version.txt", "src/backdoor.mm"])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected file", result.stderr.lower())
        self.assertNotIn("git/refs/heads/main -f sha=", calls)
        self.assertEqual(output, "")

    def test_release_branch_must_advance_during_current_action(self):
        result, calls, output = self.run_promotion(previous_release_sha=HEAD_SHA)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not create a new commit", result.stderr.lower())
        self.assertNotIn("workflow run ci.yml", calls)
        self.assertEqual(output, "")

    def test_cmake_may_only_change_the_project_version(self):
        result, calls, output = self.run_promotion(
            head_cmake="project(MetasequoiaImeApple VERSION 1.2.3 LANGUAGES CXX)\nexecute_process(COMMAND curl bad.invalid)\n"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cmake", result.stderr.lower())
        self.assertNotIn("workflow run ci.yml", calls)
        self.assertEqual(output, "")

    def test_non_release_commit_message_is_rejected(self):
        result, calls, output = self.run_promotion(commit_message="feat: unrelated")

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("workflow run ci.yml", calls)
        self.assertEqual(output, "")

    def test_merge_commit_is_rejected(self):
        result, calls, output = self.run_promotion(parent_shas=[BASE_SHA, "4" * 40])

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("workflow run ci.yml", calls)
        self.assertEqual(output, "")

    def test_diverged_release_branch_is_rejected(self):
        result, calls, output = self.run_promotion(compare_status="diverged")

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("workflow run ci.yml", calls)
        self.assertEqual(output, "")

    def test_failed_ci_prevents_promotion(self):
        result, calls, output = self.run_promotion(ci_exit_code="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("run watch 9001", calls)
        self.assertNotIn("git/refs/heads/main -f sha=", calls)
        self.assertEqual(output, "")

    def test_main_advancing_during_ci_prevents_promotion(self):
        result, calls, output = self.run_promotion(current_base_after_ci="3" * 40)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("advanced while ci was running", result.stderr.lower())
        self.assertNotIn("git/refs/heads/main -f sha=", calls)
        self.assertEqual(output, "")

    def test_stale_workflow_cannot_advance_main(self):
        result, calls, output = self.run_promotion(current_base="3" * 40)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main advanced", result.stderr.lower())
        self.assertNotIn("git/refs/heads/main -f sha=", calls)
        self.assertEqual(output, "")


class ReleaseSigningModeTests(unittest.TestCase):
    def run_detection(self, configured_secrets=()):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            output = temporary / "github-output"
            summary = temporary / "github-summary"
            environment = os.environ.copy()
            for secret in SIGNING_SECRETS:
                environment.pop(secret, None)
            environment.update({secret: "configured" for secret in configured_secrets})
            environment["GITHUB_OUTPUT"] = str(output)
            environment["GITHUB_STEP_SUMMARY"] = str(summary)
            result = subprocess.run(
                [MACOS_ROOT / "scripts/detect-release-signing.sh"],
                capture_output=True,
                text=True,
                env=environment,
            )
            return (
                result,
                output.read_text() if output.exists() else "",
                summary.read_text() if summary.exists() else "",
            )

    def test_missing_credentials_selects_clearly_labeled_unsigned_release(self):
        result, output, summary = self.run_detection()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "signing_enabled=false\nasset_suffix=-unsigned\n")
        self.assertIn("unsigned", summary.lower())

    def test_complete_credentials_selects_signed_and_notarized_release(self):
        result, output, summary = self.run_detection(SIGNING_SECRETS)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "signing_enabled=true\nasset_suffix=\n")
        self.assertIn("signed and notarized", summary.lower())

    def test_partial_credentials_fail_instead_of_publishing_ambiguous_artifacts(self):
        result, output, summary = self.run_detection(SIGNING_SECRETS[:2])

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "")
        self.assertEqual(summary, "")
        self.assertIn("partially configured", result.stderr)
        self.assertIn("MACOS_DEVELOPER_ID_APPLICATION", result.stderr)


class ReleasePublicationTests(unittest.TestCase):
    def run_publication(
        self,
        signing_enabled,
        asset_suffix,
        existing_notes="",
        corrupt_checksum=False,
        misdirected_checksum=False,
        release_trigger="workflow_dispatch",
        ios_testflight=False,
        existing_assets="",
    ):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            log = temporary / "gh.log"
            captured_notes = temporary / "notes.md"
            fake_gh = fake_bin / "gh"
            fake_gh.write_text(
                """#!/bin/bash
set -euo pipefail
printf '%s\\n' "$*" >> "$FAKE_GH_LOG"
if [[ "$1 $2" == "release view" ]]; then
    if [[ "$*" == *"--json assets"* ]]; then
        printf '%s' "$FAKE_EXISTING_ASSETS"
    else
        printf '%s' "$FAKE_EXISTING_NOTES"
    fi
elif [[ "$1 $2" == "release edit" && "$*" == *"--notes-file"* ]]; then
    while (($#)); do
        if [[ "$1" == "--notes-file" ]]; then
            cp "$2" "$FAKE_CAPTURED_NOTES"
            exit 0
        fi
        shift
    done
fi
"""
            )
            fake_gh.chmod(0o755)
            dist = temporary / "dist"
            dist.mkdir()
            stem = f"MetasequoiaIME-v1.2.3-macos-universal{asset_suffix}"
            for extension in (".zip", ".pkg"):
                artifact = dist / f"{stem}{extension}"
                artifact.write_bytes(f"test {extension} artifact\n".encode())
                digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
                if corrupt_checksum and extension == ".pkg":
                    digest = "0" * 64
                (dist / f"{stem}{extension}.sha256").write_text(f"{digest}  {artifact.name}\n")
            update_archive = dist / f"{stem}-update.zip"
            update_archive.write_bytes(b"test Sparkle update artifact\n")
            update_digest = hashlib.sha256(update_archive.read_bytes()).hexdigest()
            (dist / f"{stem}-update.zip.sha256").write_text(
                f"{update_digest}  {update_archive.name}\n"
            )
            (dist / "appcast.xml").write_text(
                "<?xml version=\"1.0\"?><rss><channel><item>test</item></channel></rss>\n"
            )
            ios_suffix = "testflight" if ios_testflight else "unsigned"
            for ios_name in (
                f"MetasequoiaIME-v1.2.3-ios-{ios_suffix}.xcarchive.zip",
                f"MetasequoiaIME-v1.2.3-ios-{ios_suffix}.ipa",
            ):
                ios_artifact = dist / ios_name
                ios_artifact.write_bytes(f"test {ios_name} artifact\n".encode())
                ios_digest = hashlib.sha256(ios_artifact.read_bytes()).hexdigest()
                (dist / f"{ios_name}.sha256").write_text(f"{ios_digest}  {ios_name}\n")
            if misdirected_checksum:
                archive = dist / f"{stem}.zip"
                archive_digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                (dist / f"{stem}.pkg.sha256").write_text(f"{archive_digest}  {archive.name}\n")
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{fake_bin}:{environment['PATH']}",
                    "GH_REPO": "metasequoiaime/MSIME-Apple",
                    "TAG_NAME": "v1.2.3",
                    "ASSET_SUFFIX": asset_suffix,
                    "SIGNING_ENABLED": signing_enabled,
                    "RELEASE_TRIGGER": release_trigger,
                    "DIST_DIR": str(dist),
                    "RUNNER_TEMP": str(temporary),
                    "FAKE_GH_LOG": str(log),
                    "FAKE_EXISTING_NOTES": existing_notes,
                    "FAKE_EXISTING_ASSETS": existing_assets,
                    "FAKE_CAPTURED_NOTES": str(captured_notes),
                    "IOS_TESTFLIGHT_ENABLED": "true" if ios_testflight else "false",
                }
            )
            result = subprocess.run(
                [MACOS_ROOT / "scripts/publish-release.sh"],
                capture_output=True,
                text=True,
                env=environment,
            )
            return (
                result,
                log.read_text() if log.exists() else "",
                captured_notes.read_text() if captured_notes.exists() else "",
            )

    def test_unsigned_publication_records_mode_before_uploading_labeled_assets(self):
        result, calls, notes = self.run_publication("false", "-unsigned", "Existing notes")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("metasequoia-release-mode:unsigned", notes)
        self.assertIn("not Developer ID signed or notarized", notes)
        self.assertIn("Recommended: ZIP", notes)
        self.assertIn("Install.command", notes)
        self.assertIn("does not automatically log out or restart", notes)
        self.assertIn("PKG option", notes)
        self.assertIn("attempts to register and enable 水杉", notes)
        self.assertIn("System Settings", notes)
        self.assertLess(calls.index("--notes-file"), calls.index("release upload"))
        self.assertIn("macos-universal-unsigned.pkg", calls)
        self.assertIn("macos-universal-unsigned-update.zip", calls)
        self.assertIn("ios-unsigned.xcarchive.zip", calls)
        self.assertIn("ios-unsigned.ipa", calls)
        # The .ipa is the asset a tester can use, so the notes have to lead with it and say plainly
        # that it still needs signing.
        self.assertIn("Both iOS assets are **unsigned**", notes)
        self.assertIn("Sideloadly", notes)
        # The appcast is signed with the Ed25519 update key, not with an Apple identity, so an Apple-unsigned release still publishes it and Sparkle keeps working.
        self.assertIn("appcast.xml", calls)
        self.assertIn("--draft=false", calls)

    def test_same_mode_retry_keeps_notes_and_reuploads_with_clobber(self):
        marker = (
            "Existing notes\n\n"
            "<!-- metasequoia-release-mode:unsigned -->\n"
            "<!-- metasequoia-install-guidance:v4 -->\n"
        )
        result, calls, notes = self.run_publication("false", "-unsigned", marker)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("--notes-file", calls)
        self.assertIn("--clobber", calls)
        self.assertEqual(notes, "")

    def test_retry_adds_install_guidance_to_release_with_only_mode_marker(self):
        marker = "Existing notes\n\n<!-- metasequoia-release-mode:unsigned -->\n"
        result, calls, notes = self.run_publication("false", "-unsigned", marker)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Existing notes", notes)
        self.assertEqual(notes.count("metasequoia-release-mode:unsigned"), 1)
        self.assertIn("metasequoia-install-guidance:v4", notes)
        self.assertIn("Recommended: ZIP", notes)
        self.assertLess(calls.index("--notes-file"), calls.index("release upload"))

    def test_cross_mode_retry_is_rejected_before_assets_change(self):
        marker = "<!-- metasequoia-release-mode:unsigned -->"
        result, calls, notes = self.run_publication("true", "", marker)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already locked to unsigned", result.stderr)
        self.assertNotIn("release upload", calls)
        self.assertNotIn("release edit", calls)
        self.assertEqual(notes, "")

    def test_signed_publication_records_signed_mode_without_unsigned_warning(self):
        result, calls, notes = self.run_publication(
            "true",
            "",
            ios_testflight=True,
            existing_assets=(
                "MetasequoiaIME-v1.2.3-ios-unsigned.xcarchive.zip\n"
                "MetasequoiaIME-v1.2.3-ios-unsigned.xcarchive.zip.sha256\n"
                "MetasequoiaIME-v1.2.3-ios-unsigned.ipa\n"
                "MetasequoiaIME-v1.2.3-ios-unsigned.ipa.sha256\n"
            ),
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("metasequoia-release-mode:signed", notes)
        self.assertNotIn("WARNING", notes)
        self.assertIn("Recommended: ZIP", notes)
        self.assertIn("PKG option", notes)
        self.assertIn("attempts to register and enable 水杉", notes)
        self.assertIn("macos-universal.pkg", calls)
        self.assertIn("ios-testflight.xcarchive.zip", calls)
        self.assertIn("ios-testflight.ipa", calls)
        self.assertIn("release delete-asset", calls)
        self.assertIn("distribution-signed", notes)

    def test_corrupt_artifact_is_rejected_before_release_metadata_or_assets_change(self):
        result, calls, notes = self.run_publication("false", "-unsigned", corrupt_checksum=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("FAILED", result.stdout + result.stderr)
        self.assertEqual(calls, "")
        self.assertEqual(notes, "")

    def test_checksum_for_another_artifact_is_rejected_before_release_changes(self):
        result, calls, notes = self.run_publication("false", "-unsigned", misdirected_checksum=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, "")
        self.assertEqual(notes, "")

    def test_push_publishes_into_the_build_channel(self):
        result, calls, notes = self.run_publication(
            "true", "", existing_notes="Existing notes", release_trigger="push"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--prerelease", calls)
        self.assertNotIn("--latest", calls)
        self.assertIn("（自动构建）", calls)
        self.assertIn("metasequoia-build-channel:v1", notes)
        self.assertIn("未经人工挑选", notes)

    def test_dispatch_publishes_into_the_release_channel(self):
        result, calls, notes = self.run_publication(
            "true", "", existing_notes="Existing notes", release_trigger="workflow_dispatch"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--prerelease=false", calls)
        self.assertIn("--latest", calls)
        self.assertNotIn("（自动构建）", calls)
        self.assertNotIn("metasequoia-build-channel", notes)

    def test_build_channel_note_is_not_repeated_on_a_retry(self):
        _, _, notes = self.run_publication(
            "true",
            "",
            existing_notes="Existing notes <!-- metasequoia-build-channel:v1 --> 未经人工挑选",
            release_trigger="push",
        )

        self.assertLessEqual(notes.count("metasequoia-build-channel:v1"), 1)

    def test_publication_requires_knowing_which_channel_it_is_publishing_into(self):
        # Defaulting would silently pick a channel, and picking the release channel by accident
        # puts an uncurated build behind the Latest badge, which is what Sparkle follows.
        result, calls, notes = self.run_publication("true", "", release_trigger="")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("RELEASE_TRIGGER", result.stderr)
        self.assertEqual(calls, "")
        self.assertEqual(notes, "")


class SparkleAppcastTests(unittest.TestCase):
    def run_generator(self, private_key="test-private-key", archive_name=None, tag="v1.2.3", build=None):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            tools = temporary / "tools"
            tools.mkdir()
            log = temporary / "tools.log"
            archive_name = archive_name or f"MetasequoiaIME-{tag}-macos-universal-unsigned-update.zip"
            archive = temporary / archive_name
            archive.write_bytes(b"update archive")
            output = temporary / "appcast.xml"

            generate_appcast = tools / "generate_appcast"
            generate_appcast.write_text(
                """#!/bin/bash
set -euo pipefail
read -r secret
printf 'generate:%s:%s\\n' "$secret" "$*" >> "$FAKE_SPARKLE_LOG"
output=
while (($#)); do
    if [[ "$1" == "-o" ]]; then
        output=$2
        shift 2
        continue
    fi
    shift
done
cat > "$output" <<'XML'
<?xml version="1.0"?><rss><channel><item><enclosure url="https://github.com/metasequoiaime/MSIME-Apple/releases/download/v1.2.3/MetasequoiaIME-v1.2.3-macos-universal-unsigned-update.zip" sparkle:edSignature="test-signature" /></item></channel></rss>
XML
"""
            )
            generate_appcast.write_text(generate_appcast.read_text().replace("v1.2.3", tag))
            generate_appcast.chmod(0o755)
            sign_update = tools / "sign_update"
            sign_update.write_text(
                """#!/bin/bash
set -euo pipefail
read -r secret
printf 'sign:%s:%s\\n' "$secret" "$*" >> "$FAKE_SPARKLE_LOG"
if [[ "${!#}" == *.zip ]]; then
    printf '%s\\n' 'sparkle:edSignature="test-signature" length="14"'
fi
"""
            )
            sign_update.chmod(0o755)

            environment = os.environ.copy()
            environment.update(
                {
                    "SPARKLE_TOOLS_DIR": str(tools),
                    "SPARKLE_ED_PRIVATE_KEY": private_key,
                    "FAKE_SPARKLE_LOG": str(log),
                    "GH_REPO": "metasequoiaime/MSIME-Apple",
                }
            )
            if build:
                environment["METASEQUOIA_BUILD_NUMBER"] = build
            result = subprocess.run(
                [
                    MACOS_ROOT / "scripts/generate-sparkle-appcast.sh",
                    tag,
                    archive,
                    output,
                ],
                capture_output=True,
                text=True,
                env=environment,
            )
            return (
                result,
                output.read_text() if output.exists() else "",
                log.read_text() if log.exists() else "",
            )

    def test_generates_and_signs_appcast_for_exact_release_archive(self):
        result, appcast, calls = self.run_generator()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("releases/download/v1.2.3/", appcast)
        self.assertIn("test-signature", appcast)
        self.assertIn("generate:test-private-key:", calls)
        self.assertIn("sign:test-private-key:", calls)

    def test_build_tag_selects_internal_build_for_appcast(self):
        result, appcast, calls = self.run_generator(tag="v1.2.3-build.2.23.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--versions 2.23.1", calls)
        self.assertIn("releases/download/v1.2.3-build.2.23.1/", appcast)

    def test_formal_release_uses_independent_build(self):
        result, appcast, calls = self.run_generator(build="2.24.1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--versions 2.24.1", calls)

    def test_rejects_archive_that_does_not_match_release_tag(self):
        result, appcast, calls = self.run_generator(
            archive_name="MetasequoiaIME-v9.9.9-macos-universal-unsigned-update.zip"
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(appcast, "")
        self.assertEqual(calls, "")

    def test_rejects_missing_private_key(self):
        result, appcast, calls = self.run_generator(private_key="")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(appcast, "")
        self.assertEqual(calls, "")

    def run_promoted_release_creation(
        self, *, main_sha=HEAD_SHA, release_exists="false", release_draft="true", release_target=HEAD_SHA
    ):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            log = temporary / "gh.log"
            output = temporary / "github-output"
            fake_gh = temporary / "gh"
            fake_gh.write_text(
                """#!/bin/zsh
set -euo pipefail
print -r -- "$*" >> "$FAKE_GH_LOG"
case "$*" in
  "api repos/$GH_REPO/git/ref/heads/main --jq .object.sha")
    print -r -- "$FAKE_MAIN_SHA"
    ;;
  "api repos/$GH_REPO/contents/version.txt?ref=$TARGET_SHA --jq .content")
    print -r -- "MC4yOC4wCg=="
    ;;
  "release view $TAG_NAME --repo $GH_REPO --json isDraft,tagName,targetCommitish")
    if [[ "$FAKE_RELEASE_EXISTS" != true && ! -f "$FAKE_RELEASE_CREATED" ]]; then exit 1; fi
    print -r -- "{\\"isDraft\\":$FAKE_RELEASE_DRAFT,\\"tagName\\":\\"$TAG_NAME\\",\\"targetCommitish\\":\\"$FAKE_RELEASE_TARGET\\"}"
    ;;
  "release create $TAG_NAME --repo $GH_REPO --target $TARGET_SHA --title $TAG_NAME --generate-notes --draft")
    touch "$FAKE_RELEASE_CREATED"
    ;;
  *)
    print -u2 -- "Unexpected gh invocation: $*"
    exit 64
    ;;
esac
"""
            )
            fake_gh.chmod(0o755)
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{temporary}:{environment['PATH']}",
                    "GH_REPO": "metasequoiaime/MSIME-Apple",
                    "TARGET_SHA": HEAD_SHA,
                    "TAG_NAME": "v0.28.0",
                    "GITHUB_OUTPUT": str(output),
                    "FAKE_GH_LOG": str(log),
                    "FAKE_MAIN_SHA": main_sha,
                    "FAKE_RELEASE_EXISTS": release_exists,
                    "FAKE_RELEASE_DRAFT": release_draft,
                    "FAKE_RELEASE_TARGET": release_target,
                    "FAKE_RELEASE_CREATED": str(temporary / "release-created"),
                }
            )
            result = subprocess.run(
                [MACOS_ROOT / "scripts/create-promoted-release.sh"],
                capture_output=True,
                text=True,
                env=environment,
            )
            return result, log.read_text() if log.exists() else "", output.read_text() if output.exists() else ""

    def test_promoted_commit_creates_draft_release_at_exact_sha(self):
        result, calls, output = self.run_promoted_release_creation()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"release create v0.28.0 --repo metasequoiaime/MSIME-Apple --target {HEAD_SHA}", calls)
        self.assertEqual(calls.count("release view v0.28.0"), 2)
        self.assertEqual(output, "release_created=true\ntag_name=v0.28.0\n")

    def test_existing_draft_release_resumes_without_recreating_it(self):
        result, calls, output = self.run_promoted_release_creation(release_exists="true")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("release create", calls)
        self.assertEqual(output, "release_created=true\ntag_name=v0.28.0\n")

    def test_promoted_release_rejects_stale_main(self):
        result, calls, output = self.run_promoted_release_creation(main_sha=BASE_SHA)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("main advanced", result.stderr)
        self.assertNotIn("release create", calls)
        self.assertEqual(output, "")

    def test_existing_draft_release_must_target_promoted_sha(self):
        result, calls, output = self.run_promoted_release_creation(
            release_exists="true", release_target=BASE_SHA
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("targets", result.stderr)
        self.assertNotIn("release create", calls)
        self.assertEqual(output, "")


if __name__ == "__main__":
    unittest.main()
