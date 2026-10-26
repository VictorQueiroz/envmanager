# Installer and releases

`install.sh` is a standalone POSIX shell entry point for macOS and Linux. It lives
in this subdirectory because the shell loader sources top-level `.sh` files.
Downloading or running the installer does not source application modules.

New installations clone a release tag, verify its commit against the published
manifest, configure the selected shell, and start with a core preset. The preset
enables core initialization, user binary paths, and telemetry preferences. It
disables other recipes through the existing `disabled-scripts` mechanism.
`em_enable`/`em_disable` remain the source of user choices. During upgrades, newly
introduced optional recipe names are disabled in core installations.

Existing recognized checkouts are reused without changing their module choices.
Their custom `~/.envmanagerrc` files are preserved. Managed release checkouts use
explicit `--upgrade`; existing branch checkouts retain fast-forward updates.
Uninstall removes managed shell integration and an unedited managed loader,
and retains the checkout and tool data.

Managed files are replaced atomically after resolving leaf symlinks. Existing
permissions are retained and backups are created only for changed files. An
installer lock prevents concurrent operations. Fresh clones are published by
renaming a prepared staging directory on the destination filesystem; rerunning
repairs missing integration without fetching another release.

## Test

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_installer.py' -v
```

The fixture serves manifests on localhost and clones local Git repositories. No
test installs optional tools or writes to the developer's shell configuration.
`ENVMANAGER_INSTALL_REPOSITORY` and `ENVMANAGER_INSTALL_RELEASE_BASE` are fixture
overrides; public installs use the official GitHub repository and releases.

## Publish

1. Update `VERSION` and the changelog. Validate shell tests and the website build.
2. Commit the complete source and tag that tested commit as `vX.Y.Z`.
3. The `Publish release` workflow tests macOS/Linux before publishing assets.
   It checks that the tag agrees with `VERSION` and archives the tagged commit.
4. Confirm the manifest's commit, release archive checksums, and installer bytes.
5. Deploy the website from the same tested commit and verify the public installer
   against the release asset before testing it in a disposable home.

`package-release.py` produces the source archive, installer, release manifest,
and `SHA256SUMS`. The installer verifies Git commit identity; `SHA256SUMS` also
allows independent verification of downloaded release files. Both GitHub Releases
and the website use the canonical `installer/install.sh`.
