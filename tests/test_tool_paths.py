"""Production providers must keep existing tool homes and explicit preferences."""

import shutil
import unittest

from helpers import PROJECT, SHELLS, SOURCE_CORE, ShellTestCase


CONFIGURATIONS = (
    ("99-codex.sh", "CODEX_HOME", ".codex", ".local/share/codex"),
    ("99-gradle.sh", "GRADLE_USER_HOME", ".gradle", ".local/share/gradle"),
    ("99-keras.sh", "KERAS_HOME", ".keras", ".local/state/keras"),
    ("99-rust.sh", "CARGO_HOME", ".cargo", ".local/share/cargo"),
    ("99-npm.sh", "NPM_CONFIG_USERCONFIG", ".npmrc", ".config/npm/npmrc"),
)
PRINT_PATHS = "\n".join(f'printf "%s\\n" "${variable}"'
                        for _, variable, _, _ in CONFIGURATIONS)


class ToolPathTests(ShellTestCase):
    def copy_configurations(self):
        for filename, _, _, _ in CONFIGURATIONS:
            shutil.copy2(PROJECT / filename, self.repo)

    def make_path(self, relative):
        path = self.home / relative
        if path.name in (".npmrc", "npmrc"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("existing npm configuration\n")
        else:
            path.mkdir(parents=True, exist_ok=True)
        return path

    def test_existing_conventional_homes_are_reused_across_platforms(self):
        self.copy_configurations()
        expected = [str(self.make_path(native)) for _, _, native, _ in CONFIGURATIONS]
        for shell in SHELLS:
            for os_name in ("linux", "macos", "freebsd", "openbsd", "netbsd", "windows", "android"):
                with self.subTest(shell=shell, os=os_name):
                    result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
''' + PRINT_PATHS + '''
printf '%s\\n' "$CODEX_SQLITE_HOME"
''', extra_env={"ENVMANAGER_OS": os_name})
                    self.assertEqual(result.stdout.splitlines(), expected + [expected[0]])
                    for _, _, _, xdg in CONFIGURATIONS:
                        self.assertFalse((self.home / xdg).exists())

    def test_existing_xdg_paths_keep_precedence_and_split_codex_state(self):
        self.copy_configurations()
        for _, _, native, _ in CONFIGURATIONS:
            self.make_path(native)
        expected = [str(self.make_path(xdg)) for _, _, _, xdg in CONFIGURATIONS]
        state = self.make_path(".local/state/codex")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
''' + PRINT_PATHS + '''
printf '%s\\n' "$CODEX_SQLITE_HOME"
''')
                self.assertEqual(result.stdout.splitlines(), expected + [str(state)])

    def test_native_codex_does_not_pick_up_an_unrelated_xdg_state_directory(self):
        shutil.copy2(PROJECT / "99-codex.sh", self.repo)
        native = self.make_path(".codex")
        self.make_path(".local/state/codex")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
printf '%s\\n' "$CODEX_HOME" "$CODEX_SQLITE_HOME"
''')
                self.assertEqual(result.stdout.splitlines(), [str(native)] * 2)

    def test_xdg_codex_with_embedded_state_keeps_it_in_the_home(self):
        shutil.copy2(PROJECT / "99-codex.sh", self.repo)
        home = self.make_path(".local/share/codex")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
printf '%s\\n' "$CODEX_SQLITE_HOME"
''')
                self.assertEqual(result.stdout, str(home) + "\n")

    def test_explicit_paths_and_new_installation_defaults(self):
        self.copy_configurations()
        for shell in SHELLS:
            for explicit in (False, True):
                with self.subTest(shell=shell, explicit=explicit):
                    overrides = {variable: str(self.home / "custom" / variable)
                                 for _, variable, _, _ in CONFIGURATIONS} if explicit else {}
                    if explicit:
                        overrides["CODEX_SQLITE_HOME"] = str(self.home / "custom state")
                    expected = [overrides.get(variable, str(self.home / xdg))
                                for _, variable, _, xdg in CONFIGURATIONS]
                    expected.append(overrides.get("CODEX_SQLITE_HOME", str(self.home / ".local/state/codex")))
                    result = self.shell(shell, SOURCE_CORE + '''
em_load_scripts || exit 10
''' + PRINT_PATHS + '''
printf '%s\\n' "$CODEX_SQLITE_HOME"
''', extra_env=overrides)
                    self.assertEqual(result.stdout.splitlines(), expected)

    def test_desktop_loaders_reuse_installed_native_nvm_and_pyenv(self):
        for filename in ("90-python.sh", "99-nvm.sh", "99-sdkman.sh"):
            shutil.copy2(PROJECT / filename, self.repo)
        nvm = self.make_path(".nvm")
        (nvm / "nvm.sh").write_text("return 0\n")
        pyenv = self.make_path(".pyenv/bin")
        sdkman = self.make_path(".sdkman")
        uv = self.home / ".local/bin/uv"
        uv.parent.mkdir(parents=True)
        uv.write_text("#!/bin/sh\nprintf 'uv fixture\\n'\n")
        uv.chmod(0o700)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
git() { printf 'unexpected Git operation\\n' >&2; exit 91; }
curl() { printf 'unexpected download\\n' >&2; exit 92; }
em_load_scripts || exit 10
printf '%s\\n' "$NVM_DIR" "$PYENV_ROOT" "$SDKMAN_DIR"
''', extra_env={"UV_VERSION": "fixture", "ENVMANAGER_OS": "linux"})
                self.assertEqual(result.stdout.splitlines(), [str(nvm), str(pyenv.parent), str(sdkman)])

    def test_installer_paths_preserve_explicit_locations_without_downloading(self):
        providers = (
            ("99-doppler.sh", "DOPPLER_INSTALL_DIR"),
            ("99-emsdk.sh", "EMSDK_DIR"),
            ("99-pnpm.sh", "PNPM_HOME"),
            ("99-sdkman.sh", "SDKMAN_DIR"),
            ("99-wasi.sh", "WASI_SDK_PATH"),
        )
        overrides = {}
        for filename, variable in providers:
            shutil.copy2(PROJECT / filename, self.repo)
            overrides[variable] = str(self.make_path(f"custom providers/{variable}"))
        (self.home / "custom providers/DOPPLER_INSTALL_DIR/doppler").touch()
        pnpm = self.home / "custom providers/PNPM_HOME/bin/pnpm"
        pnpm.parent.mkdir()
        pnpm.write_text("#!/bin/sh\nexit 93\n")
        pnpm.chmod(0o700)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
em_run_every() { return 0; }
git() { printf 'unexpected Git operation\\n' >&2; exit 91; }
curl() { printf 'unexpected download\\n' >&2; exit 92; }
wget() { printf 'unexpected download\\n' >&2; exit 92; }
em_load_scripts || exit 10
''' + "\n".join(f'printf "%s\\n" "${variable}"' for _, variable in providers),
                                    extra_env=overrides | {"ENVMANAGER_OS": "linux", "ENVMANAGER_ARCH": "x86_64"})
                self.assertEqual(result.stdout.splitlines(), list(overrides.values()))


if __name__ == "__main__":
    unittest.main()
