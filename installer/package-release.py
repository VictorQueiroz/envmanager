"""Package immutable artifacts from a tested Git commit, without local files."""

import hashlib
from pathlib import Path
import subprocess
import sys


destination = Path(sys.argv[1] if len(sys.argv) > 1 else "release-artifacts")
destination.mkdir(parents=True, exist_ok=True)
version = Path("VERSION").read_text().strip()
tag = "v" + version
commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
archive = destination / f"envmanager-{tag}.tar.gz"
archive.write_bytes(subprocess.check_output([
    "git", "archive", "--format=tar.gz", f"--prefix=envmanager-{tag}/", commit,
]))
installer = destination / "install.sh"
installer.write_bytes(subprocess.check_output(["git", "show", commit + ":installer/install.sh"]))
(destination / "envmanager-release.txt").write_text(f"version={tag}\ncommit={commit}\n")
checksums = []
for file in sorted(destination.iterdir()):
    if file.name == "SHA256SUMS":
        continue
    checksums.append(f"{hashlib.sha256(file.read_bytes()).hexdigest()}  {file.name}\n")
(destination / "SHA256SUMS").write_text("".join(checksums))
print(f"Packaged {tag} at {commit} in {destination}")
