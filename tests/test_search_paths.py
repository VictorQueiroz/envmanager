"""Search path additions preserve ordering, literal entries and caller exports."""

import shutil
import unittest

from helpers import PROJECT, SHELLS, SOURCE_MODULES, ShellTestCase


class SearchPathTests(ShellTestCase):
    def test_modes_and_existing_positions(self):
        cases = (
            (None, "/first:/last", "/new", "/first:/last:/new"),
            ("append", "/first:/last", "/new", "/first:/last:/new"),
            ("prepend", "/first:/last", "/new", "/new:/first:/last"),
            ("prepend-move", "/first:/last", "/new", "/new:/first:/last"),
        )
        for mode in (None, "append", "prepend", "prepend-move"):
            for initial in ("/entry:/last", "/first:/entry:/last", "/first:/entry",
                            "/entry", "/entry:/first:/entry:/entry"):
                expected = initial
                if mode == "prepend-move":
                    expected = ":".join(["/entry"] + [part for part in initial.split(":")
                                                      if part != "/entry"])
                cases += ((mode, initial, "/entry", expected),)
        for shell in SHELLS:
            for mode, initial, entry, expected in cases:
                with self.subTest(shell=shell, mode=mode, initial=initial):
                    argument = "" if mode is None else " " + mode
                    result = self.shell(shell, SOURCE_MODULES + '''
em_add_path EM_SEARCH_PATH "$ENTRY"''' + argument + ''' || exit 10
em_add_path EM_SEARCH_PATH "$ENTRY"''' + argument + ''' || exit 11
printf '%s\n' "$EM_SEARCH_PATH"
sh -c 'printf "%s\\n" "$EM_SEARCH_PATH"'
''', extra_env={"EM_SEARCH_PATH": initial, "ENTRY": entry})
                    self.assertEqual(result.stdout, f"{expected}\n{expected}\n")

    def test_unset_and_empty_lists_start_with_one_entry(self):
        for shell in SHELLS:
            for mode in ("append", "prepend", "prepend-move"):
                for setup in ("unset EM_SEARCH_PATH", 'EM_SEARCH_PATH=""'):
                    with self.subTest(shell=shell, mode=mode, setup=setup):
                        result = self.shell(shell, SOURCE_MODULES + setup + '''
set -eu
em_add_path EM_SEARCH_PATH '/not installed yet/bin' ''' + mode + '''
printf '%s\n' "$EM_SEARCH_PATH"
sh -c 'printf "%s\\n" "$EM_SEARCH_PATH"'
''')
                        self.assertEqual(result.stdout, "/not installed yet/bin\n" * 2)

    def test_unset_and_empty_manpath_preserve_system_defaults(self):
        for shell in SHELLS:
            for mode in (None, "append", "prepend", "prepend-move"):
                for setup in ("unset MANPATH", 'MANPATH=""'):
                    with self.subTest(shell=shell, mode=mode, setup=setup):
                        argument = "" if mode is None else " " + mode
                        expected = ":/custom/man" if mode in (None, "append") else "/custom/man:"
                        result = self.shell(shell, SOURCE_MODULES + setup + '''
set -eu
em_add_path MANPATH /custom/man''' + argument + '''
em_add_path MANPATH /custom/man''' + argument + '''
printf '%s\n' "$MANPATH"
sh -c 'printf "%s\\n" "$MANPATH"'
''')
                        self.assertEqual(result.stdout, f"{expected}\n{expected}\n")

    def test_empty_components_are_preserved(self):
        cases = (
            ("append", ":/other::", ":/other:::/entry"),
            ("prepend", ":/other::", "/entry::/other::"),
            ("prepend-move", ":/other::", "/entry::/other::"),
            ("append", ":/entry::/other:/entry:", ":/entry::/other:/entry:"),
            ("prepend", ":/entry::/other:/entry:", ":/entry::/other:/entry:"),
            ("prepend-move", ":/entry::/other:/entry:", "/entry:::/other:"),
        )
        for shell in SHELLS:
            for mode, initial, expected in cases:
                with self.subTest(shell=shell, mode=mode, initial=initial):
                    result = self.shell(shell, SOURCE_MODULES + '''
em_add_path MANPATH /entry "$MODE" || exit 10
printf '%s\n' "$MANPATH"
''', extra_env={"MANPATH": initial, "MODE": mode})
                    self.assertEqual(result.stdout, expected + "\n")

    def test_entries_are_literal_and_matched_as_whole_components(self):
        for shell in SHELLS:
            for entry in ('/bin', '/a [glob]*? "quoted" $(touch unexpected)',
                          r'/back\slash', '/line\nbreak\n'):
                for initial in (entry + "-other", "/first:" + entry + ":/last"):
                    for mode in ("append", "prepend", "prepend-move"):
                        with self.subTest(shell=shell, entry=entry, initial=initial, mode=mode):
                            result = self.shell(shell, SOURCE_MODULES + '''
em_add_path EM_SEARCH_PATH "$ENTRY" "$MODE" || exit 10
printf '%s\n' "$EM_SEARCH_PATH"
''', extra_env={"EM_SEARCH_PATH": initial, "ENTRY": entry, "MODE": mode})
                            parts = initial.split(":")
                            if entry in parts and mode != "prepend-move":
                                expected = initial
                            elif mode == "append":
                                expected = initial + ":" + entry
                            else:
                                expected = ":".join([entry] + [part for part in parts if part != entry])
                            self.assertEqual(result.stdout, expected + "\n")
                            self.assertFalse((self.root / "unexpected").exists())

    def test_generic_variables_and_child_exports(self):
        for shell in SHELLS:
            for name in ("PATH", "MANPATH", "CDPATH", "INFOPATH", "FPATH",
                         "PKG_CONFIG_PATH", "LD_LIBRARY_PATH", "var_name"):
                for existing in (False, True):
                    with self.subTest(shell=shell, name=name, existing=existing):
                        initial = "/first:/entry:/last" if existing else "/first:/last"
                        expected = initial if existing else initial + ":/entry"
                        result = self.shell(shell, SOURCE_MODULES + f'''
{name}='{initial}'
em_add_path {name} /entry || exit 10
printf '%s\\n' "${name}"
"$CHILD_SHELL" -c 'printf "%s\\n" "${name}"'
''', extra_env={"CHILD_SHELL": shutil.which("sh")})
                        self.assertEqual(result.stdout, f"{expected}\n{expected}\n")

    def test_invalid_calls_leave_the_variable_unchanged(self):
        calls = (
            "em_add_path", "em_add_path EM_SEARCH_PATH", 'em_add_path EM_SEARCH_PATH ""',
            "em_add_path EM_SEARCH_PATH /one:/two", "em_add_path EM_SEARCH_PATH /entry unknown",
            'em_add_path EM_SEARCH_PATH /entry ""', "em_add_path EM_SEARCH_PATH /entry append extra",
            'em_add_path "" /entry', 'em_add_path "1INVALID" /entry',
            'em_add_path "BAD; touch unexpected" /entry', 'em_add_path "BAD[0]" /entry',
        )
        for shell in SHELLS:
            for call in calls:
                with self.subTest(shell=shell, call=call):
                    result = self.shell(shell, SOURCE_MODULES + '''
set -eu
EM_SEARCH_PATH=/unchanged
if ''' + call + '''; then exit 10; else [ "$?" -eq 2 ] || exit 11; fi
printf '%s\n' "$EM_SEARCH_PATH"
sh -c 'printf "%s\\n" "${EM_SEARCH_PATH+exported}"'
''')
                    self.assertEqual(result.stdout, "/unchanged\n\n")
                    self.assertFalse((self.root / "unexpected").exists())

    def test_providers_can_be_loaded_repeatedly_without_duplicates(self):
        filenames = ("10-home-bin-folders.sh", "10-homebrew.macos.sh", "99-rust.sh",
                     "99-doppler.sh", "99-pnpm.sh", "99-pnpm.android.termux.sh")
        for filename in filenames:
            shutil.copy2(PROJECT / filename, self.repo)
        for shell in SHELLS:
            with self.subTest(shell=shell):
                result = self.shell(shell, SOURCE_MODULES + '''
XDG_DATA_HOME="$HOME/.local/share"
DOPPLER_INSTALL_DIR="$HOME/doppler"
PNPM_HOME="$HOME/pnpm"
mkdir -p "$DOPPLER_INSTALL_DIR" "$PNPM_HOME/bin"
touch "$DOPPLER_INSTALL_DIR/doppler" "$PNPM_HOME/bin/pnpm"
chmod +x "$PNPM_HOME/bin/pnpm"
for iteration in 1 2; do
  for script in 10-home-bin-folders.sh 10-homebrew.macos.sh 99-rust.sh 99-doppler.sh 99-pnpm.sh 99-pnpm.android.termux.sh; do
    source "$ENVMANAGER_DIR/$script" || exit 10
  done
  printf '%s\n' "$PATH"
done
''')
                first, second = result.stdout.splitlines()
                self.assertEqual(first, second)
                expected = [str(self.home / "pnpm/bin"), str(self.home / "doppler"),
                            "/opt/homebrew/sbin", "/opt/homebrew/bin"]
                expected += self.environment["PATH"].split(":")
                expected += [str(self.home / "bin"), str(self.home / ".local/bin"),
                             str(self.home / ".local/share/cargo/bin")]
                # Homebrew entries may already be present in the host PATH.
                expected = expected[:4] + [part for part in expected[4:]
                                          if part not in expected[:4]]
                self.assertEqual(first.split(":"), expected)


if __name__ == "__main__":
    unittest.main()
