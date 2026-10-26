EnvManager v0.1.1 fixes migration of existing Bash/Zsh startup hooks, including `source "$HOME"/.envmanagerrc`. It adopts the original hook at its existing position and repairs v0.1.0 configurations containing both a legacy hook and an appended managed block.

Dry runs and actual migration share a read-only planner. The installer reports the selected startup file, line, and action; it stops before edits on ambiguous active references, multiple legacy hooks, conflicting markers, and edited managed blocks. No configuration is evaluated during planning.

Regression fixtures check one loader invocation, preserved ordering, and repeated-install stability in Bash and Zsh. The current installer can repair shell integration without updating the existing checkout. Use `--upgrade` separately when checkout updates are intended.

Existing installations retain their module selections and local overrides. Release checkouts pin the published Git commit and skip the daily Git pull updater. Optional tool modules require an explicit choice and can install third-party software when loaded.

Installation guides: https://projects.envmanager.victorqueiroz.dev/install/macos/ and https://projects.envmanager.victorqueiroz.dev/install/linux/

The attached `envmanager-release.txt` records the release tag and commit. `SHA256SUMS` covers the installer, manifest, and source archive. The installer checks that the downloaded Git tag matches the manifest's commit.

Validation covers the shell test suite and installer fixtures on macOS and Linux, the website build and SEO/link checks, and mksh compatibility on Linux. Native Android device execution is not part of this release's installer scope.
