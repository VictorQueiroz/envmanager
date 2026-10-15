"""Shell integration is activated explicitly and preserves argument values."""

import os
import shutil
import unittest

from helpers import SHELLS, SOURCE_MODULES, ShellTestCase


class ShellTests(ShellTestCase):
    def test_automatic_logging_omits_environment_values_and_command_arguments(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.shell(shell, SOURCE_MODULES + '''
systemd-cat() { printf '%s\n' "$@" >> "$TEST_LOG"; }
env() { printf 'unexpected environment dump\n' >> "$TEST_LOG"; }
em_init
em_export_alternatives EM_TEST_VALUE "$TEST_PRIVATE_VALUE"
em_export_alternatives EM_TEST_VALUE ignored
record() { [ "$1" = "$TEST_PRIVATE_VALUE" ]; }
em_run_every 30s record "$TEST_PRIVATE_VALUE" || exit 10
em_run_every 30s record "$TEST_PRIVATE_VALUE" || exit 11
''', extra_env={
                    "ENVMANAGER_ENABLE_LOGGING": "true",
                    "TEST_PRIVATE_VALUE": "test-only-confidential-marker",
                    "TMPDIR": str(self.root / f"{shell}-tmp"),
                })
                messages = self.log.read_text()
                self.assertIn("Configured %s", messages)
                self.assertIn("em_run_every: running", messages)
                self.assertNotIn("test-only-confidential-marker", messages)
                self.assertNotIn("unexpected environment dump", messages)
                self.log.unlink()

    def test_existing_shell_integrations_are_preserved(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, '''
znap() { printf 'existing znap\n'; }
compdef() { printf 'existing compdef\n'; }
''' + SOURCE_MODULES + '''
em_install_shell_fallbacks
znap
compdef
''')
                self.assertEqual(result.stdout, "existing znap\nexisting compdef\n")

    def test_lazy_fallback_initializes_once_and_forwards_arguments(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
em_install_shell_fallbacks
znap function loader em_lazy 'printf "setup\\n" >> "$TEST_LOG"; em_lazy() { printf "<%s>\\n" "$@"; }'
em_lazy "one two" "" '$(literal)'
em_lazy second
''')
                self.assertEqual(result.stdout, "<one two>\n<>\n<$(literal)>\n<second>\n")
                self.assertEqual(self.log.read_text(), "setup\n")
                self.log.unlink()

    def test_logging_is_disabled_until_enabled(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
systemd-cat() { printf '<%s>\n' "$@" >> "$TEST_LOG"; }
em_print_debug '%s' "quiet"
[ ! -f "$TEST_LOG" ] || exit 10
ENVMANAGER_ENABLE_LOGGING=true
ENVMANAGER_SYSTEMD_IDENTIFIER=example
em_print_debug '%s' "two words"
em_print_err '%s' "failure"
''')
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.log.read_text().splitlines(), [
                    "<--stderr-priority=err>", "<--identifier=example>", "<--priority=debug>",
                    "<printf>", "<%s>", "<two words>",
                    "<--stderr-priority=err>", "<--identifier=example>", "<--priority=err>",
                    "<printf>", "<%s>", "<failure>",
                ])
                self.log.unlink()

    def test_lazy_fallback_can_prepare_an_external_command(self):
        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        executable = bin_directory / "em_external"
        executable.write_text('''#!/bin/sh
printf '<%s>\\n' "$@"
''')
        executable.chmod(0o700)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
em_install_shell_fallbacks
znap function loader em_external 'printf "setup\\n" >> "$TEST_LOG"'
em_external "one two" ""
em_external second
''', extra_env={"PATH": f"{bin_directory}:{os.environ['PATH']}"})
                self.assertEqual(result.stdout, "<one two>\n<>\n<second>\n")
                self.assertEqual(self.log.read_text(), "setup\n")
                self.log.unlink()

    @unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
    def test_repeated_initialization_deduplicates_completion_hooks(self):
        result = self.shell("zsh", SOURCE_MODULES + '''
em_init
em_init
for directory in "${fpath[@]}"; do
  [ "$directory" != "$ENVMANAGER_DIR/completions" ] || printf 'directory\n'
done
printf '%s\n' "${precmd_functions[@]}"
autoload -Uz compinit
compinit -D -i
em_register_completions
[[ "${_comps[em_disable]}" = _em_disable ]] || exit 10
for hook in "${precmd_functions[@]}"; do
  [ "$hook" != em_register_completions ] || exit 11
done
''')
        self.assertEqual(result.stdout.splitlines(), ["directory", "em_register_completions"])


if __name__ == "__main__":
    unittest.main()
