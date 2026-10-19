"""Android identity and selection are independent of Termux and installer execution."""

import unittest

import shutil

from helpers import PROJECT, SHELLS, SOURCE_CORE, SOURCE_MODULES, ShellTestCase


class PlatformTests(ShellTestCase):
    def test_android_detection_without_termux_and_guest_override(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
uname() { printf 'Linux\\n'; }
em_android_sdk() { printf '35\\n'; }
em_current_os
em_current_runtime
TERMUX_VERSION=example
PREFIX=/example/prefix
em_current_os
em_current_runtime
ENVMANAGER_OS=linux
em_current_os
em_current_runtime
''')
                self.assertEqual(result.stdout.splitlines(), [
                    "android", "system", "android", "termux", "linux", "system",
                ])

    def test_invalid_overrides_fail(self):
        for shell in SHELLS:
            for extra in ({"ENVMANAGER_OS": "unknown"},
                          {"ENVMANAGER_OS": "linux", "ENVMANAGER_RUNTIME": "termux"}):
                with self.subTest(shell=shell, override=extra):
                    result = self.shell(shell, SOURCE_MODULES + "\nem_current_runtime\n",
                                        check=False, extra_env=extra)
                    self.assertEqual(result.returncode, 2)

    def test_unsupported_wasi_architecture_is_not_suggested(self):
        (self.repo / "99-wasi.sh").write_text("return 91\n")
        for shell in SHELLS:
            for os_name, arch in (("macos", "x86_64"), ("linux", "aarch64")):
                with self.subTest(shell=shell, os=os_name, arch=arch):
                    result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
em_available_script_names
em_script_unsupported_reason "$ENVMANAGER_DIR/99-wasi.sh"
''', extra_env={"ENVMANAGER_OS": os_name, "ENVMANAGER_ARCH": arch})
                    self.assertEqual(result.stdout, "requires Linux x86_64 binaries\n")

    def test_android_qualifiers_and_local_variants(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
for file in 90-tool.android.sh 90-tool.android.termux.sh 90-tool.android.system.local.sh; do
  em_script_name "$file"
  em_script_os "$file"
  em_script_runtime "$file"
  printf '%s\\n' ---
done
''')
                self.assertEqual(result.stdout, "tool\nandroid\n---\ntool\nandroid\ntermux\n---\ntool\nandroid\nsystem\n---\n")

    def test_runtime_filtering_loads_into_calling_shell(self):
        for name in ("01-tool.android.sh", "02-tool.android.termux.sh",
                     "03-tool.android.system.sh", "04-tool.linux.sh"):
            (self.repo / name).write_text(f"printf '%s\\n' '{name}' >> \"$TEST_LOG\"\nexport EM_ANDROID_LOADED=yes\n")
        for shell in SHELLS:
            for runtime in ("termux", "system"):
                with self.subTest(shell=shell, runtime=runtime):
                    if self.log.exists():
                        self.log.unlink()
                    result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
printf '%s\\n' "$EM_ANDROID_LOADED"
em_available_script_names
''', extra_env={"ENVMANAGER_OS": "android", "ENVMANAGER_RUNTIME": runtime})
                    self.assertEqual(result.stdout, "yes\ntool\n")
                    self.assertEqual(self.log.read_text().splitlines(), [
                        "01-tool.android.sh", f"0{2 if runtime == 'termux' else 3}-tool.android.{runtime}.sh",
                    ])

    def test_android_skips_desktop_installers_and_reports_why(self):
        for name in ("90-python.sh", "99-nvm.sh", "99-wasi.sh", "99-sdkman.sh"):
            (self.repo / name).write_text("return 91\n")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
