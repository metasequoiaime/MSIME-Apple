import hashlib
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import xml.etree.ElementTree as ElementTree
import zipfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
MACOS_ROOT = PROJECT_ROOT / "platforms" / "macos"
SIGNING_ENVIRONMENT = (
    "METASEQUOIA_REQUIRE_RELEASE_SIGNING",
    "METASEQUOIA_DEVELOPER_ID_APPLICATION",
    "METASEQUOIA_DEVELOPER_ID_INSTALLER",
    "METASEQUOIA_NOTARY_PROFILE",
)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


class ReleasePackageTests(unittest.TestCase):
    def test_installers_reject_unsafe_home_before_running_commands(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            command_log = temporary / "commands.log"
            fake_command = (
                "#!/bin/sh\n"
                "printf '%s %s\\n' \"$0\" \"$*\" >> \"$UNSAFE_COMMAND_LOG\"\n"
                "exit 97\n"
            )
            for command_name in ("codesign", "mkdir"):
                command = fake_bin / command_name
                command.write_text(fake_command)
                command.chmod(0o755)

            release_root = temporary / "release"
            release_root.mkdir()
            release_installer = release_root / "Install.command"
            shutil.copy2(MACOS_ROOT / "scripts/install-release.sh", release_installer)
            (release_root / "MetasequoiaIME.app").mkdir()

            for installer in (
                MACOS_ROOT / "scripts/install.sh",
                release_installer,
                MACOS_ROOT / "scripts/open-settings.sh",
            ):
                for unsafe_home in (
                    "",
                    "/",
                    "/./",
                    "//",
                    "/tmp/..",
                    "relative-home",
                ):
                    with self.subTest(installer=installer.name, home=unsafe_home):
                        command_log.unlink(missing_ok=True)
                        environment = os.environ.copy()
                        environment["HOME"] = unsafe_home
                        environment["PATH"] = str(fake_bin)
                        environment["UNSAFE_COMMAND_LOG"] = str(command_log)

                        result = subprocess.run(
                            ["/bin/zsh", installer],
                            capture_output=True,
                            text=True,
                            env=environment,
                            cwd=temporary,
                        )

                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(
                            "HOME must be an absolute current-user directory.",
                            result.stderr,
                        )
                        self.assertFalse(command_log.exists())

    def test_development_install_restores_previous_bundle_when_registration_fails(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            fake_bin = Path(temporary_directory) / "bin"
            fake_bin.mkdir()
            fake_pkill = fake_bin / "pkill"
            fake_pkill.write_text("#!/bin/sh\nexit 0\n")
            fake_pkill.chmod(0o755)
            fake_pgrep = fake_bin / "pgrep"
            fake_pgrep.write_text("#!/bin/sh\nexit 1\n")
            fake_pgrep.chmod(0o755)
            fake_registrar = fake_bin / "register-input-source"
            fake_registrar.write_text("#!/bin/sh\nexit 47\n")
            fake_registrar.chmod(0o755)

            test_home = (Path(temporary_directory) / "home").resolve()
            destination = test_home / "Library/Input Methods/MetasequoiaIME.app"
            previous_marker = destination / "Contents/previous-installation.txt"
            previous_marker.parent.mkdir(parents=True)
            previous_marker.write_text("previous installation\n")
            environment = os.environ.copy()
            environment["HOME"] = str(test_home)
            environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
            environment["METASEQUOIA_REGISTER_INPUT_SOURCE_COMMAND"] = str(fake_registrar)

            result = subprocess.run(
                [MACOS_ROOT / "scripts/install.sh"],
                capture_output=True,
                text=True,
                env=environment,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(previous_marker.read_text(), "previous installation\n")
            self.assertFalse(any(destination.parent.glob(".MetasequoiaIME.installing.*")))
            self.assertFalse(any(destination.parent.glob(".MetasequoiaIME.backup.*")))

    def test_installers_clean_staging_when_backup_directory_creation_fails(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            fake_mktemp = fake_bin / "mktemp"
            fake_mktemp.write_text(
                "#!/bin/sh\n"
                "set -eu\n"
                "if test -f \"$FAKE_MKTEMP_STATE\"; then\n"
                "  if test \"${FAKE_MKTEMP_FAILURE:-exit}\" = term; then\n"
                "    kill -TERM \"$PPID\"\n"
                "    sleep 1\n"
                "  fi\n"
                "  exit 72\n"
                "fi\n"
                ": > \"$FAKE_MKTEMP_STATE\"\n"
                "target=${2%XXXXXX}partial\n"
                "/bin/mkdir -p \"$target\"\n"
                "printf '%s\\n' \"$target\"\n"
            )
            fake_mktemp.chmod(0o755)
            for command_name in ("codesign", "spctl"):
                command = fake_bin / command_name
                command.write_text("#!/bin/sh\nexit 0\n")
                command.chmod(0o755)

            release_root = temporary / "release"
            release_root.mkdir()
            release_installer = release_root / "Install.command"
            shutil.copy2(MACOS_ROOT / "scripts/install-release.sh", release_installer)
            (release_root / "MetasequoiaIME.app").mkdir()

            installers = (MACOS_ROOT / "scripts/install.sh", release_installer)
            for index, (installer, failure) in enumerate(
                (installer, failure)
                for installer in installers
                for failure in ("exit", "term")
            ):
                with self.subTest(installer=installer.name, failure=failure):
                    test_home = (temporary / f"home-{index}").resolve()
                    state = temporary / f"mktemp-{index}.state"
                    environment = os.environ.copy()
                    environment["HOME"] = str(test_home)
                    environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
                    environment["FAKE_MKTEMP_STATE"] = str(state)
                    environment["FAKE_MKTEMP_FAILURE"] = failure

                    result = subprocess.run(
                        ["/bin/zsh", installer],
                        capture_output=True,
                        text=True,
                        env=environment,
                    )

                    destination_root = test_home / "Library/Input Methods"
                    if failure == "exit":
                        self.assertEqual(result.returncode, 72, result.stderr)
                    else:
                        self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(
                        any(destination_root.glob(".MetasequoiaIME.installing.*")),
                        result.stderr,
                    )
                    self.assertFalse(
                        any(destination_root.glob(".MetasequoiaIME.backup.*")),
                        result.stderr,
                    )

    def test_installers_leave_previous_bundle_when_input_method_does_not_stop(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            pkill_log = temporary / "pkill.log"
            pgrep_log = temporary / "pgrep.log"
            fake_pkill = fake_bin / "pkill"
            fake_pkill.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$FAKE_PKILL_LOG\"\n"
                "exit 0\n"
            )
            fake_pkill.chmod(0o755)
            fake_pgrep = fake_bin / "pgrep"
            fake_pgrep.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' \"$*\" >> \"$FAKE_PGREP_LOG\"\n"
                "exit \"$FAKE_PGREP_STATUS\"\n"
            )
            fake_pgrep.chmod(0o755)
            for command_name, exit_status in (
                ("sleep", 0),
                ("codesign", 0),
                ("spctl", 0),
                ("xcrun", 0),
            ):
                command = fake_bin / command_name
                command.write_text(f"#!/bin/sh\nexit {exit_status}\n")
                command.chmod(0o755)

            release_root = temporary / "release"
            release_root.mkdir()
            release_installer = release_root / "Install.command"
            shutil.copy2(MACOS_ROOT / "scripts/install-release.sh", release_installer)
            (release_root / "MetasequoiaIME.app").mkdir()

            installers = (MACOS_ROOT / "scripts/install.sh", release_installer)
            scenarios = ((0, "did not stop in time"), (2, "Could not verify"))
            for index, (installer, (pgrep_status, expected_error)) in enumerate(
                (installer, scenario)
                for installer in installers
                for scenario in scenarios
            ):
                with self.subTest(installer=installer.name, pgrep_status=pgrep_status):
                    test_home = (temporary / f"home-{index}").resolve()
                    destination = test_home / "Library/Input Methods/MetasequoiaIME.app"
                    previous_marker = destination / "Contents/previous-installation.txt"
                    previous_marker.parent.mkdir(parents=True)
                    previous_marker.write_text("previous installation\n")
                    environment = os.environ.copy()
                    environment["HOME"] = str(test_home)
                    environment["PATH"] = f"{fake_bin}:{environment['PATH']}"
                    environment["FAKE_PKILL_LOG"] = str(pkill_log)
                    environment["FAKE_PGREP_LOG"] = str(pgrep_log)
                    environment["FAKE_PGREP_STATUS"] = str(pgrep_status)

                    result = subprocess.run(
                        ["/bin/zsh", installer],
                        capture_output=True,
                        text=True,
                        env=environment,
                    )

                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(expected_error, result.stderr)
                    self.assertEqual(previous_marker.read_text(), "previous installation\n")
                    self.assertFalse(any(destination.parent.glob(".MetasequoiaIME.installing.*")))
                    self.assertFalse(any(destination.parent.glob(".MetasequoiaIME.backup.*")))

            for arguments in pkill_log.read_text().splitlines():
                self.assertIn(f"-TERM -u {os.geteuid()} -f ^", arguments)
                self.assertIn("/Contents/MacOS/MetasequoiaIME( |$)", arguments)
            for arguments in pgrep_log.read_text().splitlines():
                self.assertIn(f"-u {os.geteuid()} -f ^", arguments)
                self.assertIn("/Contents/MacOS/MetasequoiaIME( |$)", arguments)

    def test_installers_scope_process_shutdown_to_installed_bundle(self):
        for installer in (MACOS_ROOT / "scripts/install.sh", MACOS_ROOT / "scripts/install-release.sh"):
            with self.subTest(installer=installer.name):
                script = installer.read_text()
                self.assertIn(
                    'pkill -TERM -u "$EUID" -f "$process_pattern"',
                    script,
                )
                self.assertIn(
                    'pgrep -u "$EUID" -f "$process_pattern"',
                    script,
                )
                self.assertNotIn(
                    'pkill -TERM -x -u "$EUID" MetasequoiaIME',
                    script,
                )

    def test_installers_reject_concurrent_installation(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            for command_name, exit_status in (
                ("codesign", 0),
                ("spctl", 0),
                ("pkill", 0),
                ("pgrep", 1),
                ("xcrun", 0),
            ):
                command = fake_bin / command_name
                command.write_text(f"#!/bin/sh\nexit {exit_status}\n")
                command.chmod(0o755)
            fake_registrar = fake_bin / "register-input-source"
            fake_registrar.write_text("#!/bin/sh\nexit 0\n")
            fake_registrar.chmod(0o755)

            fake_ditto = fake_bin / "ditto"
            fake_ditto.write_text(
                "#!/bin/sh\n"
                "set -eu\n"
                "if /bin/mkdir \"$FAKE_DITTO_ACTIVE\" 2>/dev/null; then\n"
                "  : > \"$FAKE_DITTO_STARTED\"\n"
                "  while test ! -e \"$FAKE_DITTO_RELEASE\"; do /bin/sleep 0.02; done\n"
                "  /usr/bin/ditto \"$@\"\n"
                "  /bin/rmdir \"$FAKE_DITTO_ACTIVE\"\n"
                "else\n"
                "  : > \"$FAKE_DITTO_OVERLAP\"\n"
                "  /usr/bin/ditto \"$@\"\n"
                "fi\n"
            )
            fake_ditto.chmod(0o755)

            release_root = temporary / "release"
            release_root.mkdir()
            installer = release_root / "Install.command"
            shutil.copy2(MACOS_ROOT / "scripts/install-release.sh", installer)
            (release_root / "MetasequoiaIME.app").mkdir()
            installers = (MACOS_ROOT / "scripts/install.sh", installer)
            for index, tested_installer in enumerate(installers):
                with self.subTest(installer=tested_installer.name):
                    active = temporary / f"ditto-active-{index}"
                    started = temporary / f"ditto-started-{index}"
                    release = temporary / f"ditto-release-{index}"
                    overlap = temporary / f"ditto-overlap-{index}"
                    test_home = (temporary / f"home-{index}").resolve()
                    environment = os.environ.copy()
                    environment.update(
                        {
                            "HOME": str(test_home),
                            "PATH": f"{fake_bin}:{environment['PATH']}",
                            "FAKE_DITTO_ACTIVE": str(active),
                            "FAKE_DITTO_STARTED": str(started),
                            "FAKE_DITTO_RELEASE": str(release),
                            "FAKE_DITTO_OVERLAP": str(overlap),
                            "METASEQUOIA_REGISTER_INPUT_SOURCE_COMMAND": str(fake_registrar),
                        }
                    )

                    first = subprocess.Popen(
                        ["/bin/zsh", tested_installer],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        env=environment,
                    )
                    try:
                        for _ in range(100):
                            if started.exists():
                                break
                            if first.poll() is not None:
                                break
                            time.sleep(0.02)
                        self.assertTrue(
                            started.exists(),
                            "The first installer did not reach the protected section.",
                        )

                        second = subprocess.run(
                            ["/bin/zsh", tested_installer],
                            capture_output=True,
                            text=True,
                            env=environment,
                            timeout=5,
                        )
                    finally:
                        release.touch()
                        first_stdout, first_stderr = first.communicate(timeout=10)

                    self.assertEqual(first.returncode, 0, first_stdout + first_stderr)
                    self.assertNotEqual(second.returncode, 0)
                    self.assertIn(
                        "Another MetasequoiaIME installation is already running",
                        second.stderr,
                    )
                    self.assertFalse(
                        overlap.exists(),
                        "Two installers entered the bundle-copy section concurrently.",
                    )
                    destination_root = test_home / "Library/Input Methods"
                    self.assertFalse(any(destination_root.glob(".MetasequoiaIME.installing.*")))
                    self.assertFalse(any(destination_root.glob(".MetasequoiaIME.backup.*")))

    def test_signed_packaging_exercises_signing_notarization_and_gatekeeper(self):
        bundle = Path(sys.argv[1]).resolve()
        version = subprocess.run(
            [
                "/usr/libexec/PlistBuddy",
                "-c",
                "Print :CFBundleShortVersionString",
                bundle / "Contents/Info.plist",
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary = Path(temporary_directory)
            legacy_bundle = temporary / "MetasequoiaIME.app"
            shutil.copytree(bundle, legacy_bundle, symlinks=True)
            legacy_uninstaller = legacy_bundle / "Contents/Resources/Uninstall.command"
            legacy_uninstaller.unlink()
            subprocess.run(
                ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", legacy_bundle],
                check=True,
            )
            fake_bin = temporary / "bin"
            fake_bin.mkdir()
            signing_log = temporary / "signing.log"
            fake_codesign = fake_bin / "codesign"
            fake_codesign.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "printf 'codesign %s\\n' \"$*\" >> \"$FAKE_SIGNING_LOG\"\n"
                "case \" $* \" in\n"
                "  *' --force '*)\n"
                "    target=\n"
                "    for argument in \"$@\"; do target=$argument; done\n"
                "    entitlement=\n"
                "    previous=\n"
                "    for argument in \"$@\"; do\n"
                "      if [[ $previous == --entitlements ]]; then entitlement=$argument; fi\n"
                "      previous=$argument\n"
                "    done\n"
                "    exec /usr/bin/codesign --force --deep --entitlements \"$entitlement\" --sign - \"$target\"\n"
                "    ;;\n"
                "esac\n"
                "exec /usr/bin/codesign \"$@\"\n"
            )
            fake_codesign.chmod(0o755)
            fake_productsign = fake_bin / "productsign"
            fake_productsign.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "printf 'productsign %s\\n' \"$*\" >> \"$FAKE_SIGNING_LOG\"\n"
                "source_path=\n"
                "destination_path=\n"
                "for argument in \"$@\"; do\n"
                "  source_path=$destination_path\n"
                "  destination_path=$argument\n"
                "done\n"
                "exec /bin/cp \"$source_path\" \"$destination_path\"\n"
            )
            fake_productsign.chmod(0o755)
            fake_xcrun = fake_bin / "xcrun"
            fake_xcrun.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "printf 'xcrun %s\\n' \"$*\" >> \"$FAKE_SIGNING_LOG\"\n"
            )
            fake_xcrun.chmod(0o755)

            legacy_project_root = temporary / "legacy-project-root"
            legacy_project_root.mkdir()
            shutil.copy2(PROJECT_ROOT / "LICENSE", legacy_project_root / "LICENSE")
            shutil.copy2(
                PROJECT_ROOT / "THIRD_PARTY_NOTICES.txt",
                legacy_project_root / "THIRD_PARTY_NOTICES.txt",
            )
            legacy_scripts = legacy_project_root / "platforms/macos/scripts"
            legacy_scripts.mkdir(parents=True)
            shutil.copy2(
                MACOS_ROOT / "scripts/pkg-postinstall.sh",
                legacy_scripts / "pkg-postinstall.sh",
            )
            legacy_resources = legacy_project_root / "platforms/macos/resources"
            legacy_resources.mkdir(parents=True)
            shutil.copy2(
                MACOS_ROOT / "resources/VoiceInput.entitlements",
                legacy_resources / "VoiceInput.entitlements",
            )

            # The release workflow copies the packaging script out of the checkout and runs it from
            # $RUNNER_TEMP, so running it in-tree let an input that resolved relative to the
            # script's own location pass here and fail there. Everything it reads has to come from
            # the project root or an explicit override.
            staged_script = temporary / "staged" / "package-release.sh"
            staged_script.parent.mkdir()
            shutil.copy2(MACOS_ROOT / "scripts/package_release.sh", staged_script)
            staged_script.chmod(0o755)

            output = temporary / "output"
            environment = os.environ.copy()
            environment.update(
                {
                    "PATH": f"{fake_bin}:{environment['PATH']}",
                    "FAKE_SIGNING_LOG": str(signing_log),
                    "METASEQUOIA_REQUIRE_RELEASE_SIGNING": "true",
                    "METASEQUOIA_DEVELOPER_ID_APPLICATION": "Developer ID Application: Test",
                    "METASEQUOIA_DEVELOPER_ID_INSTALLER": "Developer ID Installer: Test",
                    "METASEQUOIA_NOTARY_PROFILE": "metasequoia-test-notary",
                    "METASEQUOIA_RELEASE_ASSET_SUFFIX": "",
                    "METASEQUOIA_PROJECT_ROOT": str(legacy_project_root),
                    "METASEQUOIA_RELEASE_INSTALL_SCRIPT": str(
                        MACOS_ROOT / "scripts/install-release.sh"
                    ),
                    "METASEQUOIA_RELEASE_UNINSTALL_SCRIPT": str(
                        MACOS_ROOT / "scripts/uninstall.sh"
                    ),
                    "METASEQUOIA_RELEASE_SETTINGS_SCRIPT": str(
                        MACOS_ROOT / "scripts/open-settings.sh"
                    ),
                    "METASEQUOIA_INSTALLER_DISTRIBUTION": str(
                        MACOS_ROOT / "resources/InstallerDistribution.xml.in"
                    ),
                }
            )
            result = subprocess.run(
                [staged_script, f"v{version}", legacy_bundle, output],
                capture_output=True,
                text=True,
                env=environment,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

            archive = output / f"MetasequoiaIME-v{version}-macos-universal.zip"
            update_archive = output / f"MetasequoiaIME-v{version}-macos-universal-update.zip"
            installer_package = output / f"MetasequoiaIME-v{version}-macos-universal.pkg"
            self.assertTrue(archive.is_file())
            self.assertTrue(archive.with_suffix(".zip.sha256").is_file())
            self.assertTrue(update_archive.is_file())
            self.assertTrue(update_archive.with_suffix(".zip.sha256").is_file())
            self.assertTrue(installer_package.is_file())
            self.assertTrue(installer_package.with_suffix(".pkg.sha256").is_file())
            self.assertFalse(any(output.glob("*-unsigned.*")))
            self.assertFalse(legacy_uninstaller.exists())

            signing_calls = signing_log.read_text()
            self.assertIn("--sign Developer ID Application: Test", signing_calls)
            # Resolved from the project root, not from wherever the script itself happens to sit.
            self.assertIn(
                f"--entitlements {legacy_resources.resolve()}/VoiceInput.entitlements", signing_calls
            )
            self.assertIn("productsign --sign Developer ID Installer: Test", signing_calls)
            notary_calls = [line for line in signing_calls.splitlines() if line.startswith("xcrun notarytool submit ")]
            self.assertEqual(len(notary_calls), 2)
            self.assertTrue(any("/MetasequoiaIME-notary.zip " in line for line in notary_calls))
            self.assertTrue(any("-macos-universal.pkg " in line for line in notary_calls))
            for notary_call in notary_calls:
                self.assertIn("--keychain-profile metasequoia-test-notary --wait", notary_call)
            staple_calls = [line for line in signing_calls.splitlines() if line.startswith("xcrun stapler staple ")]
            validate_calls = [line for line in signing_calls.splitlines() if line.startswith("xcrun stapler validate ")]
            self.assertEqual(len(staple_calls), 2)
            self.assertEqual(len(validate_calls), 2)
            for stapler_calls in (staple_calls, validate_calls):
                self.assertTrue(any(line.endswith("/MetasequoiaIME.app") for line in stapler_calls))
                self.assertTrue(any(line.endswith("-macos-universal.pkg") for line in stapler_calls))

            extracted = temporary / "signed-extracted"
            subprocess.run(["ditto", "-x", "-k", archive, extracted], check=True)
            package_root = extracted / f"MetasequoiaIME-v{version}"
            self.assertFalse((package_root / "UNSIGNED_BUILD.txt").exists())
            packaged_uninstaller = package_root / "MetasequoiaIME.app/Contents/Resources/Uninstall.command"
            self.assertTrue(packaged_uninstaller.is_file())
            self.assertTrue(os.access(packaged_uninstaller, os.X_OK))
            self.assertEqual(packaged_uninstaller.read_bytes(), (MACOS_ROOT / "scripts/uninstall.sh").read_bytes())
            subprocess.run(
                ["/usr/bin/codesign", "--verify", "--deep", "--strict", package_root / "MetasequoiaIME.app"],
                check=True,
            )
            entitlements = subprocess.run(
                ["/usr/bin/codesign", "-d", "--entitlements", ":-", package_root / "MetasequoiaIME.app"],
                check=True, capture_output=True,
            ).stdout
            self.assertTrue(plistlib.loads(entitlements)["com.apple.security.device.audio-input"])
            install_command = (package_root / "Install.command").read_text()
            self.assertIn("spctl --assess --type execute", install_command)
            settings_command = package_root / "Open Settings.command"
            self.assertFalse(
                settings_command.exists(),
                "A standalone-settings launcher was injected into a legacy bundle without the capability marker.",
            )

            expanded_package = temporary / "signed-expanded-package"
            subprocess.run(["pkgutil", "--expand-full", installer_package, expanded_package], check=True)
            installer_readme = (expanded_package / "Resources/InstallerReadMe.txt").read_text()
            self.assertIn("Developer ID signed and notarized", installer_readme)
            self.assertNotIn("UNSIGNED TEST BUILD", installer_readme)
            component_info_path = next(expanded_package.glob("*.pkg/PackageInfo"))
            installer_uninstaller = (
                component_info_path.parent / "Payload/MetasequoiaIME.app/Contents/Resources/Uninstall.command"
            )
            self.assertTrue(installer_uninstaller.is_file())
            self.assertTrue(os.access(installer_uninstaller, os.X_OK))
            self.assertEqual(installer_uninstaller.read_bytes(), (MACOS_ROOT / "scripts/uninstall.sh").read_bytes())

            fake_spctl = fake_bin / "spctl"
            fake_spctl.write_text(
                "#!/bin/bash\n"
                "set -euo pipefail\n"
                "printf 'spctl %s\\n' \"$*\" >> \"$FAKE_SIGNING_LOG\"\n"
            )
            fake_spctl.chmod(0o755)
            fake_pkill = fake_bin / "pkill"
            fake_pkill.write_text("#!/bin/sh\nexit 0\n")
            fake_pkill.chmod(0o755)
            fake_pgrep = fake_bin / "pgrep"
            fake_pgrep.write_text("#!/bin/sh\nexit 1\n")
            fake_pgrep.chmod(0o755)
            fake_registrar = fake_bin / "register-input-source"
            fake_registrar.write_text("#!/bin/sh\nexit 0\n")
            fake_registrar.chmod(0o755)
            install_home = (temporary / "signed-install-home").resolve()
            install_environment = environment.copy()
            install_environment["HOME"] = str(install_home)
            install_environment["METASEQUOIA_REGISTER_INPUT_SOURCE_COMMAND"] = str(fake_registrar)
            install_result = subprocess.run(
                ["zsh", package_root / "Install.command"],
                capture_output=True,
                text=True,
                env=install_environment,
            )
            self.assertEqual(install_result.returncode, 0, install_result.stderr)
            self.assertNotIn("Type I UNDERSTAND", install_result.stdout)
            gatekeeper_calls = [
                line for line in signing_log.read_text().splitlines() if line.startswith("spctl --assess --type execute ")
            ]
            self.assertEqual(len(gatekeeper_calls), 3)
            self.assertTrue(any("/signed-extracted/" in line for line in gatekeeper_calls))
            self.assertTrue(any("/.MetasequoiaIME.installing." in line for line in gatekeeper_calls))
            self.assertTrue(any("/signed-install-home/" in line for line in gatekeeper_calls))
            self.assertTrue(
                (install_home / "Library/Input Methods/MetasequoiaIME.app/Contents/Info.plist").is_file()
            )

    def test_package_is_portable_and_self_contained(self):
        bundle = Path(sys.argv[1]).resolve()
        version = subprocess.run(["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleShortVersionString", bundle / "Contents/Info.plist"], check=True, capture_output=True, text=True).stdout.strip()
        dictionary = bundle / "Contents/Resources/msime.db"
        with (bundle / "Contents/Info.plist").open("rb") as info_file:
            bundle_info = plistlib.load(info_file)
            dictionary_fingerprint = bundle_info["MetasequoiaDictionarySHA256"]
        self.assertTrue(dictionary.is_file())
        self.assertEqual(dictionary_fingerprint, sha256_file(dictionary))

        bundled_uninstaller = bundle / "Contents/Resources/Uninstall.command"
        self.assertTrue(bundled_uninstaller.is_file())
        self.assertTrue(os.access(bundled_uninstaller, os.X_OK))
        self.assertEqual(bundled_uninstaller.read_bytes(), (MACOS_ROOT / "scripts/uninstall.sh").read_bytes())

        app_icon_name = "MetasequoiaIME.icns"
        menu_icon_name = "MetasequoiaIMEMenuIcon.tiff"
        input_mode = bundle_info["ComponentInputModeDict"]["tsInputModeListKey"][
            "com.houko.inputmethod.MetasequoiaIME.Hans"
        ]
        self.assertEqual(bundle_info["CFBundleIconFile"], app_icon_name)
        self.assertEqual(bundle_info["tsInputMethodIconFileKey"], menu_icon_name)
        self.assertEqual(input_mode["tsInputModeMenuIconFileKey"], menu_icon_name)
        self.assertEqual(input_mode["tsInputModePaletteIconFileKey"], menu_icon_name)
        app_icon = bundle / "Contents/Resources" / app_icon_name
        self.assertTrue(app_icon.is_file())
        with tempfile.TemporaryDirectory() as icon_directory:
            iconset = Path(icon_directory) / "MetasequoiaIME.iconset"
            subprocess.run(
                ["iconutil", "--convert", "iconset", "--output", iconset, app_icon],
                check=True,
            )
            self.assertTrue((iconset / "icon_16x16.png").is_file())
            self.assertTrue((iconset / "icon_128x128@2x.png").is_file())
        menu_icon = bundle / "Contents/Resources" / menu_icon_name
        self.assertTrue(menu_icon.is_file())
        helpcode_directory = bundle / "Contents/Resources/helpcodes"
        self.assertEqual(
            {path.name for path in helpcode_directory.iterdir() if path.is_file()},
            {
                "helpcode.txt",
                "zrm_helpcode_big_unique.txt",
                "shouyou2_0_helpcode.txt",
                "shouyouplus_helpcode.txt",
                "xiaohe_helpcode.txt",
            },
        )
        for helpcode_table in helpcode_directory.iterdir():
            if helpcode_table.is_file():
                self.assertGreater(helpcode_table.stat().st_size, 0)
        menu_icon_properties = subprocess.run(
            [
                "sips",
                "-g",
                "pixelWidth",
                "-g",
                "pixelHeight",
                "-g",
                "hasAlpha",
                "-g",
                "dpiWidth",
                "-g",
                "dpiHeight",
                menu_icon,
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertIn("pixelWidth: 32", menu_icon_properties)
        self.assertIn("pixelHeight: 36", menu_icon_properties)
        self.assertIn("hasAlpha: no", menu_icon_properties)
        self.assertIn("dpiWidth: 144", menu_icon_properties)
        self.assertIn("dpiHeight: 144", menu_icon_properties)

        executable = bundle / "Contents/MacOS/MetasequoiaIME"
        for architecture in ("arm64", "x86_64"):
            dependencies = subprocess.run(
                ["otool", "-arch", architecture, "-L", executable],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.splitlines()[1:]
            for dependency in dependencies:
                library = dependency.strip().split(" (", 1)[0]
                self.assertTrue(
                    library.startswith(("/System/Library/", "/usr/lib/", "@")),
                    f"{architecture} has a non-portable dependency: {library}",
                )

            build_version = subprocess.run(
                ["vtool", "-arch", architecture, "-show-build", executable],
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            self.assertRegex(build_version, r"(?m)^\s*minos 12\.0$")

        with tempfile.TemporaryDirectory() as temporary_directory:
            output = Path(temporary_directory) / "output"
            environment = os.environ.copy()
            for variable in SIGNING_ENVIRONMENT:
                environment.pop(variable, None)
            environment["METASEQUOIA_RELEASE_ASSET_SUFFIX"] = "-unsigned"
            trusted_packager = Path(temporary_directory) / "package-release.sh"
            shutil.copy2(MACOS_ROOT / "scripts/package_release.sh", trusted_packager)
            environment["METASEQUOIA_PROJECT_ROOT"] = str(PROJECT_ROOT)
            environment["METASEQUOIA_RELEASE_INSTALL_SCRIPT"] = str(
                MACOS_ROOT / "scripts/install-release.sh"
            )
            environment["METASEQUOIA_RELEASE_SETTINGS_SCRIPT"] = str(
                MACOS_ROOT / "scripts/open-settings.sh"
            )
            subprocess.run(
                [trusted_packager, f"v{version}", bundle, output],
                check=True,
                env=environment,
            )
            archive = output / f"MetasequoiaIME-v{version}-macos-universal-unsigned.zip"
            update_archive = output / f"MetasequoiaIME-v{version}-macos-universal-unsigned-update.zip"
            checksum = archive.with_suffix(f"{archive.suffix}.sha256")
            digest, filename = checksum.read_text().split()
            actual_digest = hashlib.sha256()
            with archive.open("rb") as archive_file:
                for chunk in iter(lambda: archive_file.read(1024 * 1024), b""):
                    actual_digest.update(chunk)

            self.assertEqual(filename, archive.name)
            self.assertEqual(digest, actual_digest.hexdigest())

            update_checksum = update_archive.with_suffix(f"{update_archive.suffix}.sha256")
            update_digest, update_filename = update_checksum.read_text().split()
            self.assertEqual(update_filename, update_archive.name)
            self.assertEqual(update_digest, hashlib.sha256(update_archive.read_bytes()).hexdigest())
            with zipfile.ZipFile(update_archive) as update_zip:
                update_names = update_zip.namelist()
                self.assertIn("MetasequoiaIME.app/Contents/Info.plist", update_names)
                update_info = plistlib.loads(update_zip.read("MetasequoiaIME.app/Contents/Info.plist"))
                self.assertTrue(
                    update_info["SUEnableAutomaticChecks"],
                    "Unsigned releases publish a signed appcast, so they must keep checking it.",
                )
                self.assertIn(
                    "MetasequoiaIME.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
                    update_names,
                )
                self.assertIn(
                    "MetasequoiaIME.app/Contents/Resources/Licenses/Sparkle-LICENSE.txt",
                    update_names,
                )
                self.assertFalse(any(name.endswith("Install.command") for name in update_names))
                self.assertFalse(any(name.endswith("UNSIGNED_BUILD.txt") for name in update_names))

            with zipfile.ZipFile(archive) as release_zip:
                names = release_zip.namelist()
                package_root = f"MetasequoiaIME-v{version}/"
                self.assertIn(f"{package_root}MetasequoiaIME.app/Contents/Info.plist", names)
                self.assertIn(
                    f"{package_root}MetasequoiaIME.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle",
                    names,
                )
                self.assertIn(f"{package_root}Install.command", names)
                self.assertIn(f"{package_root}Open Settings.command", names)
                self.assertIn(f"{package_root}Uninstall.command", names)
                self.assertIn(f"{package_root}UNSIGNED_BUILD.txt", names)
                self.assertIn(f"{package_root}LICENSE", names)
                self.assertIn(f"{package_root}THIRD_PARTY_NOTICES.txt", names)
                self.assertIn(
                    f"{package_root}MetasequoiaIME.app/Contents/Resources/Licenses/GPL-3.0.txt", names
                )
                self.assertIn(
                    f"{package_root}MetasequoiaIME.app/Contents/Resources/Licenses/THIRD_PARTY_NOTICES.txt", names
                )
                self.assertFalse(any(name.endswith("register_input_source.swift") for name in names))
                install_command = release_zip.read(f"{package_root}Install.command").decode()
                settings_command = release_zip.read(f"{package_root}Open Settings.command").decode()
                uninstall_command = release_zip.read(f"{package_root}Uninstall.command").decode()
                self.assertIn("spctl --assess --type execute", install_command)
                self.assertIn("Type I UNDERSTAND", install_command)
                self.assertIn("Contents/MacOS/MetasequoiaIME", install_command)
                self.assertIn("--register-input-source", install_command)
                self.assertNotIn("xattr", install_command)
                self.assertIn("--show-settings", settings_command)
                self.assertIn("Library/Input Methods/MetasequoiaIME.app", settings_command)
                self.assertIn("Type REMOVE METASEQUOIAIME", uninstall_command)
                self.assertIn("--remove-user-data", uninstall_command)
                self.assertNotIn("rm -rf", uninstall_command)

                extracted = Path(temporary_directory) / "extracted"
                subprocess.run(["ditto", "-x", "-k", archive, extracted], check=True)
                fake_bin = Path(temporary_directory) / "bin"
                fake_bin.mkdir()
                fake_pkill = fake_bin / "pkill"
                fake_pkill.write_text("#!/bin/sh\nexit 0\n")
                fake_pkill.chmod(0o755)
                fake_pgrep = fake_bin / "pgrep"
                fake_pgrep.write_text("#!/bin/sh\nexit 1\n")
                fake_pgrep.chmod(0o755)
                registration_log = Path(temporary_directory) / "registration.log"
                fake_registrar = fake_bin / "register-input-source"
                fake_registrar.write_text(
                    "#!/bin/sh\n"
                    "printf '%s\\n' \"$*\" >> \"$FAKE_REGISTRATION_LOG\"\n"
                    "exit \"${FAKE_REGISTRATION_STATUS:-0}\"\n"
                )
                fake_registrar.chmod(0o755)

                missing_settings_home = (Path(temporary_directory) / "missing-settings-home").resolve()
                missing_settings_environment = os.environ.copy()
                missing_settings_environment["HOME"] = str(missing_settings_home)
                missing_settings = subprocess.run(
                    ["zsh", extracted / package_root / "Open Settings.command"],
                    capture_output=True,
                    text=True,
                    env=missing_settings_environment,
                )
                self.assertNotEqual(missing_settings.returncode, 0)
                self.assertIn("is not installed", missing_settings.stderr)

                settings_home = (Path(temporary_directory) / "settings-home").resolve()
                settings_executable = settings_home / "Library/Input Methods/MetasequoiaIME.app/Contents/MacOS/MetasequoiaIME"
                settings_executable.parent.mkdir(parents=True)
                settings_log = Path(temporary_directory) / "settings.log"
                settings_executable.write_text(
                    "#!/bin/sh\n"
                    "printf '%s\\n' \"$*\" > \"$SETTINGS_LAUNCH_LOG\"\n"
                )
                settings_executable.chmod(0o755)
                settings_environment = os.environ.copy()
                settings_environment["HOME"] = str(settings_home)
                settings_environment["SETTINGS_LAUNCH_LOG"] = str(settings_log)
                opened_settings = subprocess.run(
                    ["zsh", extracted / package_root / "Open Settings.command"],
                    capture_output=True,
                    text=True,
                    env=settings_environment,
                )
                self.assertEqual(opened_settings.returncode, 0, opened_settings.stderr)
                self.assertEqual(settings_log.read_text(), "--show-settings\n")

                test_home = (Path(temporary_directory) / "home").resolve()
                install_environment = os.environ.copy()
                install_environment["HOME"] = str(test_home)
                install_environment["PATH"] = f"{fake_bin}:{install_environment['PATH']}"
                install_environment["FAKE_REGISTRATION_LOG"] = str(registration_log)
                install_environment["METASEQUOIA_REGISTER_INPUT_SOURCE_COMMAND"] = str(fake_registrar)
                rejected_install = subprocess.run(
                    ["zsh", extracted / package_root / "Install.command"],
                    input="no\n",
                    capture_output=True,
                    text=True,
                    env=install_environment,
                )
                self.assertNotEqual(rejected_install.returncode, 0)
                self.assertIn("Unsigned installation cancelled", rejected_install.stderr)
                self.assertFalse((test_home / "Library/Input Methods/MetasequoiaIME.app").exists())
                install_result = subprocess.run(
                    ["zsh", extracted / package_root / "Install.command"],
                    input="I UNDERSTAND\n",
                    capture_output=True,
                    text=True,
                    env=install_environment,
                )
                self.assertEqual(install_result.returncode, 0, install_result.stderr)
                self.assertIn("not Developer ID signed or notarized", install_result.stderr)
                self.assertTrue(
                    (test_home / "Library/Input Methods/MetasequoiaIME.app/Contents/Info.plist").is_file()
                )
                self.assertIn("--register-input-source", registration_log.read_text())
                packaged_uninstall = subprocess.run(
                    ["zsh", extracted / package_root / "Uninstall.command"],
                    input="REMOVE METASEQUOIAIME\n",
                    capture_output=True,
                    text=True,
                    env=install_environment,
                )
                self.assertEqual(packaged_uninstall.returncode, 0, packaged_uninstall.stderr)
                self.assertFalse((test_home / "Library/Input Methods/MetasequoiaIME.app").exists())
                self.assertEqual(len(list((test_home / ".Trash").glob("MetasequoiaIME-uninstall.*"))), 1)

                registration_failure_home = (Path(temporary_directory) / "registration-failure-home").resolve()
                registration_failure_destination = (
                    registration_failure_home / "Library/Input Methods/MetasequoiaIME.app"
                )
                registration_failure_marker = (
                    registration_failure_destination / "Contents/previous-installation.txt"
                )
                registration_failure_marker.parent.mkdir(parents=True)
                registration_failure_marker.write_text("previous installation\n")
                registration_failure_environment = install_environment.copy()
                registration_failure_environment["HOME"] = str(registration_failure_home)
                registration_failure_environment["FAKE_REGISTRATION_STATUS"] = "54"
                failed_registration = subprocess.run(
                    ["zsh", extracted / package_root / "Install.command"],
                    input="I UNDERSTAND\n",
                    capture_output=True,
                    text=True,
                    env=registration_failure_environment,
                )
                self.assertNotEqual(failed_registration.returncode, 0)
                self.assertFalse(registration_failure_marker.exists())
                self.assertTrue(
                    (registration_failure_destination / "Contents/Info.plist").is_file()
                )
                self.assertFalse(
                    any(registration_failure_destination.parent.glob(".MetasequoiaIME.installing.*"))
                )
                self.assertFalse(
                    any(registration_failure_destination.parent.glob(".MetasequoiaIME.backup.*"))
                )
                self.assertIn("registration or enable failed", failed_registration.stderr)
                self.assertIn("remains installed", failed_registration.stderr)
                self.assertIn("enable it manually", failed_registration.stderr)

                fake_codesign = fake_bin / "codesign"
                fake_codesign.write_text(
                    "#!/bin/sh\n"
                    "target=\n"
                    "for argument in \"$@\"; do target=$argument; done\n"
                    "if test -n \"${FAIL_CODESIGN_PATH:-}\" && test \"$target\" = \"$FAIL_CODESIGN_PATH\"; then\n"
                    "  exit 45\n"
                    "fi\n"
                    "exec /usr/bin/codesign \"$@\"\n"
                )
                fake_codesign.chmod(0o755)
                fake_mv = fake_bin / "mv"
                fake_mv.write_text(
                    "#!/bin/sh\n"
                    "source_path=\n"
                    "for argument in \"$@\"; do\n"
                    "  case $argument in -*) ;; *) source_path=$argument; break ;; esac\n"
                    "done\n"
                    "if test \"${INTERRUPT_AFTER_MOVE:-false}\" = true && "
                    "test \"$source_path\" = \"$INTERRUPT_MOVE_SOURCE\"; then\n"
                    "  /bin/mv \"$@\"\n"
                    "  kill -TERM \"$PPID\"\n"
                    "  exit 0\n"
                    "fi\n"
                    "case $source_path in\n"
                    "  */.MetasequoiaIME.backup.*/MetasequoiaIME.app)\n"
                    "    test \"${FAIL_ROLLBACK:-false}\" != true || exit 46\n"
                    "    ;;\n"
                    "esac\n"
                    "exec /bin/mv \"$@\"\n"
                )
                fake_mv.chmod(0o755)

                interrupted_home = (Path(temporary_directory) / "interrupted-home").resolve()
                interrupted_destination = interrupted_home / "Library/Input Methods/MetasequoiaIME.app"
                interrupted_marker = interrupted_destination / "Contents/previous-installation.txt"
                interrupted_marker.parent.mkdir(parents=True)
                interrupted_marker.write_text("previous installation\n")
                interrupted_environment = install_environment.copy()
                interrupted_environment["HOME"] = str(interrupted_home)
                interrupted_environment["INTERRUPT_AFTER_MOVE"] = "true"
                interrupted_environment["INTERRUPT_MOVE_SOURCE"] = str(interrupted_destination)
                interrupted_install = subprocess.run(
                    ["zsh", extracted / package_root / "Install.command"],
                    input="I UNDERSTAND\n",
                    capture_output=True,
                    text=True,
                    env=interrupted_environment,
                )
                self.assertNotEqual(interrupted_install.returncode, 0)
                self.assertEqual(interrupted_marker.read_text(), "previous installation\n")
                self.assertFalse(any(interrupted_destination.parent.glob(".MetasequoiaIME.installing.*")))
                self.assertFalse(any(interrupted_destination.parent.glob(".MetasequoiaIME.backup.*")))

                restored_home = (Path(temporary_directory) / "restored-home").resolve()
                restored_destination = restored_home / "Library/Input Methods/MetasequoiaIME.app"
                restored_marker = restored_destination / "Contents/previous-installation.txt"
                restored_marker.parent.mkdir(parents=True)
                restored_marker.write_text("previous installation\n")
                restored_environment = install_environment.copy()
                restored_environment["HOME"] = str(restored_home)
                restored_environment["FAIL_CODESIGN_PATH"] = str(restored_destination)
                failed_install = subprocess.run(
                    ["zsh", extracted / package_root / "Install.command"],
                    input="I UNDERSTAND\n",
                    capture_output=True,
                    text=True,
                    env=restored_environment,
                )
                self.assertNotEqual(failed_install.returncode, 0)
                self.assertEqual(restored_marker.read_text(), "previous installation\n")
                self.assertFalse(any(restored_destination.parent.glob(".MetasequoiaIME.installing.*")))
                self.assertFalse(any(restored_destination.parent.glob(".MetasequoiaIME.backup.*")))
                self.assertIn("restoring the previous installation", failed_install.stderr)

                rollback_home = (Path(temporary_directory) / "rollback-home").resolve()
                rollback_destination = rollback_home / "Library/Input Methods/MetasequoiaIME.app"
                previous_marker = rollback_destination / "Contents/previous-installation.txt"
                previous_marker.parent.mkdir(parents=True)
                previous_marker.write_text("previous installation\n")
                rollback_environment = install_environment.copy()
                rollback_environment["HOME"] = str(rollback_home)
                rollback_environment["FAIL_CODESIGN_PATH"] = str(rollback_destination)
                rollback_environment["FAIL_ROLLBACK"] = "true"
                failed_rollback = subprocess.run(
                    ["zsh", extracted / package_root / "Install.command"],
                    input="I UNDERSTAND\n",
                    capture_output=True,
                    text=True,
                    env=rollback_environment,
                )
                self.assertNotEqual(failed_rollback.returncode, 0)
                preserved_backups = list(
                    rollback_destination.parent.glob(".MetasequoiaIME.backup.*/MetasequoiaIME.app")
                )
                self.assertEqual(len(preserved_backups), 1)
                self.assertEqual(
                    (preserved_backups[0] / "Contents/previous-installation.txt").read_text(),
                    "previous installation\n",
                )
                self.assertIn("Previous installation is preserved at", failed_rollback.stderr)

            installer_package = output / f"MetasequoiaIME-v{version}-macos-universal-unsigned.pkg"
            installer_checksum = installer_package.with_suffix(f"{installer_package.suffix}.sha256")
            self.assertTrue(installer_package.is_file())
            self.assertTrue(installer_checksum.is_file())
            installer_digest, installer_filename = installer_checksum.read_text().split()
            actual_installer_digest = hashlib.sha256()
            with installer_package.open("rb") as installer_file:
                for chunk in iter(lambda: installer_file.read(1024 * 1024), b""):
                    actual_installer_digest.update(chunk)

            self.assertEqual(installer_filename, installer_package.name)
            self.assertEqual(installer_digest, actual_installer_digest.hexdigest())

            domain_info = subprocess.run(["installer", "-pkg", installer_package, "-target", "CurrentUserHomeDirectory", "-dominfo", "-verbose"], check=True, capture_output=True, text=True).stdout
            self.assertIn("CurrentUserHomeDirectory", domain_info)
            self.assertRegex(domain_info, r"CurrentUserHomeDirectory[\s\S]*Status\s+: Enabled")
            self.assertRegex(domain_info, r"LocalSystem[\s\S]*Status\s+: Disabled")

            expanded_package = Path(temporary_directory) / "expanded-package"
            subprocess.run(["pkgutil", "--expand-full", installer_package, expanded_package], check=True)
            distribution = ElementTree.parse(expanded_package / "Distribution").getroot()
            domains = distribution.find("domains")
            self.assertIsNotNone(domains)
            self.assertEqual(domains.attrib["enable_currentUserHome"], "true")
            self.assertEqual(domains.attrib["enable_localSystem"], "false")
            self.assertEqual(distribution.find("license").attrib["file"], "LICENSE")
            self.assertEqual(distribution.find("readme").attrib["file"], "InstallerReadMe.txt")
            package_reference = next(
                reference
                for reference in distribution.findall("pkg-ref")
                if reference.attrib.get("id") == "com.houko.inputmethod.MetasequoiaIME.pkg"
                and reference.text
            )
            self.assertNotIn("onConclusion", package_reference.attrib)
            installer_readme = (expanded_package / "Resources/InstallerReadMe.txt").read_text()
            self.assertIn("UNSIGNED TEST BUILD", installer_readme)
            self.assertIn("not Developer ID signed or notarized", installer_readme)
            self.assertIn("verify the downloaded .pkg SHA-256 checksum", installer_readme)
            self.assertIn("Third-party notices", installer_readme)
            self.assertIn("MetasequoiaImeEngine", installer_readme)
            self.assertIn("Contents/Resources/Uninstall.command", installer_readme)
            self.assertIn("may request administrator authorization", installer_readme)
            self.assertIn("attempts to register and enable 水杉", installer_readme)
            self.assertIn("will not log out or restart the Mac automatically", installer_readme)

            component_info_path = next(expanded_package.glob("*.pkg/PackageInfo"))
            component_info = ElementTree.parse(component_info_path).getroot()
            self.assertEqual(component_info.attrib["identifier"], "com.houko.inputmethod.MetasequoiaIME.pkg")
            self.assertEqual(component_info.attrib["version"], version)
            self.assertEqual(component_info.attrib["install-location"], "Library/Input Methods")
            self.assertEqual(component_info.attrib["relocatable"], "false")
            self.assertEqual(component_info.attrib["auth"], "root")
            upgrade_bundle = component_info.find("upgrade-bundle/bundle")
            self.assertIsNotNone(upgrade_bundle)
            self.assertEqual(upgrade_bundle.attrib["id"], "com.houko.inputmethod.MetasequoiaIME")
            self.assertTrue((component_info_path.parent / "Payload/MetasequoiaIME.app/Contents/Info.plist").is_file())
            packaged_uninstaller = (
                component_info_path.parent / "Payload/MetasequoiaIME.app/Contents/Resources/Uninstall.command"
            )
            self.assertTrue(packaged_uninstaller.is_file())
            self.assertTrue(os.access(packaged_uninstaller, os.X_OK))
            pkg_postinstall = component_info_path.parent / "Scripts/postinstall"
            self.assertTrue(pkg_postinstall.is_file())
            self.assertTrue(os.access(pkg_postinstall, os.X_OK))
            postinstall_source = pkg_postinstall.read_text()
            self.assertIn("launchctl asuser", postinstall_source)
            self.assertIn("--register-input-source", postinstall_source)
            self.assertIn("input source registration will be deferred", postinstall_source)
            self.assertTrue(
                (
                    component_info_path.parent
                    / "Payload/MetasequoiaIME.app/Contents/Resources/Licenses/GPL-3.0.txt"
                ).is_file()
            )

            asset_names = (
                f"MetasequoiaIME-v{version}-macos-universal-unsigned.zip",
                f"MetasequoiaIME-v{version}-macos-universal-unsigned.zip.sha256",
                f"MetasequoiaIME-v{version}-macos-universal-unsigned-update.zip",
                f"MetasequoiaIME-v{version}-macos-universal-unsigned-update.zip.sha256",
                f"MetasequoiaIME-v{version}-macos-universal-unsigned.pkg",
                f"MetasequoiaIME-v{version}-macos-universal-unsigned.pkg.sha256",
            )

            cleanup_failure_output = Path(temporary_directory) / "cleanup-failure-output"
            cleanup_failure_output.mkdir()
            cleanup_failing_bin = Path(temporary_directory) / "cleanup-failing-bin"
            cleanup_failing_bin.mkdir()
            failing_rm = cleanup_failing_bin / "rm"
            failing_rm.write_text(
                "#!/bin/sh\n"
                "target=\n"
                "for argument in \"$@\"; do target=$argument; done\n"
                "case $target in\n"
                "  */.package.*) exit 44 ;;\n"
                "esac\n"
                "exec /bin/rm \"$@\"\n"
            )
            failing_rm.chmod(0o755)
            cleanup_failure_environment = environment.copy()
            cleanup_failure_environment["PATH"] = (
                f"{cleanup_failing_bin}:{cleanup_failure_environment['PATH']}"
            )
            failed_cleanup = subprocess.run(
                [trusted_packager, f"v{version}", bundle, cleanup_failure_output],
                capture_output=True,
                text=True,
                env=cleanup_failure_environment,
            )
            self.assertNotEqual(failed_cleanup.returncode, 0)
            for asset_name in asset_names:
                self.assertTrue(
                    (cleanup_failure_output / asset_name).is_file(),
                    f"Missing {asset_name}\nstdout:\n{failed_cleanup.stdout}\nstderr:\n{failed_cleanup.stderr}",
                )
            self.assertEqual(len(list(cleanup_failure_output.glob(".package.*"))), 1)
            self.assertIn("cleanup was incomplete", failed_cleanup.stderr)

            failure_output = Path(temporary_directory) / "failure-output"
            failure_output.mkdir()
            previous_contents = b"previous complete release asset\n"
            for asset_name in asset_names:
                (failure_output / asset_name).write_bytes(previous_contents)

            failing_bin = Path(temporary_directory) / "failing-bin"
            failing_bin.mkdir()
            failing_mv = failing_bin / "mv"
            failing_mv.write_text(
                "#!/bin/sh\n"
                "source_path=\n"
                "for argument in \"$@\"; do\n"
                "  case $argument in -*) ;; *) source_path=$argument; break ;; esac\n"
                "done\n"
                "case $source_path in\n"
                "  */PreviousAssets/*)\n"
                "    if test \"${FAIL_ROLLBACK:-false}\" = true && test ! -f \"$ROLLBACK_FAILURE_FILE\"; then\n"
                "      printf '%s\\n' failed > \"$ROLLBACK_FAILURE_FILE\"\n"
                "      exit 43\n"
                "    fi\n"
                "    ;;\n"
                "  */.package.*/MetasequoiaIME-v*-macos-universal*)\n"
                "    count=0\n"
                "    test ! -f \"$MV_COUNT_FILE\" || count=$(cat \"$MV_COUNT_FILE\")\n"
                "    count=$((count + 1))\n"
                "    printf '%s\\n' \"$count\" > \"$MV_COUNT_FILE\"\n"
                "    test \"$count\" -ne 2 || exit 42\n"
                "    ;;\n"
                "esac\n"
                "exec /bin/mv \"$@\"\n"
            )
            failing_mv.chmod(0o755)
            failure_environment = environment.copy()
            failure_environment["PATH"] = f"{failing_bin}:{failure_environment['PATH']}"
            failure_environment["MV_COUNT_FILE"] = str(Path(temporary_directory) / "mv-count")
            failed_package = subprocess.run(
                [trusted_packager, f"v{version}", bundle, failure_output],
                capture_output=True,
                text=True,
                env=failure_environment,
            )
            self.assertNotEqual(failed_package.returncode, 0)
            for asset_name in asset_names:
                self.assertEqual((failure_output / asset_name).read_bytes(), previous_contents)
            self.assertFalse(any(failure_output.glob(".package.*")))

            rollback_failure_output = Path(temporary_directory) / "rollback-failure-output"
            rollback_failure_output.mkdir()
            for asset_name in asset_names:
                (rollback_failure_output / asset_name).write_bytes(previous_contents)
            rollback_failure_environment = failure_environment.copy()
            rollback_failure_environment["MV_COUNT_FILE"] = str(
                Path(temporary_directory) / "rollback-mv-count"
            )
            rollback_failure_environment["FAIL_ROLLBACK"] = "true"
            rollback_failure_environment["ROLLBACK_FAILURE_FILE"] = str(
                Path(temporary_directory) / "rollback-failed"
            )
            failed_rollback = subprocess.run(
                [trusted_packager, f"v{version}", bundle, rollback_failure_output],
                capture_output=True,
                text=True,
                env=rollback_failure_environment,
            )
            self.assertNotEqual(failed_rollback.returncode, 0)
            preserved_staging = list(rollback_failure_output.glob(".package.*"))
            self.assertEqual(len(preserved_staging), 1)
            preserved_backup = preserved_staging[0] / "PreviousAssets"
            for asset_name in asset_names:
                final_asset = rollback_failure_output / asset_name
                backup_asset = preserved_backup / asset_name
                self.assertTrue(final_asset.exists() or backup_asset.exists())
                preserved_asset = final_asset if final_asset.exists() else backup_asset
                self.assertEqual(preserved_asset.read_bytes(), previous_contents)
            self.assertIn("PreviousAssets", failed_rollback.stderr)


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
