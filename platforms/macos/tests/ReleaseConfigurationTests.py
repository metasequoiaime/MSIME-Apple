import json
import os
import plistlib
import re
import subprocess
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
MACOS_ROOT = PROJECT_ROOT / "platforms" / "macos"


class ReleaseConfigurationTests(unittest.TestCase):
    def test_shuangpin_beginner_keymap_is_wired_to_the_input_controller(self):
        readme = (PROJECT_ROOT / "README.md").read_text()
        cmake = (PROJECT_ROOT / "CMakeLists.txt").read_text()
        preferences_controller = (MACOS_ROOT / "src/PreferencesWindowController.mm").read_text()
        input_controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()

        self.assertIn("显示小鹤双拼键位提示", preferences_controller)
        self.assertIn('accessibilityLabel = @"双拼键位提示行"', preferences_controller)
        self.assertIn("storedShuangpinKeymapEnabled", preferences_controller)
        self.assertIn('import "ShuangpinKeymapPanel.h"', input_controller)
        self.assertIn("_shuangpinKeymapPanel = [[MetasequoiaShuangpinKeymapPanel alloc] init]", input_controller)
        self.assertIn("storedShuangpinKeymapEnabled", input_controller)
        self.assertIn("attributesForCharacterIndex:0 lineHeightRectangle:&caretRect", input_controller)
        self.assertIn("showNearCaretRect:caretRect", input_controller)
        self.assertGreaterEqual(input_controller.count("[_shuangpinKeymapPanel orderOut:nil]"), 5)
        reload_session = input_controller.split("- (void)reloadSessionFromPreferences", 1)[1].split(
            "- (BOOL)prepareSessionIfNeeded", 1
        )[0]
        self.assertLess(
            reload_session.index("storedShuangpinKeymapEnabled"),
            reload_session.index("_session->has_composition()"),
        )
        self.assertIn("ShuangpinKeymapPanel.mm", cmake)
        self.assertIn("ShuangpinKeymapPanelTests.mm", cmake)
        self.assertIn("小鹤双拼键位提示", readme)

        keymap_panel = (MACOS_ROOT / "src/ShuangpinKeymapPanel.mm").read_text()
        self.assertIn("profile.zero_initials", keymap_panel)
        self.assertIn("MetasequoiaXiaoheZeroInitialText", keymap_panel)
        self.assertIn("零声母", readme)

    def test_ci_cancels_duplicate_runs_for_the_same_source_branch(self):
        workflow = (PROJECT_ROOT / ".github/workflows/ci.yml").read_text()

        self.assertIn(
            "group: ci-${{ github.workflow }}-${{ github.event_name }}-${{ github.event.pull_request.head.ref || github.ref_name }}",
            workflow,
        )
        self.assertIn("cancel-in-progress: true", workflow)
        # merge-release-pr.sh dispatches ci.yml and waits on that run with --exit-status, so a pull_request run on the same branch must land in a different concurrency group or it cancels the release.
        self.assertIn("${{ github.event_name }}", workflow.split("concurrency:", 1)[1].split("permissions:", 1)[0])
        self.assertIn("on:\n  push:\n    branches:\n      - main\n  pull_request:\n", workflow)

    def test_current_repository_links_use_the_canonical_apple_repository(self):
        canonical_repository = "https://github.com/metasequoiaime/MSIME-Apple"
        current_metadata = "\n".join(
            path.read_text()
            for path in (
                PROJECT_ROOT / "README.md",
                PROJECT_ROOT / "PRIVACY.md",
                PROJECT_ROOT / "THIRD_PARTY_NOTICES.txt",
                PROJECT_ROOT / "docs/apple-platform-architecture.md",
                MACOS_ROOT / "resources/Info.plist",
                MACOS_ROOT / "tests/ReleaseAutomationTests.py",
            )
        )

        self.assertNotIn("github.com/houko/MetasequoiaImeApple", current_metadata)
        self.assertNotIn("github.com/houko/MetasequoiaImeMac", current_metadata)
        self.assertIn(canonical_repository, current_metadata)
        with (MACOS_ROOT / "resources/Info.plist").open("rb") as info_file:
            info = plistlib.load(info_file)
        self.assertEqual(
            info["SUFeedURL"],
            f"{canonical_repository}/releases/latest/download/appcast.xml",
        )

    def test_input_source_uses_a_dedicated_menu_icon(self):
        with (MACOS_ROOT / "resources/Info.plist").open("rb") as info_file:
            info = plistlib.load(info_file)

        app_icon = "MetasequoiaIME.icns"
        menu_icon = "MetasequoiaIMEMenuIcon.tiff"
        input_mode = info["ComponentInputModeDict"]["tsInputModeListKey"][
            "com.houko.inputmethod.MetasequoiaIME.Hans"
        ]

        self.assertEqual(info["CFBundleIconFile"], app_icon)
        self.assertEqual(info["tsInputMethodIconFileKey"], menu_icon)
        self.assertEqual(input_mode["tsInputModeMenuIconFileKey"], menu_icon)
        self.assertEqual(input_mode["tsInputModePaletteIconFileKey"], menu_icon)
        self.assertTrue((MACOS_ROOT / "resources" / menu_icon).is_file())
        self.assertIn(menu_icon, (PROJECT_ROOT / "CMakeLists.txt").read_text())
        menu_icon_svg = (MACOS_ROOT / "resources" / "MetasequoiaIMEMenuIcon.svg").read_text()
        self.assertIn('<rect width="32" height="36" fill="#fff" />', menu_icon_svg)

        icon_path = MACOS_ROOT / "resources" / menu_icon
        dpi_output = subprocess.check_output(
            ["sips", "-g", "dpiWidth", "-g", "dpiHeight", str(icon_path)],
            text=True,
        )
        self.assertRegex(dpi_output, r"dpiWidth:\s*144(?:\.0+)?")
        self.assertRegex(dpi_output, r"dpiHeight:\s*144(?:\.0+)?")

        alpha_output = subprocess.check_output(
            ["sips", "-g", "hasAlpha", str(icon_path)],
            text=True,
        )
        self.assertRegex(alpha_output, r"hasAlpha:\s*no")

    def test_input_controller_survives_the_engine_helpcode_semantics(self):
        controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()

        # InputSession::helpcode_enabled() reports false for schemes without helpcodes, so an unguarded comparison never matches a Wubi session and rebuilds the engine on every keystroke.
        matches = controller.split("bool SessionMatchesPreferences(", 1)[1].split("\n}", 1)[0]
        self.assertIn("SchemeUsesHelpcodes(preferences.scheme)", matches)
        self.assertNotIn("session.helpcode_enabled() == preferences.helpcodeEnabled &&", matches)
        scheme_guard = controller.split("bool SchemeUsesHelpcodes(", 1)[1].split("\n}", 1)[0]
        self.assertIn("SchemeType::Quanpin", scheme_guard)
        self.assertIn("SchemeType::Shuangpin", scheme_guard)

        # The engine consumes A-Z during a composition as helpcode input. macOS does not offer that, so uppercase must not reach the session while something is being composed; it commits the leading candidate and the application inserts the capital. The one capital path that is allowed opens a local input mode, and the engine guards every one of those triggers on there being no composition, so this branch has to carry the same guard. The full-width and keymap-highlight paths elsewhere in this file legitimately look at uppercase, so scope the check to the key-routing branch.
        character_branch = controller.split("case metasequoia::mac::ControllerKeyAction::Character:", 1)[1].split(
            "if (!result.handled)", 1
        )[0]
        self.assertIn("if (character >= 'a' && character <= 'z')", character_branch)
        self.assertIn("HandleCharacterWithWubiAutoCommit", character_branch)

        uppercase_conditions = [
            line for line in character_branch.splitlines() if "character <= 'Z'" in line
        ]
        self.assertEqual(
            len(uppercase_conditions),
            1,
            "uppercase reaches the session from more than one place in the key-routing branch",
        )
        uppercase_branch = character_branch.split("character <= 'Z'", 1)[1].split("}", 1)[0]
        self.assertIn("!_session->has_composition()", uppercase_branch)
        self.assertIn("_localInputModesEnabled", character_branch)
        self.assertIn("NSEventModifierFlagShift", uppercase_branch)
        self.assertIn("handle_character(static_cast<char>(character), true)", uppercase_branch)

    def test_engine_english_learning_stays_unreachable_from_macos(self):
        controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()
        installer = (MACOS_ROOT / "src/DictionaryInstaller.mm").read_text()

        # The engine writes learned English words to data_file_path("english.db"), while this installer
        # replays the English journal into msime_english.db and only backs that name up when learned data
        # is reset. The two never meet today because macOS never turns the engine's English paths on, so
        # the divergence is latent. Wiring any of these up without first reconciling the filename would
        # orphan learned English words in a file no macOS code reads, migrates or clears.
        self.assertIn("msime_english.db", installer)
        for switch in (
            "set_dedicated_english_mode",
            "set_english_input_options",
            "set_frequency_adjustment",
            "set_mixed_expressive_options",
        ):
            self.assertNotIn(switch, controller, f"{switch} reaches the engine's english.db path; reconcile the filename with msime_english.db first")
        # handle_character's second parameter is what routes Shift+letter into the English and local modes.
        self.assertIn("_session->handle_character(static_cast<char>(character))", controller)

    def test_input_controller_owns_a_native_floating_status_toolbar(self):
        cmake = (PROJECT_ROOT / "CMakeLists.txt").read_text()
        controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()
        readme = (PROJECT_ROOT / "README.md").read_text()

        self.assertIn("FloatingToolbarPanel.mm", cmake)
        self.assertIn("FloatingToolbarPanelTests.mm", cmake)
        self.assertIn('#import "FloatingToolbarPanel.h"', controller)
        self.assertIn("[MetasequoiaFloatingToolbarPanel sharedPanel]", controller)
        self.assertIn("activateForDelegate:self", controller)
        self.assertIn("deactivateForDelegate:self", controller)
        refresh_method = controller.split("- (void)refreshFloatingToolbar", 1)[1].split("\n}", 1)[0]
        self.assertIn("toolbarDelegate != self", refresh_method)
        self.assertNotIn("activateForDelegate:self", refresh_method)
        self.assertIn("MetasequoiaFloatingToolbarDidChangeNotification", controller)
        self.assertIn("floatingToolbarDidRequestToggleInputMode:", controller)
        self.assertIn("floatingToolbarDidRequestTogglePunctuation:", controller)
        self.assertIn("floatingToolbarDidRequestToggleFullWidth:", controller)
        self.assertIn("floatingToolbarDidRequestToggleTraditionalOutput:", controller)
        punctuation_method = controller.split("floatingToolbarDidRequestTogglePunctuation:", 1)[1].split("\n}", 1)[0]
        self.assertLess(
            punctuation_method.index("commitLeadingCandidate:"),
            punctuation_method.index("setChinesePunctuationEnabled:"),
        )
        self.assertIn("悬浮状态栏", readme)

    def test_traditional_output_converts_visible_candidates_and_commits(self):
        cmake = (PROJECT_ROOT / "CMakeLists.txt").read_text()
        controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()
        readme = (PROJECT_ROOT / "README.md").read_text()
        app_target = cmake.split("add_executable(MetasequoiaIME MACOSX_BUNDLE", 1)[1].split("\n", 1)[0]

        self.assertIn("src/ChineseTextConversion.mm", app_target)
        self.assertIn('#import "ChineseTextConversion.h"', controller)
        self.assertIn("MetasequoiaTraditionalChineseOutputDidChangeNotification", controller)
        self.assertIn("traditionalChineseOutputEnabled:", controller)
        self.assertIn("selectSimplifiedOutput:", controller)
        self.assertIn("selectTraditionalOutput:", controller)

        self.assertEqual(controller.count("- (BOOL)traditionalChineseOutputActive\n"), 1)
        accessor = controller.split("- (BOOL)traditionalChineseOutputActive\n", 1)[1].split("\n}", 1)[0]
        self.assertIn("storedTraditionalChineseOutputEnabled", accessor)

        apply_result = controller.split("- (void)applyResult:", 1)[1].split("\n}", 1)[0]
        self.assertIn("[self traditionalChineseOutputActive]", apply_result)
        self.assertNotIn("storedTraditionalChineseOutputEnabled", apply_result)
        self.assertLess(
            apply_result.index("MetasequoiaChineseOutputString"),
            apply_result.index("insertText:"),
        )
        candidate_panel = controller.split("- (void)rebuildCandidatePanelPreservingSelection:", 1)[1].split(
            "\n}", 1
        )[0]
        self.assertIn("[self traditionalChineseOutputActive]", candidate_panel)
        self.assertNotIn("storedTraditionalChineseOutputEnabled", candidate_panel)
        self.assertLess(
            candidate_panel.index("MetasequoiaChineseOutputString"),
            candidate_panel.index("MetasequoiaIndexedCandidateString"),
        )

        self.assertIn("默认输出简体", readme)
        self.assertIn("切换为繁体字，不改变词库键值和学习数据", readme)
        self.assertIn("「简体输出」还是「繁体输出」", readme)

        preference_refresh = controller.split("- (void)floatingToolbarPreferenceDidChange:", 1)[1].split(
            "\n}", 1
        )[0]
        self.assertIn("refreshCandidatePanelPreservingSelection", preference_refresh)

        selected_callback = controller.split("- (void)candidateSelected:", 1)[1].split("\n}", 1)[0]
        self.assertIn("MetasequoiaCandidateIndex", selected_callback)
        self.assertIn("selectedCandidate", selected_callback)
        self.assertIn("candidateStringIdentifier", selected_callback)

    def test_floating_toolbar_uses_native_utility_actions(self):
        toolbar = (MACOS_ROOT / "src/FloatingToolbarPanel.mm").read_text()
        controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()
        readme = (PROJECT_ROOT / "README.md").read_text()

        self.assertIn("CreateMetasequoiaFloatingToolbarUtilityMenu", toolbar)
        self.assertIn("popUpMenuPositioningItem", toolbar)
        self.assertIn("floatingToolbarDidRequestCheckForUpdates:", controller)
        self.assertIn("floatingToolbarDidRequestOpenWebsite:", controller)
        hide_method = controller.split("- (void)floatingToolbarDidRequestHide:", 1)[1].split("\n}", 1)[0]
        self.assertIn("setFloatingToolbarEnabled:NO", hide_method)
        self.assertIn("https://msime.app/", controller)
        self.assertIn("隐藏悬浮状态栏", readme)

    def test_release_version_matches_cmake_project_version(self):
        manifest = json.loads((PROJECT_ROOT / ".release-please-manifest.json").read_text())
        cmake = (PROJECT_ROOT / "CMakeLists.txt").read_text()
        project_line = next(line for line in cmake.splitlines() if line.startswith("project(MetasequoiaImeApple "))
        match = re.search(r"VERSION ([0-9]+\.[0-9]+\.[0-9]+)", project_line)

        self.assertIsNotNone(match)
        self.assertEqual(manifest["."], match.group(1))
        self.assertEqual((PROJECT_ROOT / "version.txt").read_text().strip(), match.group(1))
        self.assertIn("x-release-please-version", project_line)

    def test_release_automation_bumps_tags_and_uploads_installable_assets(self):
        config = json.loads((PROJECT_ROOT / "release-please-config.json").read_text())
        package = config["packages"]["."]
        workflow = (PROJECT_ROOT / ".github/workflows/release.yml").read_text()
        merge_release_pr = (MACOS_ROOT / "scripts/merge-release-pr.sh").read_text()
        promote_release_branch = (MACOS_ROOT / "scripts/promote-release-branch.sh").read_text()
        create_promoted_release = (MACOS_ROOT / "scripts/create-promoted-release.sh").read_text()
        readme = (PROJECT_ROOT / "README.md").read_text()
        info_plist = (MACOS_ROOT / "resources/Info.plist").read_text()
        cmake = (PROJECT_ROOT / "CMakeLists.txt").read_text()

        self.assertEqual(package["release-type"], "simple")
        self.assertIn({"type": "generic", "path": "CMakeLists.txt"}, package["extra-files"])
        self.assertNotIn("generated", (package["pull-request-header"] + package["pull-request-footer"]).lower())
        self.assertTrue(package["draft"])
        self.assertTrue(package["force-tag-creation"])
        self.assertFalse(package.get("include-component-in-tag", True))
        ci_workflow = (PROJECT_ROOT / ".github/workflows/ci.yml").read_text()
        allowed_actions = {"actions/checkout", "googleapis/release-please-action"}
        used_actions = set()
        for workflow_source in (workflow, ci_workflow):
            uses_lines = [line.strip() for line in workflow_source.splitlines() if line.strip().startswith("uses:")]
            self.assertGreater(len(uses_lines), 0)
            for uses_line in uses_lines:
                action_reference = uses_line.removeprefix("uses:").strip().split()[0]
                action, separator, revision = action_reference.partition("@")
                self.assertEqual(separator, "@")
                self.assertIn(action, allowed_actions)
                self.assertRegex(revision, r"^[0-9a-f]{40}$")
                used_actions.add(action)
        self.assertEqual(used_actions, allowed_actions)
        self.assertIn("steps.release.outputs.release_created", workflow)
        self.assertIn("run: bash platforms/macos/scripts/merge-release-pr.sh", workflow)
        merge_release_pr_script = (MACOS_ROOT / "scripts/merge-release-pr.sh").read_text()
        # main requires the pull_request checks, which are a different set of runs from the one this
        # script dispatches and watches. Merging on the dispatched run alone is refused by the branch
        # protection whenever the pull_request runs are still queued.
        self.assertIn("gh pr view \"$pr_number\" --repo \"$GH_REPO\" --json statusCheckRollup", merge_release_pr_script)
        self.assertLess(
            merge_release_pr_script.index("statusCheckRollup"),
            merge_release_pr_script.index("gh pr merge"),
        )
        self.assertIn("id: merge_release_pr", workflow)
        self.assertIn("id: promote_release_commit", workflow)
        self.assertIn("id: release_branch_before", workflow)
        self.assertIn("EXPECTED_PREVIOUS_RELEASE_SHA: ${{ steps.release_branch_before.outputs.sha }}", workflow)
        self.assertIn("git/matching-refs/heads/$RELEASE_BRANCH", workflow)
        self.assertNotIn("2>/dev/null || true", workflow)
        self.assertIn("steps.release.outcome == 'failure'", workflow)
        self.assertIn("continue-on-error: true", workflow)
        self.assertIn("run: bash platforms/macos/scripts/promote-release-branch.sh", workflow)
        self.assertIn("steps.promote_release_commit.outputs.promoted == 'true'", workflow)
        self.assertIn("id: finalized_promoted_release", workflow)
        self.assertIn("steps.finalized_promoted_release.outputs.release_created", workflow)
        self.assertIn("target_sha:", workflow)
        self.assertIn("steps.requested_release.outputs.target_sha", workflow)
        self.assertIn("ref: ${{ needs.prepare.outputs.target_sha }}", workflow)
        self.assertIn('gh release view "$TAG_NAME" --json isDraft,targetCommitish', workflow)
        self.assertIn("Draft release target must be an immutable full commit SHA", workflow)
        self.assertIn("name: Revalidate draft release target", workflow)
        self.assertLess(workflow.index("name: Revalidate draft release target"), workflow.index("name: Upload and publish release"))
        self.assertIn("run: bash platforms/macos/scripts/create-promoted-release.sh", workflow)
        self.assertIn("id: finalized_release", workflow)
        self.assertIn("steps.merge_release_pr.outputs.merged == 'true'", workflow)
        self.assertIn("steps.finalized_release.outputs.release_created", workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("GH_REPO: ${{ github.repository }}", workflow)
        self.assertIn("gh workflow run ci.yml", merge_release_pr)
        self.assertIn("--field mac_only=true", promote_release_branch)
        self.assertIn("gh run watch", merge_release_pr)
        self.assertIn("--match-head-commit", merge_release_pr)
        self.assertTrue(merge_release_pr.startswith("#!/usr/bin/env bash\n"))
        self.assertIn("git/refs/heads/main", promote_release_branch)
        self.assertIn("force=false", promote_release_branch)
        self.assertIn("gh_api_retry()", promote_release_branch)
        self.assertIn("METASEQUOIA_GH_API_MAX_ATTEMPTS", promote_release_branch)
        self.assertIn("GitHub API request failed", promote_release_branch)
        self.assertTrue(promote_release_branch.startswith("#!/usr/bin/env bash\n"))
        self.assertIn('gh release create "$TAG_NAME"', create_promoted_release)
        self.assertIn('--target "$TARGET_SHA"', create_promoted_release)
        self.assertTrue(create_promoted_release.startswith("#!/usr/bin/env bash\n"))
        self.assertIn("platforms/macos/scripts/package_release.sh", workflow)
        signing_detector = (MACOS_ROOT / "scripts/detect-release-signing.sh").read_text()
        release_publisher = (MACOS_ROOT / "scripts/publish-release.sh").read_text()
        release_packager = (MACOS_ROOT / "scripts/package_release.sh").read_text()
        self.assertIn("macos-universal$ASSET_SUFFIX.pkg", release_publisher)
        self.assertIn("asset_suffix=-unsigned", signing_detector)
        self.assertIn("timeout-minutes: 30", workflow)
        self.assertIn(
            """        include:
          - runner: macos-15
            architecture: arm64
          - runner: macos-15-intel
            architecture: x86_64
""",
            ci_workflow,
        )
        self.assertIn("runs-on: ${{ matrix.runner }}", ci_workflow)
        self.assertIn("gh release upload", release_publisher)
        self.assertIn("gh release edit", release_publisher)
        self.assertIn("METASEQUOIA_REQUIRE_RELEASE_SIGNING", workflow)
        self.assertIn("platforms/macos/scripts/detect-release-signing.sh", workflow)
        self.assertIn("steps.signing.outputs.signing_enabled", workflow)
        self.assertIn("steps.signing.outputs.asset_suffix", workflow)
        self.assertIn("metasequoia-release-mode", release_publisher)
        self.assertIn("ref: ${{ github.event.repository.default_branch }}", workflow)
        self.assertNotIn("ref: ${{ github.sha }}", workflow)
        self.assertIn("$RUNNER_TEMP/detect-release-signing.sh", workflow)
        self.assertIn("$RUNNER_TEMP/package-release.sh", workflow)
        self.assertIn("$RUNNER_TEMP/InstallerDistribution.xml.in", workflow)
        self.assertIn("$RUNNER_TEMP/uninstall.sh", workflow)
        self.assertIn("METASEQUOIA_PROJECT_ROOT", workflow)
        self.assertIn("METASEQUOIA_RELEASE_INSTALL_SCRIPT", workflow)
        self.assertIn("METASEQUOIA_RELEASE_UNINSTALL_SCRIPT", workflow)
        self.assertIn("METASEQUOIA_RELEASE_SETTINGS_SCRIPT", workflow)
        self.assertIn("METASEQUOIA_INSTALLER_DISTRIBUTION", workflow)
        self.assertIn("$RUNNER_TEMP/publish-release.sh", workflow)
        self.assertIn("$RUNNER_TEMP/generate-sparkle-appcast.sh", workflow)
        self.assertIn("SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}", workflow)
        self.assertIn("steps.signing.outputs.signing_enabled == 'true'", workflow)
        self.assertIn("steps.sparkle.outputs.appcast_enabled == 'true'", workflow)
        self.assertNotIn("name: Generate signed Sparkle appcast\n        if: ${{ steps.signing.outputs.signing_enabled", workflow)

        # The secrets context is rejected in a step-level if:, and the workflow then fails to parse and schedules no jobs at all. Release only runs on push to main, so no pull request check can catch it.
        for workflow_path in sorted((PROJECT_ROOT / ".github/workflows").glob("*.yml")):
            for number, line in enumerate(workflow_path.read_text().splitlines(), start=1):
                stripped = line.strip()
                if stripped.startswith("if:") and "secrets." in stripped:
                    self.fail(f"{workflow_path.name}:{number} uses the secrets context in a step condition: {stripped}")
        self.assertIn("Unsigned release: skipping Developer ID signature verification before packaging.", workflow)
        self.assertIn("Unsigned release: skipping source bundle Developer ID signature verification.", release_packager)
        self.assertIn("Sparkle-2.9.6.tar.xz", workflow)
        self.assertIn("52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192", workflow)
        self.assertLess(workflow.index("name: Generate signed Sparkle appcast"), workflow.index("name: Upload and publish release"))
        self.assertIn("git merge-base --is-ancestor HEAD refs/remotes/origin/main", workflow)
        self.assertLess(workflow.index("name: Determine release signing mode"), workflow.index("name: Check out release tag"))
        self.assertLess(workflow.index("name: Verify release tag provenance"), workflow.index("name: Import Developer ID signing certificates"))
        self.assertIn("security import", workflow)
        self.assertIn("notarytool store-credentials", workflow)
        self.assertIn("name: Determine release signing mode", workflow)
        self.assertLess(workflow.index("name: Determine release signing mode"), workflow.index("name: Install dependencies"))
        self.assertIn("Developer ID Application", readme)
        self.assertIn("公证", readme)
        self.assertIn("全拼、小鹤双拼或 86 五笔", readme)
        self.assertIn("作为翻页键", readme)
        self.assertIn("macos-universal-update.zip", readme)
        self.assertIn("`appcast.xml`", readme)
        self.assertIn("即使产物未经 Apple 签名，appcast 依然会发布", readme)
        self.assertIn("是 Sparkle 的更新载荷，不是供手动打开的安装包", readme)
        self.assertIn("启用全拼纠错", readme)
        self.assertIn("原生的「水杉输入法设置」面板", readme)
        self.assertIn("表情与符号", readme)
        self.assertIn("蓝天小雨点、自然码、首右2.0、首右plus 或小鹤", readme)
        self.assertIn("当前用户的 `~/Library/Input Methods`", readme)
        self.assertIn("可能会请求管理员授权", readme)
        self.assertIn("不想注销或使用管理员权限", readme)
        self.assertIn("不会自动注销或重启 Mac", readme)
        self.assertIn("希望立即用上水杉、又不想注销或使用管理员权限时的推荐方式", readme)
        self.assertNotIn("为所有用户安装", readme)
        self.assertNotIn("系统级安装", readme)
        self.assertIn("InputMethodServerPreferencesWindowControllerClass", info_plist)
        self.assertIn("METASEQUOIA_DEVELOPMENT_BUNDLE=$<TARGET_BUNDLE_DIR:MetasequoiaIME>", cmake)
        self.assertIn("@METASEQUOIA_IME_DICTIONARY_SHA256@", info_plist)
        self.assertIn("<key>SUPublicEDKey</key>", info_plist)
        self.assertIn("rSAufajnup+T+d+I4LTs4EAhe5M8bwHemWDKao3CB/E=", info_plist)
        self.assertIn("<key>SUFeedURL</key>", info_plist)
        self.assertIn("releases/latest/download/appcast.xml", info_plist)
        self.assertIn("<key>SUVerifyUpdateBeforeExtraction</key>", info_plist)
        self.assertIn("<key>SURequireSignedFeed</key>", info_plist)
        self.assertIn("<key>LSMinimumSystemVersion</key>", info_plist)
        self.assertIn("@CMAKE_OSX_DEPLOYMENT_TARGET@", info_plist)
        self.assertIn('file(SHA256 "${METASEQUOIA_IME_DICTIONARY}" METASEQUOIA_IME_DICTIONARY_SHA256)', cmake)
        self.assertIn("PreferencesWindowController.mm", cmake)
        self.assertIn("UpdateController.mm", cmake)
        self.assertIn('set(METASEQUOIA_SPARKLE_VERSION "2.9.6")', cmake)
        self.assertIn("Sparkle-${METASEQUOIA_SPARKLE_VERSION}.tar.xz", cmake)
        self.assertIn("52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192", cmake)
        self.assertIn("Contents/Frameworks", cmake)
        self.assertNotIn("UpdateChecker.mm", cmake)
        self.assertNotIn("UpdateCheckerTests.mm", cmake)
        self.assertIn("<key>SUEnableAutomaticChecks</key>", info_plist)
        self.assertIn("${METASEQUOIA_MACOS_ROOT}/scripts/uninstall.sh", cmake)
        self.assertIn("MACOSX_PACKAGE_LOCATION Resources", cmake)
        preferences_controller = (MACOS_ROOT / "src/PreferencesWindowController.mm").read_text()
        self.assertIn("initWithWindowNibName:(NSNibName)windowNibName owner:(id)owner", preferences_controller)
        self.assertIn("showAndActivate", preferences_controller)
        self.assertIn("showAndActivateForStandaloneLaunch", preferences_controller)
        self.assertIn("MetasequoiaStandalonePreferencesDidCloseNotification", preferences_controller)
        self.assertIn("storedScheme", preferences_controller)
        self.assertIn("setStoredScheme", preferences_controller)
        self.assertIn("小鹤双拼", preferences_controller)
        self.assertIn("storedAutocorrectEnabled", preferences_controller)
        self.assertIn("setAutocorrectEnabled", preferences_controller)
        self.assertIn("启用全拼自动纠错", preferences_controller)
        self.assertIn("storedHelpcodeEnabled", preferences_controller)
        self.assertIn("setHelpcodeEnabled", preferences_controller)
        self.assertIn("启用辅助码", preferences_controller)
        self.assertIn("storedQuanpinHelpcodeSchema", preferences_controller)
        self.assertIn("storedShuangpinHelpcodeSchema", preferences_controller)
        # Each preference owns one notification name here. The two schemas briefly shared MetasequoiaHelpcodeDidChangeNotification, whose payload is the enabled BOOL, so a subscriber reading -boolValue would have seen a schema index instead.
        self.assertIn("MetasequoiaQuanpinHelpcodeSchemaDidChangeNotification", preferences_controller)
        self.assertIn("MetasequoiaShuangpinHelpcodeSchemaDidChangeNotification", preferences_controller)
        self.assertNotIn('@"MetasequoiaHelpcodeSchemaDidChangeNotification"', preferences_controller)
        helpcode_enabled_setter = preferences_controller.split("+ (void)setHelpcodeEnabled:", 1)[1].split("\n}", 1)[0]
        self.assertIn("MetasequoiaHelpcodeDidChangeNotification", helpcode_enabled_setter)
        self.assertNotIn("Schema", helpcode_enabled_setter)
        self.assertIn("全拼辅助码方案", preferences_controller)
        self.assertIn("双拼辅助码方案", preferences_controller)
        input_controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()
        self.assertIn("HelpcodeUtils::select_helpcode_schema", input_controller)
        self.assertIn("storedChinesePunctuationEnabled", preferences_controller)
        self.assertIn("setChinesePunctuationEnabled", preferences_controller)
        self.assertIn("使用中文标点", preferences_controller)
        self.assertIn("restoreDefaults:", preferences_controller)
        self.assertIn("恢复默认设置", preferences_controller)
        self.assertIn("CFBundleShortVersionString", preferences_controller)
        self.assertIn('#import "DictionaryInstaller.h"', preferences_controller)
        self.assertIn("refreshDictionaryStatus", preferences_controller)
        self.assertIn("EnsureMetasequoiaDictionary", preferences_controller)
        self.assertIn("constexpr CGFloat kWindowWidth = 680.0", preferences_controller)
        self.assertIn("constexpr CGFloat kWindowHeight = 660.0", preferences_controller)
        self.assertIn("NSWindowToolbarStylePreference", preferences_controller)
        self.assertIn("NSToolbarDisplayModeIconAndLabel", preferences_controller)
        self.assertIn("toolbarSelectableItemIdentifiers", preferences_controller)
        self.assertIn('@"键盘输入", @"外观", @"词库与数据", @"更新与反馈"', preferences_controller)
        self.assertIn('@[ @"全拼输入", @"双拼输入", @"五笔输入" ]', preferences_controller)
        self.assertIn('addItemWithTitle:@"小鹤双拼"', preferences_controller)
        self.assertIn('addItemWithTitle:@"86 五笔"', preferences_controller)
        self.assertIn('accessibilityLabel = @"五笔功能设置"', preferences_controller)
        self.assertIn("selectPreferencesPageFromToolbar:", preferences_controller)
        self.assertIn('NSURL URLWithString:@"https://msime.app/"', preferences_controller)
        self.assertNotIn('accessibilityLabel = @"水杉输入法导航"', preferences_controller)
        self.assertNotIn("sidebar.fillColor", preferences_controller)
        self.assertIn("词库已就绪", preferences_controller)
        self.assertIn("当前输入结束后的下一次按键生效", preferences_controller)
        self.assertIn("词库不可用，请重新安装水杉输入法", preferences_controller)
        input_controller = (MACOS_ROOT / "src/MetasequoiaInputController.mm").read_text()
        self.assertIn("EngineSchemeForStoredPreference", input_controller)
        self.assertIn("reloadSessionFromPreferences", input_controller)
        self.assertIn("prepareSessionIfNeeded", input_controller)
        self.assertIn("kDictionaryRetryDelay", input_controller)
        self.assertIn("- (void)activateServer:(id)sender", input_controller)
        handle_event = input_controller.split("- (BOOL)handleEvent:(NSEvent *)event client:(id)sender", 1)[1].split(
            "- (void)commitLeadingCandidate:(id)sender", 1
        )[0]
        self.assertIn("[self prepareSessionIfNeeded]", handle_event)
        self.assertIn("[self reloadSessionFromPreferences];", handle_event)
        self.assertLess(
            handle_event.index("[self prepareSessionIfNeeded]"),
            handle_event.index("[self reloadSessionFromPreferences];"),
        )
        self.assertLess(
            handle_event.index("[self reloadSessionFromPreferences];"),
            handle_event.index("const NSEventModifierFlags modifiers"),
        )
        reload_session = input_controller.split("- (void)reloadSessionFromPreferences", 1)[1].split(
            "- (BOOL)prepareSessionIfNeeded", 1
        )[0]
        self.assertLess(reload_session.index("_session->has_composition()"), reload_session.index("ReadSessionPreferences()"))
        self.assertIn("_candidateSelection.reset();", reload_session)
        self.assertIn("[_candidatePanel hide];", reload_session)
        controller_initialization = input_controller.split("- (instancetype)initWithServer:", 1)[1].split(
            "- (void)reloadSessionFromPreferences", 1
        )[0]
        self.assertLess(
            controller_initialization.index("_candidatePanel ="),
            controller_initialization.index("prepareSessionIfNeeded"),
        )
        self.assertIn("NSString *characters = event.characters;", input_controller)
        self.assertIn("NSString *charactersIgnoringModifiers = event.charactersIgnoringModifiers;", handle_event)
        self.assertIn("candidatePageShortcutModified", handle_event)
        character_input = handle_event.split("ControllerKeyAction::Character:", 1)[1]
        self.assertNotIn("charactersIgnoringModifiers", character_input)
        commit_composition = input_controller.split("- (void)commitComposition:(id)sender", 1)[1].split(
            "- (void)deactivateServer:(id)sender", 1
        )[0]
        self.assertIn("commitLeadingCandidate", commit_composition)
        self.assertNotIn("Command::CommitRaw", commit_composition)
        self.assertIn("在没有活动组词时于下一次按键前生效", readme)

        release_installer = (MACOS_ROOT / "scripts/install-release.sh").read_text()
        settings_launcher = (MACOS_ROOT / "scripts/open-settings.sh").read_text()
        self.assertNotIn("xcrun", release_installer)
        self.assertNotIn("xattr", release_installer)
        self.assertIn("spctl --assess --type execute", release_installer)
        self.assertIn("--register-input-source", release_installer)
        self.assertIn("Registered and enabled 水杉输入法 with macOS", release_installer)
        self.assertIn("--show-settings", settings_launcher)
        self.assertIn("Library/Input Methods/MetasequoiaIME.app", settings_launcher)
        self.assertIn("Open Settings.command", readme)
        self.assertIn("安装器在替换已有安装前始终校验 bundle 的代码签名", readme)
        self.assertIn("使其无需注销即可出现在输入法菜单中", readme)
        self.assertIn("两种方式都会安装当前用户的 bundle", readme)
        self.assertIn("并自动为当前用户启用水杉输入法", readme)
        self.assertIn("安装后脚本会自动注册并启用水杉输入法", readme)
        self.assertIn("明确标注为未签名的构建则需要输入 `I UNDERSTAND`", readme)
        self.assertNotIn("同时校验代码签名与 Gatekeeper", readme)
        self.assertIn("./MetasequoiaIME-vX.Y.Z/Uninstall.command", readme)
        self.assertIn("MetasequoiaIME.app/Contents/Resources/Uninstall.command", readme)
        self.assertIn("默认保留偏好设置与学习数据", readme)
        self.assertNotIn("xattr -dr com.apple.quarantine", readme)
        self.assertNotIn("swift", release_installer.lower())
        install_script = (MACOS_ROOT / "scripts/install.sh").read_text()
        self.assertIn("staging_root=$(mktemp -d", install_script)
        self.assertIn("backup_root=$(mktemp -d", install_script)
        self.assertIn("install_complete=false", install_script)
        self.assertIn("METASEQUOIA_REGISTER_INPUT_SOURCE_COMMAND", install_script)
        self.assertIn("--register-input-source", install_script)
        self.assertNotIn("register_input_source.swift", install_script)
        self.assertIn("TISRegisterInputSource", (MACOS_ROOT / "scripts/register_input_source.swift").read_text())
        package_script = (MACOS_ROOT / "scripts/package_release.sh").read_text()
        self.assertIn("productsign", package_script)
        self.assertIn("notarytool", package_script)
        self.assertIn("Commercial release signing requires", package_script)
        # The appcast is published for unsigned releases too, so packaging must not turn automatic
        # checks off for them.
        self.assertNotIn("SUEnableAutomaticChecks", package_script)
        self.assertIn("METASEQUOIA_VOICE_ENTITLEMENTS", package_script)
        self.assertIn("Voice input entitlements not found at", package_script)
        self.assertNotIn("${0:A:h:h}/resources", package_script)
        postinstall_script = MACOS_ROOT / "scripts/pkg-postinstall.sh"
        self.assertTrue(postinstall_script.is_file())
        self.assertIn("launchctl asuser", postinstall_script.read_text())
        self.assertIn("--register-input-source", postinstall_script.read_text())
        self.assertIn('pkgbuild --component', package_script)
        self.assertIn('--scripts "$pkg_scripts"', package_script)
        license_text = (PROJECT_ROOT / "LICENSE").read_text()
        notices = (PROJECT_ROOT / "THIRD_PARTY_NOTICES.txt").read_text()
        self.assertIn("GNU GENERAL PUBLIC LICENSE", license_text)
        self.assertIn("MetasequoiaImeEngine", notices)
        self.assertIn("googlepinyinime-rev", notices)
        self.assertIn("utfcpp", notices)
        self.assertIn("THIRD_PARTY_NOTICES.txt", package_script)
        privacy = (PROJECT_ROOT / "PRIVACY.md").read_text()
        security = (PROJECT_ROOT / "SECURITY.md").read_text()
        self.assertIn("~/Library/Application Support/metasequoiaime/", privacy)
        self.assertIn("does not send typed text", privacy)
        self.assertIn("does not sell personal data", privacy)
        self.assertIn("current recording is sent to the HTTPS endpoint configured by the user", privacy)
        self.assertIn("API tokens are stored in the system Keychain", privacy)
        self.assertIn("GitHub's public Releases API", privacy)
        self.assertIn("IP address and standard network request metadata", privacy)
        self.assertIn(
            "If learning is disabled while a composition is active, that composition keeps the setting it started "
            "with; after it is committed or cancelled, newly started compositions do not update word frequencies.",
            privacy,
        )
        self.assertIn("SECURITY.md", privacy)
        self.assertIn("latest published version", security)
        self.assertIn("Do not open a public issue", security)
        self.assertIn("MetasequoiaImeApple security report", security)
        self.assertIn("PRIVACY.md", readme)
        self.assertIn("SECURITY.md", readme)

    def test_dependabot_tracks_actions_and_expected_submodule_branches(self):
        dependabot = (PROJECT_ROOT / ".github/dependabot.yml").read_text()
        gitmodules = PROJECT_ROOT / ".gitmodules"

        def read_submodule_value(name, key):
            result = subprocess.run(
                ["git", "config", "-f", str(gitmodules), "--get", f"submodule.{name}.{key}"],
                check=False,
                capture_output=True,
                text=True,
                # A worktree checkout may expose a placeholder .git file whose
                # linked metadata is unavailable to this isolated config read.
                # Run outside the repository so git only parses .gitmodules.
                cwd=gitmodules.parent.parent,
            )
            # git config exits 1 for a key that is absent, which is a real answer here rather than a
            # failure: it is how the dictionary assertion below states that there is no submodule.
            return result.stdout.strip() if result.returncode == 0 else None

        def submodule_value(name, key):
            value = read_submodule_value(name, key)
            self.assertIsNotNone(value, f"submodule.{name}.{key} is missing from .gitmodules")
            return value

        self.assertEqual(dependabot.count('package-ecosystem: "github-actions"'), 1)
        self.assertEqual(dependabot.count('package-ecosystem: "gitsubmodule"'), 1)
        # Assert each ecosystem's own interval rather than a total count: counting means changing
        # either schedule fails on an arithmetic mismatch that says nothing about which one moved.
        actions_block = dependabot.split('package-ecosystem: "github-actions"', 1)[1].split("- package-ecosystem:", 1)[0]
        submodule_block = dependabot.split('package-ecosystem: "gitsubmodule"', 1)[1].split("- package-ecosystem:", 1)[0]
        self.assertIn('interval: "monthly"', actions_block)
        # The engine submodule moves fast enough that a monthly sweep lets it drift far enough for a
        # single bump to carry unrelated behaviour changes, which is how #222 landed two regressions.
        self.assertIn('interval: "daily"', submodule_block)
        self.assertEqual(dependabot.count('prefix: "chore(deps)"'), 2)
        self.assertEqual(submodule_value("vendor/MetasequoiaImeEngine", "path"), "vendor/MetasequoiaImeEngine")
        self.assertEqual(
            submodule_value("vendor/MetasequoiaImeEngine", "url"),
            "https://github.com/metasequoiaime/MSIME-Engine.git",
        )
        self.assertEqual(submodule_value("vendor/MetasequoiaImeEngine", "branch"), "main")
        # The dictionary is deliberately not a submodule. Vendoring the sources meant rebuilding
        # MSIME-Dict's pipeline here and shipping whatever revision the pin happened to hold, which
        # is how the personal data in quick_phrases.txt stayed in shipped builds for two days after
        # it was replaced upstream (MSIME-Windows#74). It is downloaded from a pinned, checksummed
        # release instead; re-adding it as a submodule would reintroduce that drift.
        self.assertIsNone(read_submodule_value("vendor/MetasequoiaImeDict", "path"))
        self.assertIsNone(read_submodule_value("vendor/MetasequoiaImeHelpCode", "path"))
        self.assertIsNone(read_submodule_value("tools/MetasequoiaImeDict", "path"))

    def test_dictionary_is_fetched_from_a_locked_verified_release(self):
        source = (PROJECT_ROOT / "scripts/fetch_dictionary.py").read_text()
        lock = json.loads((PROJECT_ROOT / "product-lock.json").read_text())["dictionary"]

        self.assertFalse((MACOS_ROOT / "scripts/build_dictionary.py").exists())
        # A branch or a bare "latest" would make two builds of the same commit ship different data.
        self.assertRegex(lock["tag"], r"\Adict-\d{4}\.\d{2}\.\d{2}\Z")
        self.assertEqual(lock["repository"], "metasequoiaime/MSIME-Engine")
        # Not read from a gitlink: MSIME-Linux#47 found its dict pin attesting to 55bd649 while the
        # shipped bytes came from 0c7368c, because nothing moves that pin when the tag does.
        self.assertRegex(lock["source_commit"], r"\A[0-9a-f]{40}\Z")
        # The digests are committed rather than taken from the SHA256SUMS.txt that travels with the
        # data, so a retagged release fails the build instead of shipping.
        for name in ("msime.db", "SHA256SUMS.txt", "dictionary-manifest.json"):
            self.assertRegex(lock["assets"][name], r"\A[0-9a-f]{64}\Z")
        self.assertIn("product_lock.verify_assets", source)
        # The probe that would have caught the old build: quick_parases comes from a stage the
        # removed build_dictionary.py never ran, so a database missing it looked perfectly valid.
        self.assertIn("quick_parases", source)
        self.assertIn("PRAGMA integrity_check", source)

        # Every path that produces a build has to go through it, including the iOS variant, which
        # slices the same database rather than generating its own.
        self.assertIn(
            "python3 \"$project_root/scripts/fetch_dictionary.py\"",
            (MACOS_ROOT / "scripts/build.sh").read_text(),
        )
        self.assertIn(
            '["python3", "scripts/fetch_dictionary.py"]',
            (PROJECT_ROOT / "platforms/ios/scripts/prepare_dictionary.py").read_text(),
        )
        self.assertIn(
            "run: python3 scripts/fetch_dictionary.py",
            (PROJECT_ROOT / ".github/workflows/release.yml").read_text(),
        )
        ci = (PROJECT_ROOT / ".github/workflows/ci.yml").read_text()
        self.assertIn("python3 scripts/product_lock.py validate", ci)
        self.assertIn("python3 platforms/macos/tests/ProductLockTests.py", ci)

    def test_macos_bundle_packages_helpcode_assets(self):
        cmake = (PROJECT_ROOT / "CMakeLists.txt").read_text()
        self.assertIn("vendor/MetasequoiaImeEngine/helpcode/helpcodes", cmake)
        self.assertIn("Resources/helpcodes", cmake)

    def test_release_scripts_have_valid_zsh_syntax(self):
        for relative_path in (
            "scripts/install-release.sh",
            "scripts/package_release.sh",
        ):
            result = subprocess.run(["zsh", "-n", str(MACOS_ROOT / relative_path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        result = subprocess.run(
            ["bash", "-n", str(MACOS_ROOT / "scripts/merge-release-pr.sh")], capture_output=True, text=True
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        for relative_path in ("scripts/detect-release-signing.sh", "scripts/publish-release.sh"):
            result = subprocess.run(
                ["bash", "-n", str(MACOS_ROOT / relative_path)], capture_output=True, text=True
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_package_script_refuses_ambiguously_named_unsigned_assets(self):
        environment = os.environ.copy()
        for variable in (
            "METASEQUOIA_REQUIRE_RELEASE_SIGNING",
            "METASEQUOIA_DEVELOPER_ID_APPLICATION",
            "METASEQUOIA_DEVELOPER_ID_INSTALLER",
            "METASEQUOIA_NOTARY_PROFILE",
            "METASEQUOIA_RELEASE_ASSET_SUFFIX",
        ):
            environment.pop(variable, None)

        result = subprocess.run(
            [MACOS_ROOT / "scripts/package_release.sh", "v1.2.3"],
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("require METASEQUOIA_RELEASE_ASSET_SUFFIX=-unsigned", result.stderr)


if __name__ == "__main__":
    unittest.main()