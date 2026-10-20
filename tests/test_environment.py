"""Environment selection and exports must work in the caller's shell."""

import unittest

from helpers import SHELLS, SOURCE_MODULES, ShellTestCase


SOURCE_ENVIRONMENT = SOURCE_MODULES + "\n"


class EnvironmentTests(ShellTestCase):
    def test_first_nonempty_selection(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
em_first_nonempty "" "one two" second
em_first_nonempty "" ""
em_first_nonempty
''')
                self.assertEqual(result.stdout, "one two\n\n\n")

    def test_helpers_do_not_leak_variables(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
var_name=original_name
value=original_value
alt=original_alt
alternative=original_alternative
EM_VALUE=lookup
em_get_var_value EM_VALUE
unset EM_VALUE
em_export_alternatives EM_VALUE fallback
printf '%s\n' "$var_name" "$value" "$alt" "$alternative"
''')
                self.assertEqual(result.stdout.splitlines(), [
                    "lookup", "original_name", "original_value", "original_alt", "original_alternative",
                ])

    def test_lookup_preserves_literal_values(self):
        for shell in SHELLS:
            for value in ("-n", r"one\ntwo", '$(literal) "quoted"', "var_name"):
                with self.subTest(shell=shell, value=value):
                    result = self.shell(shell, SOURCE_ENVIRONMENT + "em_get_var_value EM_VALUE\n",
                                        extra_env={"EM_VALUE": value})
                    self.assertEqual(result.stdout, value + "\n")

    def test_invalid_variable_names_return_usage_status(self):
        for shell in SHELLS:
            for name in ("", "1INVALID", "EM_VALUE; false", "EM_VALUE[0]"):
                with self.subTest(shell=shell, name=name):
                    result = self.shell(shell, SOURCE_ENVIRONMENT +
                                        'em_export_alternatives "$INVALID_NAME" fallback\n',
                                        check=False, extra_env={"INVALID_NAME": name})
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(result.stdout, "")

    def test_export_alternatives(self):
        cases = (
            ('export EM_VALUE="existing value"; em_export_alternatives EM_VALUE fallback', "existing value"),
            ('unset EM_VALUE; em_export_alternatives EM_VALUE "" "first value" second', "first value"),
            ('EM_VALUE=""; em_export_alternatives EM_VALUE fallback', "fallback"),
            ('unset EM_VALUE; em_export_alternatives EM_VALUE "" ""', ""),
        )
        for shell in SHELLS:
            for code, expected in cases:
                with self.subTest(shell=shell, code=code):
                    result = self.shell(shell, SOURCE_ENVIRONMENT + code + '''
printf '<%s>\n' "$EM_VALUE"
sh -c 'printf "<%s>\\n" "$EM_VALUE"'
''')
                    self.assertEqual(result.stdout, f"<{expected}>\n<{expected}>\n")

    def test_no_alternatives_leaves_variable_unset(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
unset EM_VALUE
em_export_alternatives EM_VALUE
printf '%s\n' "${EM_VALUE+set}"
''')
                self.assertEqual(result.stdout, "\n")

    def test_existing_local_value_stays_local(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
EM_VALUE=local
em_export_alternatives EM_VALUE fallback
printf '%s\n' "$EM_VALUE"
sh -c 'printf "%s\\n" "${EM_VALUE+exported}"'
''')
                self.assertEqual(result.stdout, "local\n\n")

    def test_variable_lookup(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
EM_VALUE='two words and "quotes"'
em_get_var_value EM_VALUE
unset EM_VALUE
em_get_var_value EM_VALUE
''')
                self.assertEqual(result.stdout, 'two words and "quotes"\n\n')

    def test_path_selection_reuses_existing_paths_before_new_defaults(self):
        preferred = self.root / "preferred path"
        conventional = self.home / "conventional path"
        conventional.mkdir()
        cases = (
            (preferred, [self.root / "absent"], preferred),
            (preferred, [self.root / "absent", conventional], conventional),
            (conventional, [preferred], conventional),
        )
        for shell in SHELLS:
            for default, candidates, expected in cases:
                with self.subTest(shell=shell, default=default, candidates=candidates):
                    result = self.shell(shell, SOURCE_ENVIRONMENT + '''
em_export_path EM_PATH "$PREFERRED" "$FIRST" "$SECOND" || exit 10
printf '%s\\n' "$EM_PATH"
sh -c 'printf "%s\\n" "$EM_PATH"'
''', extra_env={"PREFERRED": str(default), "FIRST": str(candidates[0]),
                "SECOND": str(candidates[1]) if len(candidates) > 1 else ""})
                    self.assertEqual(result.stdout.splitlines(), [str(expected)] * 2)
                    self.assertFalse(preferred.exists())

    def test_path_selection_supports_files_symlinks_and_literal_names(self):
        existing = self.home / '$(touch unexpected) "config"'
        existing.write_text("existing configuration\n")
        link = self.home / "config link"
        link.symlink_to(existing)
        for shell in SHELLS:
            for candidate in (existing, link):
                with self.subTest(shell=shell, candidate=candidate):
                    result = self.shell(shell, SOURCE_ENVIRONMENT + '''
em_export_path EM_PATH "$HOME/new config" "$EXISTING" || exit 10
printf '%s\\n' "$EM_PATH"
''', extra_env={"EXISTING": str(candidate)})
                    self.assertEqual(result.stdout, str(candidate) + "\n")
                    self.assertEqual(existing.read_text(), "existing configuration\n")
                    self.assertFalse((self.root / "unexpected").exists())

    def test_path_selection_preserves_and_exports_explicit_values(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
EM_PATH="$HOME/custom absent directory"
em_export_path EM_PATH "$HOME/default" "$HOME" || exit 10
sh -c 'printf "%s\\n" "$EM_PATH"'
''')
                self.assertEqual(result.stdout, str(self.home / "custom absent directory") + "\n")
                self.assertFalse((self.home / "custom absent directory").exists())

    def test_path_selection_rejects_invalid_calls(self):
        for shell in SHELLS:
            for call in ('em_export_path', 'em_export_path EM_PATH',
                         'em_export_path EM_PATH ""', 'em_export_path "BAD; false" /tmp'):
                with self.subTest(shell=shell, call=call):
                    result = self.shell(shell, SOURCE_ENVIRONMENT + call + "\n", check=False)
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(result.stdout, "")

    def test_mkdir_supports_multiple_paths_and_reports_failure(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_ENVIRONMENT + '''
em_mkdir "one with spaces/nested" "two/nested" || exit 10
em_mkdir "one with spaces/nested" || exit 11
printf 'blocker' > blocker
em_mkdir blocker/nested 2>/dev/null
''', check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((self.root / "one with spaces/nested").is_dir())
                self.assertTrue((self.root / "two/nested").is_dir())
                self.assertEqual((self.root / "blocker").read_text(), "blocker")


if __name__ == "__main__":
    unittest.main()
