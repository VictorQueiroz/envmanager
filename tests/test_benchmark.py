"""Startup tracing must preserve the shell while locating slow commands."""

import shutil
import subprocess
import unittest

from helpers import ShellTestCase


SOURCE = 'source "$ENVMANAGER_DIR/lib/benchmark-zsh.sh"\n'


@unittest.skipUnless(shutil.which("zsh"), "Zsh is not installed")
class BenchmarkTests(ShellTestCase):
    def run_profile(self, code, *, extra_env=None):
        result = self.shell("zsh", SOURCE + code, check=False, extra_env=extra_env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_reports_only_over_budget_in_descending_order_with_exact_locations(self):
        fixture = self.repo / "slow commands.zsh"
        fixture.write_text(
            "sleep .01\n"
            "slow_function() {\n"
            "  sleep .25\n"
            "}\n"
            "slow_function\n"
            "value=\"$(sleep .35; printf 'captured')\"\n"
            "printf '%s\\n' \"$value\"\n"
        )
        result = self.run_profile('''
em_benchmark_start
source "$TEST_FIXTURE"
em_benchmark_stop
''', extra_env={"TEST_FIXTURE": str(fixture)})
        self.assertEqual(result.stdout, "captured\n")
        self.assertIn("2 commands > 200 ms", result.stderr)
        rows = result.stderr.splitlines()[2:]
        self.assertIn(str(fixture) + ':6  value="$(sleep .35;', rows[0])
        self.assertIn(str(fixture) + ":3  sleep .25", rows[1])
        self.assertNotIn("sleep .01", result.stderr)

    def test_budget_truncation_and_last_command_are_configurable(self):
        fixture = self.repo / "long command.zsh"
        fixture.write_text('value="$(sleep .07; printf \'%s\' \'long long long long long command\')"\n')
        result = self.run_profile('''
em_benchmark_start
source "$TEST_FIXTURE"
em_benchmark_stop
''', extra_env={"TEST_FIXTURE": str(fixture),
               "ENVMANAGER_BENCHMARK_BUDGET_MS": "30",
               "ENVMANAGER_BENCHMARK_MAX_COMMAND_LENGTH": "40"})
        self.assertIn("1 commands > 30 ms", result.stderr)
        row = result.stderr.splitlines()[2]
        self.assertIn(str(fixture) + ":1", row)
        text = row.split("  ")[-1]
        self.assertEqual(len(text), 40)
        self.assertTrue(text.endswith("..."))

    def test_preserves_status_options_io_and_removes_tracing(self):
        result = self.run_profile('''
before_options="$(setopt)"
em_benchmark_start 200
false
observed=$?
printf 'status=%s\\n' "$observed"
printf 'ordinary stderr\\n' >&2
em_benchmark_stop
[[ "$(setopt)" == "$before_options" ]] || exit 10
(( $+functions[TRAPDEBUG] == 0 )) || exit 11
(( precmd_functions[(Ie)em_benchmark_stop] == 0 )) || exit 12
(( zshexit_functions[(Ie)em_benchmark_stop] == 0 )) || exit 13
sleep .01
em_benchmark_stop
''')
        self.assertEqual(result.stdout, "status=1\n")
        self.assertTrue(result.stderr.startswith("ordinary stderr\n"))
        self.assertEqual(result.stderr.count("envmanager: startup"), 1)
        self.assertIn("0 commands > 200 ms", result.stderr)

    def test_existing_function_and_list_debug_traps_are_preserved(self):
        for handler in ("TRAPDEBUG() { :; }", "trap ':' DEBUG"):
            with self.subTest(handler=handler):
                result = self.run_profile(handler + '''
before="$(trap)"
em_benchmark_start
[[ "$(trap)" == "$before" ]] || exit 10
[[ $_em_benchmark_active != true ]] || exit 11
''')
                self.assertIn("DEBUG trap is already installed", result.stderr)

    def test_invalid_settings_do_not_install_a_trap(self):
        for budget, width in (("no", "100"), ("-1", "100"), ("1.5", "100"),
                              ("200", "3"), ("200", "x"), ("999999999", "100")):
            with self.subTest(budget=budget, width=width):
                result = self.run_profile('''
em_benchmark_start
[[ $? == 2 ]] || exit 10
(( $+functions[TRAPDEBUG] == 0 )) || exit 11
''', extra_env={"ENVMANAGER_BENCHMARK_BUDGET_MS": budget,
               "ENVMANAGER_BENCHMARK_MAX_COMMAND_LENGTH": width})
                self.assertIn("budget must be", result.stderr)

    def test_import_is_inert_and_auto_is_disabled_in_noninteractive_shells(self):
        self.shell("zsh", SOURCE + '''
em_benchmark_auto
[[ $_em_benchmark_active != true ]] || exit 10
(( $+functions[TRAPDEBUG] == 0 )) || exit 11
''')

    def test_real_interactive_login_reports_once_and_can_be_disabled(self):
        dotdir = self.root / "zsh startup"
        dotdir.mkdir()
        (dotdir / ".zshrc").write_text(SOURCE + "em_benchmark_auto\nsleep .25\n")
        (dotdir / ".zlogin").write_text("sleep .30\n")
        for enabled in ("true", "false"):
            with self.subTest(enabled=enabled):
                result = subprocess.run(
                    # Read the fixture's login/interactive files without the
                    # host's global startup files (e.g. Ubuntu's compinit).
                    [shutil.which("zsh"), "-dlic", "print ready"],
                    capture_output=True, text=True, timeout=10,
                    env=self.environment | {"ZDOTDIR": str(dotdir),
                                            "ENVMANAGER_BENCHMARK": enabled},
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "ready\n")
                if enabled == "true":
                    self.assertEqual(result.stderr.count("envmanager: startup"), 1)
                    self.assertIn(str(dotdir / ".zshrc") + ":3", result.stderr)
                    self.assertIn(str(dotdir / ".zlogin") + ":1", result.stderr)
                else:
                    self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()
