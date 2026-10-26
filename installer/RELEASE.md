EnvManager's first public installer release adds repeatable macOS/Linux installation for Bash and Zsh, with a core preset, managed startup blocks, explicit upgrades, and removal of managed integration.

Existing installations retain their module selections and local overrides. Release checkouts pin the published Git commit and skip the daily Git pull updater. Optional tool modules require an explicit choice and can install third-party software when loaded.

Installation guides: https://projects.envmanager.victorqueiroz.dev/install/macos/ and https://projects.envmanager.victorqueiroz.dev/install/linux/

The attached `envmanager-release.txt` records the release tag and commit. `SHA256SUMS` covers the installer, manifest, and source archive. The installer checks that the downloaded Git tag matches the manifest's commit.

Validation covers the shell test suite and installer fixtures on macOS and Linux, the website build and SEO/link checks, and mksh compatibility on Linux. Native Android device execution is not part of this release's installer scope.