em_available_script_names
em_script_unsupported_reason "$ENVMANAGER_DIR/99-nvm.sh"
''', extra_env={"ENVMANAGER_OS": "android", "ENVMANAGER_RUNTIME": "termux"})
                self.assertIn("desktop", result.stdout)
                self.assertNotIn("\nnvm\n", "\n" + result.stdout)

    def test_supported_script_failure_stops_loading_and_reaches_caller(self):
        (self.repo / "01-fail.android.sh").write_text("return 7\n")
        (self.repo / "02-later.android.sh").write_text('printf unexpected > "$TEST_LOG"\n')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + "em_load_scripts\n", check=False,
                                    extra_env={"ENVMANAGER_OS": "android"})
                self.assertEqual(result.returncode, 7)
                self.assertFalse(self.log.exists())

    def test_android_temp_path_requires_writable_app_location(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE, check=False, extra_env={
                    "ENVMANAGER_OS": "android", "HOME": "", "TMPDIR": "",
                })
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("TMPDIR", result.stderr)

    def test_android_loader_and_providers_do_not_install_or_update(self):
        for script in PROJECT.glob("*.sh"):
            if script.name != "00-core.sh":
                shutil.copy2(script, self.repo)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, '''
git() { printf 'unexpected Git operation\\n' >&2; exit 91; }
curl() { printf 'unexpected download\\n' >&2; exit 92; }
wget() { printf 'unexpected download\\n' >&2; exit 92; }
. "$ENVMANAGER_DIR/envmanagerrc" || exit 10
printf '%s\\n' "$UV_PYTHON_DOWNLOADS" "$TMUX_TMPDIR" "$PNPM_HOME"
em_script_supported "$ENVMANAGER_DIR/99-nvm.sh" && exit 11
em_script_supported "$ENVMANAGER_DIR/99-sdkman.sh" && exit 12
exit 0
''', extra_env={"ENVMANAGER_OS": "android", "ENVMANAGER_RUNTIME": "termux"})
                self.assertEqual(result.stdout.splitlines(), [
                    "never", str(self.root / "tmp/tmux"), str(self.home / ".local/share/pnpm"),
                ])

    def test_termux_reuses_existing_tools_and_preserves_preferences(self):
        for name in ("99-java.android.termux.sh", "99-pnpm.android.termux.sh",
                     "99-default-browser.android.termux.sh"):
            shutil.copy2(PROJECT / name, self.repo)
        prefix = self.root / "app prefix"
        java = prefix / "lib/jvm/installed-jdk/bin/java"
        pnpm = self.root / "pnpm home/bin/pnpm"
        for binary in (java, pnpm):
            binary.parent.mkdir(parents=True)
            binary.write_text("#!/bin/sh\nexit 91\n")
            binary.chmod(0o700)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
termux-open-url() { exit 92; }
em_load_scripts
printf '%s\\n' "$JAVA_HOME" "$BROWSER"
case ":$PATH:" in *":$PNPM_HOME/bin:"*) ;; *) exit 10 ;; esac
JAVA_HOME=preferred-jdk
BROWSER=preferred-browser
em_load_scripts
printf '%s\\n' "$JAVA_HOME" "$BROWSER"
''', extra_env={"ENVMANAGER_OS": "android", "ENVMANAGER_RUNTIME": "termux",
                "PREFIX": str(prefix), "PNPM_HOME": str(pnpm.parent.parent)})
                self.assertEqual(result.stdout.splitlines(), [
                    str(java.parent.parent), "termux-open-url", "preferred-jdk", "preferred-browser",
                ])

    def test_android_completions_match_runtime_and_user_choices(self):
        if "zsh" not in SHELLS:
            self.skipTest("Zsh is not installed")
        for filename in ("90-python.sh", "90-python.android.termux.sh", "99-nvm.sh",
                         "99-device.android.system.sh", "01-gpg.linux.sh"):
            (self.repo / filename).write_text("return 91\n")
        for runtime, expected in (("termux", "python"), ("system", "device")):
            with self.subTest(runtime=runtime):
                result = self.shell("zsh", SOURCE_CORE + '''
autoload -Uz compinit; compinit -D -i
em_register_completions
compadd() { printf '%s\\n' "${names[@]}"; }
_em_disable
em_disable python device nvm gpg
printf '%s\\n' ---
_em_enable
em_enable gpg nvm
''', extra_env={"ENVMANAGER_OS": "android", "ENVMANAGER_RUNTIME": runtime,
                "ENVMANAGER_DISABLED_FILE": str(self.root / f"{runtime}-disabled")})
                self.assertEqual(result.stdout, f"{expected}\n---\n{expected}\n")


if __name__ == "__main__":
    unittest.main()
