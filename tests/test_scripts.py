"""Isolated Bash/Zsh checks; never load real installers or update repositories."""

import shutil
import subprocess
import unittest

from helpers import PROJECT, SHELLS, SOURCE_MODULES, ShellTestCase


class ScriptTests(ShellTestCase):
    def setUp(self):
        super().setUp()
        self.log = self.root / "loaded"
        self.environment["TEST_LOG"] = str(self.log)
        for name in (
            "00-before.sh", "01-generic.sh", "02-gpg.linux.sh",
            "03-apple.macos.sh", "04-alias.darwin.sh", "05-gpg.linux.local.sh",
            "06-bsd.freebsd.sh", "07-windows.windows.sh",
            "99-sdkman.sh", "99-sdkman.local.sh", "99-sdkman.linux.sh",
        ):
            # Sourceable scripts need not have an executable permission bit.
            (self.repo / name).write_text(f"printf '%s\\n' '{name}' >> \"$TEST_LOG\"\n")
        (self.repo / "nested").mkdir()
        (self.repo / "nested" / "nested.sh").write_text("return 77\n")
        (self.repo / "directory.sh").mkdir()
        (self.repo / "symlink.sh").symlink_to(self.repo / "01-generic.sh")

    def test_syntax(self):
        for shell in SHELLS:
            for path in list(PROJECT.glob("*.sh")) + list((PROJECT / "lib").glob("*.sh")):
                with self.subTest(shell=shell, path=path.name):
                    result = subprocess.run(
                        [shutil.which(shell), "-n", str(path)],
                        text=True, capture_output=True, env=self.environment,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_script_names_and_os_qualifiers(self):
        cases = (
            ("99-sdkman.sh", "sdkman", ""),
            ("/path with spaces/01-gpg.linux.local.sh", "gpg", "linux"),
            ("01-example.darwin.sh", "example", "macos"),
            ("01-example.macos.local.sh", "example", "macos"),
            ("12-tool-with-dashes.sh", "tool-with-dashes", ""),
            ("tool.local.sh", "tool", ""),
            ("prefix-tool.sh", "prefix-tool", ""),
        )
        for shell in SHELLS:
            for filename, name, os_name in cases:
                with self.subTest(shell=shell, filename=filename):
                    result = self.shell(shell, SOURCE_MODULES + '''
em_script_name "$FILENAME"
em_script_os "$FILENAME"
printf '|\n'
''', extra_env={"FILENAME": filename})
                    self.assertEqual(result.stdout, name + "\n" + (os_name + "\n" if os_name else "") + "|\n")

    def test_os_normalization(self):
        for shell in SHELLS:
            for observed, expected in (("Darwin", "macos"), ("Linux", "linux"),
                                       ("FreeBSD", "freebsd"), ("OpenBSD", "openbsd"),
                                       ("NetBSD", "netbsd"), ("CYGWIN_NT-10.0", "windows"),
                                       ("MSYS_NT-10.0", "windows"), ("MINGW64_NT-10.0", "windows")):
                with self.subTest(shell=shell, os=observed):
                    result = self.shell(shell, SOURCE_MODULES + '\nem_normalize_os "$OBSERVED"',
                                        extra_env={"OBSERVED": observed})
                    self.assertEqual(result.stdout, expected + "\n")

    def test_host_os_probe_failure_propagates(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
uname() { return 7; }
em_current_os
''', check=False)
                self.assertEqual(result.returncode, 7)

    def test_loading_changes_the_calling_shell(self):
        (self.repo / "08-shell-state.sh").write_text('''
export EM_LOADED_VALUE="exported by a script"
em_loaded_function() { printf 'function from a script\n'; }
''')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
em_load_scripts
printf '%s\n' "$EM_LOADED_VALUE"
em_loaded_function
sh -c 'printf "%s\\n" "$EM_LOADED_VALUE"'
''')
                self.assertEqual(result.stdout.splitlines(), [
                    "exported by a script", "function from a script", "exported by a script",
                ])

    def test_disable_persists_and_deduplicates(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                blacklist = self.root / f"{shell}-disabled"
                extra = {"ENVMANAGER_DISABLED_FILE": str(blacklist)}
                result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_disable sdkman gpg sdkman || exit 10
em_disable
''', extra_env=extra)
                self.assertEqual(result.stdout.splitlines(), ["gpg", "sdkman"])
                self.assertEqual(blacklist.read_text(), "gpg\nsdkman\n")
                self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_is_disabled sdkman && em_is_disabled gpg
''', extra_env=extra)
                self.assertEqual(list(self.root.glob(f"{shell}-disabled.*")), [])

    def test_invalid_names_do_not_change_blacklist(self):
        for shell in SHELLS:
            for name in ("missing", "core"):
                with self.subTest(shell=shell, name=name):
                    blacklist = self.repo / "disabled-scripts"
                    blacklist.write_text("sdkman\n")
                    result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_disable gpg "$INVALID_NAME"
''', check=False, extra_env={"INVALID_NAME": name})
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("unknown or protected script", result.stderr)
                    self.assertEqual(blacklist.read_text(), "sdkman\n")

    def test_enable_removes_only_requested_names_and_persists(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                blacklist = self.root / f"{shell}-disabled"
                blacklist.write_text("# local choices\ngpg\nsdkman\nsdkman\nsdkman-extra\n")
                extra = {"ENVMANAGER_DISABLED_FILE": str(blacklist)}
                result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_enable sdkman gpg sdkman || exit 10
em_enable
''', extra_env=extra)
                self.assertEqual(result.stdout, "sdkman-extra\n")
                self.assertEqual(blacklist.read_text(), "# local choices\nsdkman-extra\n")
                self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_is_disabled sdkman && exit 10
