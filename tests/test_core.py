"""Library imports and startup are separate operations."""

import unittest

from helpers import MODULES, SHELLS, SOURCE_CORE, SOURCE_MODULES, ShellTestCase


class CoreTests(ShellTestCase):
    def test_each_module_and_repeated_imports_have_no_startup_effects(self):
        imports = [f'source "$ENVMANAGER_DIR/lib/{name}.sh"' for name in MODULES]
        imports.append(SOURCE_MODULES + "\n" + SOURCE_MODULES)
        for shell in SHELLS:
            for code in imports:
                with self.subTest(shell=shell, imports=code):
                    result = self.shell(shell, '''
before_environment="$(export -p)"
before_fpath="$FPATH"
mkdir() { printf 'mkdir\n' >> "$TEST_LOG"; }
env() { printf 'env\n' >> "$TEST_LOG"; }
uname() { printf 'uname\n' >> "$TEST_LOG"; }
date() { printf 'date\n' >> "$TEST_LOG"; }
''' + code + '''
[ "$(export -p)" = "$before_environment" ] || exit 10
[ "$FPATH" = "$before_fpath" ] || exit 11
[ -z "${ENVMANAGER_VERSION+set}" ] || exit 12
[ -z "${ENVMANAGER_RUN_EVERY_DEFAULT+set}" ] || exit 13
if typeset -f znap >/dev/null; then exit 14; fi
if typeset -f compdef >/dev/null; then exit 15; fi
''', extra_env={"TMPDIR": ""})
                    self.assertEqual(result.stdout, "")
                    self.assertFalse(self.log.exists())
                    self.assertFalse((self.home / ".tmp").exists())

    def test_bootstrap_initializes_defaults(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_CORE + '''
printf '%s\n' "$TMPDIR" "$ENVMANAGER_VERSION" "$ENVMANAGER_RUN_EVERY_DEFAULT"
command -v znap >/dev/null || exit 10
sh -c 'printf "%s\\n" "$TMPDIR"'
''', extra_env={"TMPDIR": ""})
                temporary = str(self.home / ".tmp")
                self.assertEqual(result.stdout.splitlines(), [temporary, "0.1.0", "86400", temporary])
                self.assertTrue((self.home / ".tmp").is_dir())

    def test_bootstrap_resolves_home_and_xdg_locations(self):
        for shell in SHELLS:
            for use_xdg in (False, True):
                with self.subTest(shell=shell, xdg=use_xdg):
                    extra = {"ENVMANAGER_DIR": "", "TEST_CORE": str(self.repo / "00-core.sh")}
                    if use_xdg:
                        extra["XDG_CONFIG_HOME"] = str(self.repo.parent)
                        extra["HOME"] = str(self.root / "another home")
                    result = self.shell(shell, '''
source "$TEST_CORE" || exit 10
printf '%s\n' "$ENVMANAGER_DIR"
''', extra_env=extra)
                    self.assertEqual(result.stdout, str(self.repo) + "\n")

    def test_explicit_initialization_respects_configured_defaults(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                temporary = self.root / f"{shell}-configured"
                result = self.shell(shell, SOURCE_MODULES + '''
em_init
em_init
printf '%s\n' "$TMPDIR" "$ENVMANAGER_RUN_EVERY_DEFAULT"
''', extra_env={"TMPDIR": str(temporary), "ENVMANAGER_RUN_EVERY_DEFAULT": "2h"})
                self.assertEqual(result.stdout.splitlines(), [str(temporary), "2h"])
                self.assertFalse(temporary.exists())

    def test_no_home_uses_system_temporary_directory(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
em_init_environment
printf '%s\n' "$TMPDIR"
''', extra_env={"HOME": "", "TMPDIR": ""})
                self.assertEqual(result.stdout, "/tmp\n")


if __name__ == "__main__":
    unittest.main()
