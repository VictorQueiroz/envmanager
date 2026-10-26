"""Run native shells against a disposable envmanager installation."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[1]
SHELLS = [shell for shell in ("bash", "zsh") if shutil.which(shell)]
MODULES = ("platform", "environment", "scripts", "run-every", "run-concurrent", "shell")
SOURCE_MODULES = "\n".join(
    f'source "$ENVMANAGER_DIR/lib/{name}.sh" || exit $?' for name in MODULES
)
SOURCE_CORE = 'source "$ENVMANAGER_DIR/00-core.sh" || exit $?\n'


class ShellTestCase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        if not SHELLS:
            raise RuntimeError("Tests require Bash or Zsh on PATH")

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="envmanager tests ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / "home with spaces"
        self.repo = self.home / ".config" / "envmanager"
        self.repo.mkdir(parents=True)
        shutil.copy2(PROJECT / "00-core.sh", self.repo)
        shutil.copy2(PROJECT / "envmanagerrc", self.repo)
        shutil.copy2(PROJECT / "VERSION", self.repo)
        for directory in ("lib", "completions"):
            if (PROJECT / directory).is_dir():
                shutil.copytree(PROJECT / directory, self.repo / directory)
        # OS fixtures must not see the host phone's real Android properties.
        # Detection tests replace this probe explicitly; device smoke tests use
        # the unmodified production module.
        platform = self.repo / "lib/platform.sh"
        platform.write_text(platform.read_text() + "\nem_android_sdk() { return 1; }\n")
        self.log = self.root / "calls"
        self.environment = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "TMPDIR": str(self.root / "tmp"),
            "ENVMANAGER_DIR": str(self.repo),
            "ENVMANAGER_ENABLE_LOGGING": "false",
            "TEST_LOG": str(self.log),
            "LC_ALL": "C",
        }

    def shell(self, shell, code, *, check=True, extra_env=None):
        arguments = [shutil.which(shell)]
        arguments += ["-f"] if shell == "zsh" else ["--noprofile", "--norc"]
        result = subprocess.run(
            arguments + ["-c", code], text=True, capture_output=True,
            env=self.environment | (extra_env or {}), cwd=self.root, timeout=15,
        )
        if check:
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
        return result

    def state_directory(self, shell):
        return self.root / f"{shell}-tmp" / "envmanager" / "run-every"