em_is_disabled gpg && exit 11
em_is_disabled sdkman-extra || exit 12
''', extra_env=extra)
                self.assertEqual(list(self.root.glob(f"{shell}-disabled.*")), [])

    def test_enable_is_idempotent_without_creating_blacklist(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                blacklist = self.root / f"{shell}-missing" / "disabled"
                extra = {"ENVMANAGER_DISABLED_FILE": str(blacklist)}
                self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_enable sdkman || exit 10
em_enable sdkman || exit 11
em_enable
''', extra_env=extra)
                self.assertFalse(blacklist.parent.exists())
                blacklist.parent.mkdir()
                blacklist.write_text("# local choices\nsdkman")
                self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_enable gpg
''', extra_env=extra)
                self.assertEqual(blacklist.read_text(), "# local choices\nsdkman")

    def test_enable_validates_entire_request_before_writing(self):
        for shell in SHELLS:
            for name in ("missing", "core"):
                with self.subTest(shell=shell, name=name):
                    blacklist = self.repo / "disabled-scripts"
                    blacklist.write_text("sdkman\n")
                    result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_enable sdkman "$INVALID_NAME"
''', check=False, extra_env={"INVALID_NAME": name})
                    self.assertEqual(result.returncode, 2)
                    self.assertIn("unknown or protected script", result.stderr)
                    self.assertEqual(blacklist.read_text(), "sdkman\n")

    def test_enable_removes_stale_names_with_relative_override(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                blacklist = self.root / "relative-disabled"
                blacklist.write_text("sdkman\nremoved-tool")
                self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_enable sdkman removed-tool
''', extra_env={"ENVMANAGER_DISABLED_FILE": "relative-disabled"})
                self.assertEqual(blacklist.read_text(), "")
                self.assertEqual(list(self.root.glob("relative-disabled.*")), [])

    def test_enable_takes_effect_on_next_load_without_running_scripts(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                if self.log.exists():
                    self.log.unlink()
                (self.repo / "disabled-scripts").write_text("sdkman\n")
                self.shell(shell, '''
uname() { printf 'Linux\\n'; }
source "$ENVMANAGER_DIR/00-core.sh"
em_load_scripts
em_enable sdkman
''')
                self.assertFalse(any("sdkman" in name for name in self.log.read_text().splitlines()))
                self.log.unlink()
                self.shell(shell, '''
uname() { printf 'Linux\\n'; }
source "$ENVMANAGER_DIR/00-core.sh"
em_load_scripts
''')
                loaded = {name for name in self.log.read_text().splitlines() if "sdkman" in name}
                self.assertEqual(loaded, {"99-sdkman.sh", "99-sdkman.local.sh", "99-sdkman.linux.sh"})

    def test_enable_reports_write_failures_without_losing_blacklist(self):
        for shell in SHELLS:
            for failing_command in ("mktemp", "mv"):
                with self.subTest(shell=shell, command=failing_command):
                    blacklist = self.root / f"{shell}-disabled"
                    blacklist.write_text("gpg\nsdkman\n")
                    result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
''' + f"{failing_command}() {{ return 7; }}\nem_enable sdkman\n",
                                        check=False, extra_env={"ENVMANAGER_DISABLED_FILE": str(blacklist)})
                    self.assertEqual(result.returncode, 7 if failing_command == "mktemp" else 1)
                    self.assertEqual(blacklist.read_text(), "gpg\nsdkman\n")
                    self.assertEqual(list(self.root.glob(f"{shell}-disabled.*")), [])

    def test_enable_rejects_directory_blacklist(self):
        directory = self.root / "blacklist-directory"
        directory.mkdir()
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_enable sdkman
''', check=False, extra_env={"ENVMANAGER_DISABLED_FILE": str(directory)})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("blacklist path is a directory", result.stderr)
                self.assertEqual(list(directory.iterdir()), [])

    def test_missing_final_newline_and_relative_override(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                blacklist = self.root / "relative-disabled"
                blacklist.write_text("sdkman")
                result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_is_disabled sdkman || exit 10
em_disable gpg || exit 11
em_disable
''', extra_env={"ENVMANAGER_DISABLED_FILE": "relative-disabled"})
                self.assertEqual(result.stdout.splitlines(), ["gpg", "sdkman"])

    def test_failed_write_is_reported(self):
        blocker = self.root / "blocker"
        blocker.write_text("file, not a directory")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_disable sdkman
