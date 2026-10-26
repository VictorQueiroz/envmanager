"""The Zsh printf backport must preserve NVM's output and initialization."""

import shutil

from helpers import PROJECT, SHELLS, SOURCE_CORE, ShellTestCase


SOURCE_NVM = SOURCE_CORE + '\nsource "$ENVMANAGER_DIR/99-nvm.sh"\n'
LEGACY_ECHO = r'nvm_echo() { command printf %s\\n "$*" 2>/dev/null; }'


class NvmPrintfTests(ShellTestCase):
    def setUp(self):
        super().setUp()
        shutil.copy2(PROJECT / "99-nvm.sh", self.repo)
        self.nvm = self.home / ".nvm"
        self.nvm.mkdir()
        (self.nvm / "nvm.sh").write_text("return 0\n")

    def test_known_legacy_helper_uses_builtin_only_in_zsh(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_NVM + LEGACY_ECHO + '''
original="$(typeset -f nvm_echo)"
em_nvm_enable_builtin_printf
if [ -n "$ZSH_VERSION" ]; then
  case "$(typeset -f nvm_echo)" in *'builtin printf'*) ;; *) exit 10 ;; esac
else
  [ "$(typeset -f nvm_echo)" = "$original" ] || exit 11
fi
if typeset -f em_nvm_legacy_echo >/dev/null; then exit 12; fi
nvm_echo ready
''')
                self.assertEqual(result.stdout, "ready\n")

    def test_output_is_identical_including_empty_arguments_and_newlines(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_NVM + LEGACY_ECHO + r'''
nvm_echo
nvm_echo '' '-n' '%s' 'literal\n' 'ação'
IFS=:
nvm_echo alpha '' beta
IFS='
'
nvm_echo 'first
second' third
unset IFS
em_nvm_enable_builtin_printf
nvm_echo
nvm_echo '' '-n' '%s' 'literal\n' 'ação'
IFS=:
nvm_echo alpha '' beta
IFS='
'
nvm_echo 'first
second' third
''')
                expected = "\n -n %s literal\\n ação\nalpha::beta\nfirst\nsecond\nthird\n"
                self.assertEqual(result.stdout, expected * 2)

    def test_closed_stdout_preserves_the_existing_exit_status(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                self.shell(shell, SOURCE_NVM + LEGACY_ECHO + '''
if (nvm_echo value >&-); then before=0; else before=$?; fi
em_nvm_enable_builtin_printf
if (nvm_echo value >&-); then after=0; else after=$?; fi
[ "$after" = "$before" ] || exit 10
''')

    def test_backport_preserves_caller_file_descriptors(self):
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_NVM + LEGACY_ECHO + '''
exec 3> "$TEST_LOG"
em_nvm_enable_builtin_printf
nvm_echo ready
printf 'descriptor preserved\\n' >&3
exec 3>&-
''')
                self.assertEqual(result.stdout, "ready\n")
                self.assertEqual(self.log.read_text(), "descriptor preserved\n")

    def test_custom_and_already_fixed_helpers_and_missing_helpers_are_preserved(self):
        for shell in SHELLS:
            for implementation in (
                'nvm_echo() { printf "custom:%s\\\\n" "$*"; }',
                'nvm_echo() { builtin printf "%s\\\\n" "$*" 2>/dev/null; }',
            ):
                with self.subTest(shell=shell, implementation=implementation):
                    self.shell(shell, SOURCE_NVM + implementation + '''
before="$(typeset -f nvm_echo)"
em_nvm_enable_builtin_printf
[ "$(typeset -f nvm_echo)" = "$before" ] || exit 10
unset -f nvm_echo
em_nvm_enable_builtin_printf
if typeset -f nvm_echo >/dev/null; then exit 11; fi
''')

    def test_original_automatic_initializer_runs_exactly_once(self):
        (self.nvm / "nvm.sh").write_text('''
printf 'source:%s\\n' "$*" >> "$TEST_LOG"
''' + LEGACY_ECHO + '''
nvm_process_parameters() {
  printf 'init:%s\\n' "$*" >> "$TEST_LOG"
  [ "$1" != --no-use ] || return 0
  nvm_echo selected
}
nvm_process_parameters "$@"
''')
        for shell in SHELLS:
            for enabled in ("true", "false"):
                with self.subTest(shell=shell, enabled=enabled):
                    if self.log.exists():
                        self.log.unlink()
                    result = self.shell(shell, SOURCE_NVM, extra_env={
                        "ENVMANAGER_NVM_FAST_STARTUP": enabled,
                    })
                    self.assertEqual(result.stdout, "selected\n")
                    expected = (["source:--no-use", "init:--no-use", "init:"]
                                if shell == "zsh" and enabled == "true"
                                else ["source:", "init:"])
                    self.assertEqual(self.log.read_text().splitlines(), expected)

    def test_unrecognized_loader_is_sourced_normally_once(self):
        (self.nvm / "nvm.sh").write_text('printf "source:%s\\\\n" "$*" >> "$TEST_LOG"\n')
        for shell in SHELLS:
            with self.subTest(shell=shell):
                if self.log.exists():
                    self.log.unlink()
                self.shell(shell, SOURCE_NVM)
                self.assertEqual(self.log.read_text().splitlines(), ["source:"])
