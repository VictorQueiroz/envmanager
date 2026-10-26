"""Exercise the real POSIX installer with local Git releases and disposable homes."""

import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

from helpers import PROJECT, SHELLS


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *arguments):
        pass


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="envmanager installer ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home's space"
        self.home.mkdir()
        self.repo = self.root / "release source"
        self.repo.mkdir()
        for name in ("00-core.sh", "envmanagerrc", ".gitignore", "VERSION",
                     "01-disable-telemetry.sh", "10-home-bin-folders.sh"):
            shutil.copy2(PROJECT / name, self.repo)
        shutil.copytree(PROJECT / "lib", self.repo / "lib", ignore=shutil.ignore_patterns("*.zwc"))
        (self.repo / "99-optional.sh").write_text("return 91\n")
        self.git("init", "-q")
        self.git("config", "user.name", "EnvManager Tests")
        self.git("config", "user.email", "tests@example.invalid")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture release")
        self.git("tag", "v1.0.0")
        self.public = self.root / "public"
        self.public.mkdir()
        self.release("v1.0.0")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0),
            functools.partial(QuietHandler, directory=str(self.public)))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.stop_server)
        self.environment = {
            "PATH": os.environ["PATH"], "HOME": str(self.home), "SHELL": shutil.which("bash"),
            "TMPDIR": str(self.root), "LC_ALL": "C", "ENVMANAGER_ENABLE_LOGGING": "false",
            "ENVMANAGER_INSTALL_REPOSITORY": self.repo.as_uri(),
            "ENVMANAGER_INSTALL_RELEASE_BASE": f"http://127.0.0.1:{self.server.server_port}",
        }
        self.installation = self.home / ".config/envmanager"

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def git(self, *arguments):
        return subprocess.check_output(["git", "-C", str(self.repo), *arguments], text=True).strip()

    def release(self, tag):
        commit = self.git("rev-parse", tag + "^{commit}")
        for relative in (f"download/{tag}", "latest/download"):
            target = self.public / relative
            target.mkdir(parents=True, exist_ok=True)
            (target / "envmanager-release.txt").write_text(f"version={tag}\ncommit={commit}\n")

    def install(self, *arguments, check=True, extra_env=None):
        result = subprocess.run(["sh", str(PROJECT / "installer/install.sh"), *arguments],
            env=self.environment | (extra_env or {}), cwd=self.root, text=True,
            capture_output=True, timeout=20)
        if check:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def snapshot(self):
        return {str(path.relative_to(self.home)): (path.read_bytes(), path.stat().st_mtime_ns)
                for path in self.home.rglob("*") if path.is_file() and ".git" not in path.parts}

    def test_fresh_core_install_and_repeated_install_are_identical(self):
        self.install("--shell", "both")
        before = self.snapshot()
        self.install("--shell", "both")
        self.assertEqual(self.snapshot(), before)
        disabled = (self.installation / "disabled-scripts").read_text().splitlines()
        self.assertIn("optional", disabled)
        self.assertNotIn("home-bin-folders", disabled)
        for shell in SHELLS:
            flags = ["-f"] if shell == "zsh" else ["--noprofile", "--norc"]
            rc = '. "$HOME/.zshrc"' if shell == "zsh" else '. "$HOME/.bash_profile"; . "$HOME/.bashrc"'
            (self.installation / "00-counter.local.sh").write_text('EM_COUNT=$((${EM_COUNT:-0}+1))\n')
            result = subprocess.run([shutil.which(shell), *flags, "-c", rc + '''
printf '%s\n' "$ENVMANAGER_DIR" "$EM_COUNT"
git() { exit 92; }
ENVMANAGER_AUTO_UPDATE=true
. "$ENVMANAGER_DIR/envmanagerrc" || exit 93
'''], env=self.environment, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), [str(self.installation), "1"])

    def test_symlinked_configuration_permissions_and_zdotdir(self):
        dotdir = self.home / "zsh config"
        dotdir.mkdir()
        target = self.home / "dotfile"
        target.write_text("# keep this\n")
        target.chmod(0o640)
        (dotdir / ".zshrc").symlink_to(target)
        self.install("--shell", "zsh", extra_env={"ZDOTDIR": str(dotdir)})
        self.assertTrue((dotdir / ".zshrc").is_symlink())
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)
        self.assertIn("# keep this", target.read_text())
        before = self.snapshot()
        self.install("--shell", "zsh", extra_env={"ZDOTDIR": str(dotdir)})
        self.assertEqual(before, self.snapshot())

    def test_existing_install_and_custom_loader_are_preserved(self):
        self.installation.parent.mkdir(parents=True)
        subprocess.run(["git", "clone", "-q", self.repo.as_uri(), str(self.installation)], check=True)
        (self.installation / "disabled-scripts").write_text("optional\n")
        loader = self.home / ".envmanagerrc"
        loader.write_text('# custom settings\nCUSTOM=kept\n. "' + str(self.installation) + '/envmanagerrc"\n')
        original = loader.read_bytes()
        (self.home / ".bashrc").write_text('source "$HOME/.envmanagerrc"\n')
        self.install("--shell", "bash")
        self.assertEqual(loader.read_bytes(), original)
        self.assertEqual((self.installation / "disabled-scripts").read_text(), "optional\n")
        self.assertFalse((self.installation / ".envmanager-release").exists())
        self.assertEqual((self.home / ".bashrc").read_text().count("# >>> EnvManager >>>"), 1)

    def test_upgrade_preserves_choices_and_disables_new_optional_modules(self):
        self.install("--shell", "bash")
        (self.installation / "disabled-scripts").write_text("")  # user enabled optional
        (self.installation / "00-user.local.sh").write_text("# preserved\n")
        (self.repo / "98-new-tool.sh").write_text("return 94\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Next fixture release")
        self.git("tag", "-a", "v1.0.1", "-m", "Annotated release")
        self.release("v1.0.1")
        self.install("--upgrade", "--shell", "bash")
        disabled = (self.installation / "disabled-scripts").read_text().splitlines()
        self.assertNotIn("optional", disabled)
        self.assertIn("new-tool", disabled)
        self.assertEqual((self.installation / "00-user.local.sh").read_text(), "# preserved\n")
        self.assertIn("version=v1.0.1", (self.installation / ".envmanager-release").read_text())
        self.install("--upgrade", "--shell", "bash")
        self.assertEqual((self.installation / "disabled-scripts").read_text().splitlines(), disabled)

    def test_dirty_upgrade_is_reported_without_modifying_checkout(self):
        self.install("--shell", "bash")
        edited = self.installation / "envmanagerrc"
        edited.write_text(edited.read_text() + "# user edit\n")
        before = self.snapshot()
        result = self.install("--upgrade", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local changes", result.stderr)
        self.assertEqual(before, self.snapshot())

    def test_invalid_release_commit_is_not_installed(self):
        (self.public / "latest/download/envmanager-release.txt").write_text(
            "version=v1.0.0\ncommit=" + "0" * 40 + "\n")
        result = self.install(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)
        self.assertFalse(self.installation.exists())
        self.assertFalse((self.home / ".bashrc").exists())
        self.assertFalse(list(self.installation.parent.glob("*.install.*")))

    def test_dry_run_writes_nothing_and_unrelated_directory_is_rejected(self):
        self.install("--dry-run")
        self.assertEqual(list(self.home.iterdir()), [])
        self.installation.mkdir(parents=True)
        (self.installation / "valuable").write_text("keep\n")
        result = self.install(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.installation / "valuable").read_text(), "keep\n")

    def test_uninstall_retains_checkout_and_edited_loader(self):
        self.install("--shell", "both")
        loader = self.home / ".envmanagerrc"
        loader.write_text(loader.read_text() + "# user addition\n")
        original = loader.read_bytes()
        self.install("--uninstall")
        self.assertEqual(loader.read_bytes(), original)
        self.assertTrue(self.installation.is_dir())
        for name in (".bashrc", ".bash_profile", ".zshrc"):
            self.assertNotIn("# >>> EnvManager >>>", (self.home / name).read_text())
        before = self.snapshot()
        self.install("--uninstall")
        self.assertEqual(before, self.snapshot())

    def test_missing_integration_is_repaired_without_reinstalling_release(self):
        self.install("--shell", "bash")
        (self.home / ".envmanagerrc").unlink()
        self.server.shutdown()
        self.install("--shell", "bash")  # no release lookup on a repeat install
        self.assertTrue((self.home / ".envmanagerrc").exists())

    def test_interrupted_clone_is_cleaned_and_can_be_retried(self):
        binaries = self.root / "fake bin"
        binaries.mkdir()
        git = binaries / "git"
        git.write_text('''#!/bin/sh
if [ "$1" = clone ]; then
  for last do :; done
  mkdir -p "$last/partial"
  exit 1
fi
exit 95
''')
        git.chmod(0o700)
        result = self.install(check=False, extra_env={"PATH": str(binaries) + ":" + os.environ["PATH"]})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.installation.exists())
        self.assertFalse(list(self.installation.parent.glob("*.install.*")))
        self.install("--shell", "bash")
        self.assertTrue((self.home / ".bashrc").exists())

    def test_live_lock_is_preserved_and_stale_lock_is_recovered(self):
        lock = self.home / ".local/state/envmanager/install.lock"
        lock.mkdir(parents=True)
        (lock / "pid").write_text(str(os.getpid()) + "\n")
        result = self.install(check=False)
        self.assertIn("another installer", result.stderr)
        self.assertEqual((lock / "pid").read_text(), str(os.getpid()) + "\n")
        (lock / "pid").write_text("999999999\n")
        self.install("--shell", "bash")
        self.assertFalse(lock.exists())

    def test_unmatched_markers_do_not_discard_configuration(self):
        rc = self.home / ".bashrc"
        rc.write_text("# >>> EnvManager >>>\n# valuable configuration\n")
        original = rc.read_bytes()
        result = self.install("--shell", "bash", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(rc.read_bytes(), original)
        self.assertIn("conflicting managed markers", result.stderr)

    def test_full_profile_is_an_explicit_fresh_install_choice(self):
        self.install("--profile", "full", "--shell", "bash")
        self.assertFalse((self.installation / "disabled-scripts").exists())
        self.assertIn("profile=full", (self.installation / ".envmanager-release").read_text())


if __name__ == "__main__":
    unittest.main()