''', check=False, extra_env={"ENVMANAGER_DISABLED_FILE": str(blocker / "disabled")})
                self.assertNotEqual(result.returncode, 0)
                self.assertNotEqual(result.stderr, "")
                self.assertEqual(blocker.read_text(), "file, not a directory")

    def test_blacklist_path_cannot_be_a_directory(self):
        directory = self.root / "blacklist-directory"
        directory.mkdir()
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, '''
source "$ENVMANAGER_DIR/00-core.sh"
em_disable sdkman
''', check=False, extra_env={"ENVMANAGER_DISABLED_FILE": str(directory)})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("blacklist path is a directory", result.stderr)
                self.assertEqual(list(directory.iterdir()), [])

    def test_os_filters_and_local_blacklist(self):
        expected = {
            "Linux": ["02-gpg.linux.sh", "05-gpg.linux.local.sh"],
            "Darwin": ["03-apple.macos.sh", "04-alias.darwin.sh"],
            "FreeBSD": ["06-bsd.freebsd.sh"],
            "MINGW64_NT-10.0": ["07-windows.windows.sh"],
        }
        for shell in SHELLS:
            for os_name, os_scripts in expected.items():
                with self.subTest(shell=shell, os=os_name):
                    if self.log.exists():
                        self.log.unlink()
                    (self.repo / "disabled-scripts").write_text("sdkman\ncore\n")
                    self.shell(shell, '''
uname() { printf '%s\\n' "$TEST_OS"; }
source "$ENVMANAGER_DIR/00-core.sh"
em_load_scripts
''', extra_env={"TEST_OS": os_name})
                    self.assertEqual(self.log.read_text().splitlines(),
                                     ["00-before.sh", "01-generic.sh"] + os_scripts)

    def test_documented_loader_uses_filters_and_updates_once(self):
        loader = (PROJECT / "README.md").read_text().split("```sh\n", 1)[1].split("```", 1)[0]
        (self.repo / "disabled-scripts").write_text("sdkman\n")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                if self.log.exists():
                    self.log.unlink()
                run_log = self.root / f"{shell}-git"
                self.shell(shell, '''
uname() { printf 'Linux\\n'; }
git() { printf 'update\\n' >> "$TEST_GIT_LOG"; }
''' + loader + "\n" + loader, extra_env={
                    "TEST_GIT_LOG": str(run_log),
                    "TMPDIR": str(self.root / f"{shell}-tmp"),
                })
                expected = ["00-before.sh", "01-generic.sh", "02-gpg.linux.sh", "05-gpg.linux.local.sh"]
                self.assertEqual(self.log.read_text().splitlines(), expected * 2)
                self.assertEqual(run_log.read_text(), "update\n")

    def test_documented_loader_bootstraps_a_missing_installation(self):
        loader = (PROJECT / "README.md").read_text().split("```sh\n", 1)[1].split("```", 1)[0]
        for shell in SHELLS:
            with self.subTest(shell=shell):
                config_directory = self.root / f"{shell}-new-config"
                installed = config_directory / "envmanager"
                self.shell(shell, '''
