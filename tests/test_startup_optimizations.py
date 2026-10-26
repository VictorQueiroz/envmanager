"""Startup shortcuts must preserve platform overrides and Node selection."""

import shutil
import unittest

from helpers import PROJECT, SHELLS, SOURCE_CORE, SOURCE_MODULES, ShellTestCase


class PlatformCacheTests(ShellTestCase):
    def test_loading_probes_once_per_pass_and_preserves_caller_state(self):
        for index in range(5):
            (self.repo / f"0{index + 1}-fixture.sh").write_text(
                'export EM_FROM_SCRIPT=yes\n'
                'em_current_os\nem_current_runtime\n'
                'em_fixture_function() { :; }\n'
            )
        for shell in SHELLS:
            with self.subTest(shell=shell):
                if self.log.exists():
                    self.log.unlink()
                result = self.shell(shell, SOURCE_MODULES + '''
uname() { printf 'probe\\n' >> "$TEST_LOG"; printf 'Darwin\\n'; }
em_load_scripts || exit 10
em_load_scripts || exit 11
[ "$EM_FROM_SCRIPT" = yes ] || exit 12
em_fixture_function || exit 13
em_current_os
[ -z "$_EM_PLATFORM_CACHE" ] || exit 14
''')
                self.assertEqual(result.stdout.splitlines(), ["macos", "system"] * 10 + ["macos"])
                self.assertEqual(self.log.read_text().splitlines(), ["probe"] * 3)

    def test_override_changes_invalidate_cached_os_and_runtime(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
uname() { printf 'Linux\\n'; }
check_context() {
  em_current_os; em_current_runtime
  TERMUX_VERSION=fixture
  em_current_os; em_current_runtime
  PREFIX=/app
  em_current_os; em_current_runtime
  ENVMANAGER_RUNTIME=system
  em_current_os; em_current_runtime
  ENVMANAGER_OS=linux
  em_current_os; em_current_runtime
  unset ENVMANAGER_OS ENVMANAGER_RUNTIME PREFIX TERMUX_VERSION
  em_current_os; em_current_runtime
}
em_with_platform check_context
''')
                self.assertEqual(result.stdout.splitlines(), [
                    "linux", "system", "linux", "system", "android", "termux",
                    "android", "system", "linux", "system", "linux", "system",
                ])

    def test_override_in_sourced_script_changes_subsequent_filtering(self):
        (self.repo / "01-change.sh").write_text("ENVMANAGER_OS=linux\n")
        (self.repo / "02-matches.linux.sh").write_text("export EM_MATCHED=yes\n")
        (self.repo / "03-other.macos.sh").write_text("return 91\n")
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
uname() { printf 'Darwin\\n'; }
em_load_scripts || exit 10
printf '%s\\n' "$EM_MATCHED" "$ENVMANAGER_OS"
''')
                self.assertEqual(result.stdout, "yes\nlinux\n")

    def test_cache_scope_preserves_failure_and_current_directory(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
uname() { printf 'Darwin\\n'; }
callback() { cd "$HOME" || return; export EM_CALLBACK=yes; return 23; }
em_with_platform callback
[ "$?" = 23 ] && [ "$PWD" = "$HOME" ] && [ "$EM_CALLBACK" = yes ] || exit 10
[ -z "$_EM_PLATFORM_CACHE" ] || exit 11
uname() { return 7; }
em_with_platform callback
[ "$?" = 7 ] || exit 12
''')
                self.assertEqual(result.stdout, "")


class NvmStartupTests(ShellTestCase):
    def setUp(self):
        super().setUp()
        shutil.copy2(PROJECT / "99-nvm.sh", self.repo)
        self.nvm = self.home / ".nvm"
        (self.nvm / "alias").mkdir(parents=True)
        (self.nvm / "nvm.sh").write_text('''
printf 'source:%s\\n' "$1" >> "$TEST_LOG"
nvm() {
  case "$1" in
    current)
      printf '%s\\n' "$TEST_NVM_CURRENT"
      [ "$TEST_NVM_CURRENT" != none ] ;;
    use)
      printf '%s\\n' "$*" >> "$TEST_LOG"
      export NVM_BIN="$NVM_DIR/versions/node/$3/bin" ;;
    *) return 91 ;;
  esac
}
if [ "$1" != --no-use ]; then
  nvm use --silent default
fi
''')

    def install_version(self, version, *, executable=True):
        binary = self.nvm / "versions/node" / version / "bin/node"
        binary.parent.mkdir(parents=True, exist_ok=True)
        binary.write_text("#!/bin/sh\nexit 0\n")
        binary.chmod(0o700 if executable else 0o600)

    def check_startup(self, expected, *, current="none", enabled="true"):
        for shell in SHELLS:
            with self.subTest(shell=shell, current=current, enabled=enabled):
                if self.log.exists():
                    self.log.unlink()
                self.shell(shell, SOURCE_CORE + '''
. "$ENVMANAGER_DIR/99-nvm.sh"
command -v nvm >/dev/null || exit 10
[ -z "$NODE_PATH" ] || exit 11
''', extra_env={"TEST_NVM_CURRENT": current,
               "ENVMANAGER_NVM_FAST_STARTUP": enabled})
                self.assertEqual(self.log.read_text().splitlines(), expected)

    def test_unambiguous_numeric_defaults_select_installed_version_immediately(self):
        self.install_version("v24.11.0")
        self.install_version("v240.0.0")
        for requested in ("24", "v24", "24.11", "v24.11.0"):
            with self.subTest(requested=requested):
                (self.nvm / "alias/default").write_text(requested + "\n")
                self.check_startup(["source:--no-use", "use --silent v24.11.0"])

    def test_existing_active_node_is_preserved(self):
        self.install_version("v24.11.0")
        self.install_version("v22.10.0")
        (self.nvm / "alias/default").write_text("24\n")
        self.check_startup(["source:--no-use", "use --silent v22.10.0"], current="v22.10.0")
        self.check_startup(["source:--no-use", "use --silent v24.11.0"], current="system")

    def test_named_aliases_and_alias_chains_keep_normal_nvm_initialization(self):
        self.install_version("v24.11.0")
        for requested in ("stable", "lts/*", "system", "24-invalid", "0.10", "3", ""):
            with self.subTest(requested=requested):
                (self.nvm / "alias/default").write_text(requested + "\n")
                self.check_startup(["source:", "use --silent default"])
        (self.nvm / "alias/default").write_text("24\n")
        (self.nvm / "alias/24").write_text("22\n")
        self.check_startup(["source:", "use --silent default"])

    def test_ambiguous_or_missing_installations_keep_normal_nvm_initialization(self):
        (self.nvm / "alias/default").write_text("24\n")
        self.check_startup(["source:", "use --silent default"])
        self.install_version("v24.11.0", executable=False)
        self.check_startup(["source:", "use --silent default"])
        self.install_version("v24.11.0")
        self.install_version("v24.12.0")
        self.check_startup(["source:", "use --silent default"])

    def test_fast_startup_can_be_disabled(self):
        self.install_version("v24.11.0")
        (self.nvm / "alias/default").write_text("24\n")
        self.check_startup(["source:", "use --silent default"], enabled="false")

    def test_incomplete_matching_installation_keeps_normal_nvm_initialization(self):
        self.install_version("v24.11.0")
        (self.nvm / "alias/default").write_text("24\n")
        (self.nvm / "versions/node/v24.12.0").mkdir()
        self.check_startup(["source:", "use --silent default"])
        self.install_version("v24.12.0", executable=False)
        self.check_startup(["source:", "use --silent default"])


if __name__ == "__main__":
    unittest.main()
