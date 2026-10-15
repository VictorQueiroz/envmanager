"""Deterministic throttling checks; commands only write to temporary files."""

import unittest

from helpers import SHELLS, SOURCE_MODULES, ShellTestCase


SOURCE_RUN_EVERY = SOURCE_MODULES + "\nem_init_environment\n"


class RunEveryTests(ShellTestCase):
    def test_expiry_boundary(self):
        for shell in SHELLS:
            for now, expiry, pending in ((1000, "", False), (1000, "1001", True),
                                        (1000, "1000", False), (1000, "999", False)):
                with self.subTest(shell=shell, now=now, expiry=expiry):
                    result = self.shell(shell, SOURCE_RUN_EVERY +
                                        'em_expiry_pending "$NOW" "$EXPIRY"\n', check=False,
                                        extra_env={"NOW": str(now), "EXPIRY": expiry})
                    self.assertEqual(result.returncode, 0 if pending else 1)
                    self.assertEqual(result.stdout, "")
                    self.assertEqual(result.stderr, "")

    def test_throttle_persists_between_shell_processes(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                code = SOURCE_RUN_EVERY + '''
em_now() { printf '1000\n'; }
record() { printf 'run\n' >> "$TEST_LOG"; }
em_run_every 1d record
'''
                extra = {"TMPDIR": str(self.root / f"{shell}-tmp")}
                self.shell(shell, code, extra_env=extra)
                self.shell(shell, code, extra_env=extra)
                self.assertEqual(self.log.read_text(), "run\n")
                self.log.unlink()

    def test_failed_state_write_is_reported(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_RUN_EVERY + '''
em_mkdir() { return 23; }
record() { printf 'run\n'; }
em_run_every 1d record
''', check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "run\n")
                self.assertFalse((self.root / "tmp").exists())

    def test_durations(self):
        for shell in SHELLS:
            for duration, expected in (("1d", 86400), ("12h", 43200), ("30m", 1800),
                                       ("90s", 90), ("42", 42), ("0s", 0)):
                with self.subTest(shell=shell, duration=duration):
                    result = self.shell(shell, SOURCE_RUN_EVERY + 'em_duration_to_seconds "$DURATION"',
                                        extra_env={"DURATION": duration})
                    self.assertEqual(result.stdout, str(expected))

    def test_runs_skips_and_runs_at_expiry(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                # Fixed time, with no waiting and no dependence on the host clock.
                result = self.shell(shell, SOURCE_RUN_EVERY + '''
em_now() { printf '%s\n' "$TEST_NOW"; }
record() { printf '%s\n' "$1" >> "$TEST_LOG"; }
TEST_NOW=1000
em_run_every 30s record "argument with spaces" || exit 10
TEST_NOW=1029
em_run_every 30s record "argument with spaces" || exit 11
TEST_NOW=1030
em_run_every 30s record "argument with spaces"
''', extra_env={"TMPDIR": str(self.root / f"{shell}-tmp")})
                self.assertEqual(result.stdout, "")
                self.assertEqual(self.log.read_text(), "argument with spaces\n" * 2)
                states = list(self.state_directory(shell).iterdir())
                self.assertEqual(len(states), 1)
                self.assertEqual(states[0].read_text(), "1060\n")
                self.log.unlink()

    def test_failure_propagates_and_retries(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.shell(shell, SOURCE_RUN_EVERY + '''
em_now() { printf '1000\n'; }
attempt() { printf 'attempt\n' >> "$TEST_LOG"; return "$TEST_EXIT"; }
TEST_EXIT=7
em_run_every 1d attempt
[ "$?" -eq 7 ] || exit 10
[ ! -d "$TMPDIR/envmanager/run-every" ] || exit 11
TEST_EXIT=0
em_run_every 1d attempt || exit 12
em_run_every 1d attempt
''', extra_env={"TMPDIR": str(self.root / f"{shell}-tmp")})
                self.assertEqual(self.log.read_text(), "attempt\n" * 2)
                self.log.unlink()

    def test_default_and_explicit_intervals(self):
        for shell in SHELLS:
            for interval, expected in (("", 1120), ("20", 1020), ("2m", 1120)):
                with self.subTest(shell=shell, interval=interval):
                    temporary = self.root / f"{shell}-{interval or 'default'}"
                    self.shell(shell, SOURCE_RUN_EVERY + '''
em_now() { printf '1000\n'; }
record() { :; }
''' + f"em_run_every {interval} record\n", extra_env={
                        "TMPDIR": str(temporary), "ENVMANAGER_RUN_EVERY_DEFAULT": "120",
                    })
                    states = list((temporary / "envmanager/run-every").iterdir())
                    self.assertEqual(len(states), 1)
                    self.assertEqual(states[0].read_text(), f"{expected}\n")

    def test_command_receives_exact_arguments(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_RUN_EVERY + '''
record() { printf '<%s>\n' "$@"; }
em_run_every 0s record "a b" "" "c*d" '$(literal)'
''')
                self.assertEqual(result.stdout, "<a b>\n<>\n<c*d>\n<$(literal)>\n")

    def test_no_command_returns_usage_status(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_RUN_EVERY + "em_run_every\n", check=False)
                self.assertEqual(result.returncode, 2)
                self.assertFalse((self.root / "tmp").exists())


if __name__ == "__main__":
    unittest.main()