git() {
  if [ "$1" = clone ]; then
    [ "$#" -eq 3 ] && [ -d "${3%/*}" ] && [ ! -e "$3" ] || return 20
    cp -R "$TEST_SOURCE_REPO" "$3" || return
    printf 'clone\n' >> "$TEST_GIT_LOG"
  elif [ "$1" = -C ] && [ -d "$2" ] && [ "$3" = pull ]; then
    printf 'update\n' >> "$TEST_GIT_LOG"
  else
    return 21
  fi
}
''' + loader, extra_env={
                    "XDG_CONFIG_HOME": str(config_directory),
                    "TEST_SOURCE_REPO": str(self.repo),
                    "TEST_GIT_LOG": str(self.root / f"{shell}-git"),
                    "TMPDIR": str(self.root / f"{shell}-tmp"),
                })
                self.assertTrue((installed / "00-core.sh").is_file())
                self.assertEqual((self.root / f"{shell}-git").read_text(), "clone\nupdate\n")

    @unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
    def test_zsh_completions_filter_by_os_and_disabled_state(self):
        common = {"before", "generic", "sdkman"}
        platform_names = {
            "Linux": {"gpg"},
            "Darwin": {"apple", "alias"},
            "FreeBSD": {"bsd"},
            "OpenBSD": set(),
            "NetBSD": set(),
            "MSYS_NT-10.0": {"windows"},
        }
        for os_name, specific in platform_names.items():
            with self.subTest(os=os_name):
                blacklist = self.repo / "disabled-scripts"
                if blacklist.exists():
                    blacklist.unlink()
                result = self.shell("zsh", '''
uname() { printf '%s\\n' "$TEST_OS"; }
autoload -Uz compinit; compinit -D -i
source "$ENVMANAGER_DIR/00-core.sh"
compadd() { printf '%s\\n' "${names[@]}"; }
_em_disable
printf '%s\\n' ---
printf '%s\\n' sdkman gpg apple alias bsd windows removed-tool > "$(em_disabled_file)"
_em_disable
printf '%s\\n' ---
_em_enable
''', extra_env={"TEST_OS": os_name})
                initial, remaining, enabled = result.stdout.split("---\n")
                self.assertEqual(set(initial.splitlines()), common | specific)
                self.assertEqual(len(initial.splitlines()), len(common | specific))
                self.assertEqual(set(remaining.splitlines()), {"before", "generic"})
                self.assertEqual(set(enabled.splitlines()), {"sdkman"} | specific)
                self.assertEqual(len(enabled.splitlines()), len({"sdkman"} | specific))

    def test_cross_platform_scripts_can_still_be_managed_explicitly(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.shell(shell, '''
uname() { printf 'Linux\\n'; }
source "$ENVMANAGER_DIR/00-core.sh"
em_disable apple || exit 10
em_is_disabled apple || exit 11
em_enable apple || exit 12
em_is_disabled apple && exit 13
exit 0
''')

    @unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
    def test_zsh_completion_before_and_after_compinit(self):
        for order in ("before", "after"):
            with self.subTest(order=order):
                initialize = "autoload -Uz compinit; compinit -D -i\n"
                source = 'source "$ENVMANAGER_DIR/00-core.sh"\n'
                setup = source + initialize if order == "before" else initialize + source
                setup = "uname() { printf 'Linux\\n'; }\n" + setup
                result = self.shell("zsh", setup + '''
[[ "${_comps[em_disable]}" = _em_disable ]] || exit 10
# Exercise the actual autoloaded completion, capturing its compadd candidates.
compadd() { printf '%s\\n' "${names[@]}"; }
_em_disable
em_disable sdkman || exit 11
printf '%s\\n' ---
_em_disable
''')
                first, second = result.stdout.split("---\n")
                self.assertIn("sdkman", first.splitlines())
                self.assertNotIn("sdkman", second.splitlines())
                self.assertNotIn("core", first.splitlines())
                self.assertEqual(first.splitlines().count("gpg"), 1)
                (self.repo / "disabled-scripts").unlink()

    @unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
    def test_zsh_enable_completion_before_and_after_compinit(self):
        for order in ("before", "after"):
            with self.subTest(order=order):
                (self.repo / "disabled-scripts").write_text("gpg\nsdkman\nremoved-tool\n")
                initialize = "autoload -Uz compinit; compinit -D -i\n"
                source = 'source "$ENVMANAGER_DIR/00-core.sh"\n'
                setup = source + initialize if order == "before" else initialize + source
                setup = "uname() { printf 'Linux\\n'; }\n" + setup
                result = self.shell("zsh", setup + '''
[[ "${_comps[em_enable]}" = _em_enable ]] || exit 10
compadd() { printf '%s\\n' "${names[@]}"; }
_em_enable
em_enable sdkman || exit 11
printf '%s\\n' ---
_em_enable
''')
                first, second = result.stdout.split("---\n")
                self.assertEqual(set(first.splitlines()), {"gpg", "sdkman"})
                self.assertEqual(set(second.splitlines()), {"gpg"})


if __name__ == "__main__":
    unittest.main()
