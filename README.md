# envmanager

## Installation

Use the [macOS guide](https://projects.envmanager.victorqueiroz.dev/install/macos/)
or [Linux guide](https://projects.envmanager.victorqueiroz.dev/install/linux/).
The installer needs Git and curl (or wget); end users do not need Node.js or Python.

```sh
curl -fsSL https://projects.envmanager.victorqueiroz.dev/install.sh | sh
```

Inspect [the installer](installer/install.sh), or run it with `--dry-run`, before
installing. New installations use the core preset: environment initialization,
user binary paths, and telemetry preferences. Optional tool recipes are disabled;
`em_enable NAME` opts in for future loads. Some recipes install third-party tools
or clone configuration. Existing installations keep their module choices.

The installer reuses recognized checkouts, preserves custom loaders and symlinked
dotfiles, and maintains managed startup blocks for Bash/Zsh. Repeating an install
is a no-op; missing integration can be repaired. Set `ENVMANAGER_DIR` or use
`--dir /absolute/path` for a custom checkout, and `--shell bash|zsh|both` for an
explicit shell selection. Zsh respects `ZDOTDIR`.

Release installs pin a verified tag/commit and skip daily Git pull updates.
Upgrade explicitly or disconnect managed shell integration:

```sh
curl -fsSL https://projects.envmanager.victorqueiroz.dev/install.sh | sh -s -- --upgrade
curl -fsSL https://projects.envmanager.victorqueiroz.dev/install.sh | sh -s -- --uninstall
```

Uninstall retains the checkout, local overrides, edited loaders, and tool data.
See [installer behavior and release packaging](installer/README.md) for options,
backups, conflict handling, and checksums.

### Manual installation, including Android

```sh
git clone https://github.com/VictorQueiroz/envmanager.git "${XDG_CONFIG_HOME:-$HOME/.config}/envmanager"
cp "${XDG_CONFIG_HOME:-$HOME/.config}/envmanager/envmanagerrc" "$HOME/.envmanagerrc"
```

For an existing manual installation, back up `~/.envmanagerrc` before replacing
it, and preserve local settings before sourcing the loader. Add this to the
appropriate shell startup file:

```sh
. "$HOME/.envmanagerrc"
```

Use `~/.bashrc` or `~/.zshrc` for Bash/Zsh. Android's system shell can source the
loader explicitly or from its own startup file. Android can load a copied checkout
offline without Git or Python. Manual branch installations on desktop OSes keep
the daily fast-forward Git updater; set `ENVMANAGER_AUTO_UPDATE=false` to disable
it. Android auto-updates remain off by default. The public installer targets
macOS/Linux Bash and Zsh; see the Android section below for its runtime policy.

## Startup benchmarks (Zsh)

Interactive Zsh startup reports commands taking more than 200 ms, sorted
slowest first, on stderr at the first prompt. Each row includes the source
file and absolute line number, plus command text truncated to 100 characters.
Tracing stops before interactive commands run. Noninteractive shells are quiet;
Bash and Android's system shell retain their existing startup behavior.

EnvManager starts tracing when its core loads. To also measure plugins and
other commands that run earlier, put this block at the **top** of `~/.zshrc`:

```sh
if [ -r "${ENVMANAGER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/envmanager}/lib/benchmark-zsh.sh" ]; then
  . "${ENVMANAGER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/envmanager}/lib/benchmark-zsh.sh"
  em_benchmark_auto
fi
```

Set these before that block (or export them from the parent shell):

```sh
ENVMANAGER_BENCHMARK_BUDGET_MS=200
ENVMANAGER_BENCHMARK_MAX_COMMAND_LENGTH=100
# ENVMANAGER_BENCHMARK=false  # disable automatic profiling
```

For a bounded manual measurement, source the module and run
`em_benchmark_start 50`, your commands, then `em_benchmark_stop`. A budget of
`0` lists all measured commands. The budget accepts nonnegative whole
milliseconds; the command length accepts 4–99999 characters. Repeated starts
are harmless, and an existing DEBUG trap is preserved by skipping profiling.
The profiler requires the normal Zsh `DEBUG_BEFORE_CMD` option.

Timing uses Zsh's builtin high resolution clock and DEBUG hook, with no clock
process per command. Measurements include tracing overhead. Shell functions,
sourced files, and eval wrappers with traced children are omitted to avoid
overlapping rows. Command substitutions, pipelines, and explicit subshells
are measured as a unit in the parent; commands in those children are not
listed separately. Command text uses Zsh's reconstructed, unexpanded syntax.
The startup total covers the time from starting the profiler to the first
prompt, including work below the threshold; it is not the sum of listed rows.
An interactive `zsh -lic 'command'` has no prompt, so reports at shell exit
instead, including that command. No trace file or command history is written.

## Disable and enable scripts

Run `em_disable sdkman` to skip SDKMAN on future shell loads. Names omit the
numeric prefix and the `.sh`, OS and `.local` suffixes. The blacklist applies to
all variants of a name, so `em_disable gpg` also skips `01-gpg.linux.sh`.

Multiple names are accepted, for example `em_disable sdkman wasi`. Run
`em_disable` without arguments to list disabled names. Disabling a script takes
effect on the next load; it does not undo exports or functions already loaded.

Run `em_enable sdkman wasi` to remove those names from the disabled list. Scripts
run again on the next load; enabling does not immediately execute them or their
installers. Already enabled scripts are left alone. Names still in the disabled
list can be removed even if their scripts no longer exist. Unknown names are
rejected before any changes are written. With no arguments, `em_enable` also
lists disabled names.

The list is saved in `$ENVMANAGER_DIR/disabled-scripts` and ignored by Git. Set
`ENVMANAGER_DISABLED_FILE` before loading envmanager to use another file. Core
helpers cannot be disabled.

Zsh completion suggests names with at least one compatible script:
enabled names for `em_disable`, and disabled names for `em_enable`. OS aliases
and local variants follow the same rules as script loading. Names are suggested
only once even when several variants match.

The disabled list is shared across platforms, and no-argument listings show the
full list. Other-OS names can still be typed explicitly, and `em_enable` can still
remove stale entries whose scripts are gone; those entries are omitted from
completion.

Completion works with the standard `compinit` system whether envmanager loads
before or after it. If your Zsh configuration does not initialize completion,
add `autoload -Uz compinit; compinit` to `~/.zshrc`.

## OS-specific scripts

Unsuffixed scripts run on desktop OSes; Android uses the audited compatibility
policy below. Add an OS suffix immediately before `.sh`
(or before `.local.sh` for a local override):

| Filename | Runs on |
| --- | --- |
| `01-gpg.linux.sh` | Linux |
| `99-example.macos.sh` | macOS |
| `99-example.darwin.sh` | macOS, alias for `.macos.sh` |
| `99-example.linux.local.sh` | Linux, local override |
| `99-example.android.sh` | Android, any runtime |
| `99-example.android.termux.sh` | Android in Termux |
| `99-example.android.system.local.sh` | Android system runtime, local override |

`.freebsd.sh`, `.openbsd.sh`, `.netbsd.sh` and `.windows.sh` are also supported.
Windows detection covers Cygwin, MSYS and MinGW shells. Eligible scripts still
load in filename order, after core helpers.
If a compatible script fails, loading stops and returns its failure status.

## Search paths

Use `em_add_path VARIABLE entry [mode]` to add one entry to `PATH`, `MANPATH`,
`CDPATH`, `PKG_CONFIG_PATH`, or another colon-separated environment variable.
It updates and exports the variable in the current shell:

| Mode | Entry absent | Entry already present |
| --- | --- | --- |
| `append` (default) | Add at the end | Keep its current position |
| `prepend` | Add at the beginning | Keep its current position |
| `prepend-move` | Add at the beginning | Move to the beginning, removing other copies |

```sh
em_add_path PATH "$HOME/bin"
em_add_path MANPATH "$HOME/share/man" prepend
em_add_path PATH "$HOME/preferred/bin" prepend-move
```

Matching uses the complete literal entry, including spaces and glob characters.
Other entries keep their order and existing empty components are preserved
(including leading/trailing colons used by `MANPATH`). An unset or empty variable
starts with just the new entry, except `MANPATH`: its implicit system defaults
are kept before an appended entry (`:/custom/man`) or after a prepended entry
(`/custom/man:`). Paths do not have to exist. Empty entries,
entries containing `:`, invalid variable names, and invalid modes return status 2
without changing the variable. Repeated calls do not add copies of the entry.

## Tool paths

Tool configuration, data, installation and cache providers use
`em_export_path VARIABLE preferred_path [existing_alternatives...]`:

1. Preserve and export a nonempty explicit value, even if the path does not exist.
2. Reuse the preferred path when it exists.
3. Otherwise reuse the first existing alternative.
4. If none exists, export the preferred path for a new installation.

Selection only checks paths; it does not create, copy, merge or move tool data.
Files and symlinks to existing paths are supported as well as directories.
Candidates are literal shell paths and work without OS detection or external
path-resolution tools. Each provider supplies the paths appropriate to its tool;
this does not infer arbitrary operating-system or application conventions.

For example, Codex prefers an existing `$XDG_DATA_HOME/codex`, then an existing
`$HOME/.codex`, and uses the XDG path when neither exists. Its SQLite state stays
with a native/custom Codex home. An XDG Codex home reuses an existing
`$XDG_STATE_HOME/codex`, then its own home directory, before starting a new split
state directory. Explicit `CODEX_SQLITE_HOME` always takes precedence.

Cargo, Gradle, Keras, npm, NVM, pyenv and SDKMAN also check their conventional
home paths before creating a separate XDG installation. Providers without a
conventional alternative retain their existing defaults while preserving explicit
preferences. Set a variable before loading envmanager to select a path explicitly:

```sh
export CODEX_HOME="$HOME/.codex"
. "$HOME/.envmanagerrc"
```

If both paths exist, the preferred XDG path wins; envmanager never merges them.
An inherited variable also counts as explicit. To recalculate Codex paths in an
already configured shell, run `unset CODEX_HOME CODEX_SQLITE_HOME` before sourcing
the loader again. Fresh Termux sessions use Termux's existing `$HOME` directly.

NVM and Node remain available as soon as startup finishes. For a numeric default
with exactly one matching installed modern Node version, startup resolves that
version with shell builtins and lets NVM activate it. An already active Node
version is preserved. Named/LTS aliases, alias chains, ambiguous matches, and
legacy Node layouts use normal NVM initialization. Set
`ENVMANAGER_NVM_FAST_STARTUP=false` before loading envmanager to always use normal
NVM initialization.

On Zsh, EnvManager also backports NVM's builtin `printf` output helper before
automatic activation. It replaces only the recognized legacy helper; custom
and already-fixed helpers are preserved. NVM's original automatic initializer
still selects and activates the version, including named/LTS aliases. Installed
NVM files are left intact. `ENVMANAGER_NVM_FAST_STARTUP=false` disables this
backport too.

OS and runtime detection are cached in memory for each script-loading or
completion pass. Changes to `ENVMANAGER_OS`, `ENVMANAGER_RUNTIME`, `TERMUX_VERSION`
or `PREFIX` invalidate the snapshot immediately. The next pass detects again;
standalone platform queries stay fresh. This cache does not write files or
change the execution/output semantics of `em_run_every`.

## Limit concurrent commands

Prepend `em_run_concurrent N` to allow at most N matching invocations to run
at once across shell sessions. Additional calls wait and start when one slot
opens. `N=1` acts as a mutex. Commands are never skipped.

```sh
# Match the command and every argument, including empty arguments and spaces.
em_run_concurrent 2 -- curl -O https://example.com/archive.tar.gz

# Different commands/arguments share one named limit.
em_run_concurrent --key package-installs 1 -- npm install
em_run_concurrent --key package-installs 1 -- pip install requests
```

Use the same N (1–999999999) for every invocation sharing a key. `--key`
(or `-k`) goes before N; `--` before the command is optional. Without a key,
the command name and exact argument list determine the group. The working
directory, environment, and resolved executable path are not part of that
identity. Explicit keys and automatic command identities are separate groups.

The command receives its original arguments, stdin, stdout, and stderr, and
the prefix returns its exit status. Shell functions and builtins work too.
Execution takes place in a subshell, so changes to variables or the current
directory do not propagate back to the caller. Wrap pipelines or compound
commands in a function or `sh -c '...'` to limit the whole operation. Commands
must wait for their own background work before returning.

State is shared in `${XDG_STATE_HOME:-$HOME/.local/state}/envmanager/concurrent`,
independently of `TMPDIR`. Set `ENVMANAGER_CONCURRENCY_DIR` to an absolute path
to override it; all participating sessions must use the same local directory.
State created by this helper is private and stores hashed identities, process
IDs, and admission tickets, rather than command arguments. SHA-256 requires
`sha256sum` or `shasum`; no Python or platform-specific lock utility is needed.
Importing the module does not create state.

Commands retain their slots until they return, even if the invoking shell is
interrupted or killed. Interrupting the prefix does not cancel its command.
Abandoned waiting requests are removed by subsequent callers. Live process IDs
are treated conservatively, so PID reuse after an unclean shutdown can delay
admission. Do not delete concurrency state while commands are running. Limits
apply on one host; this is not a distributed lock or a limit on commands invoked
without the prefix. Nesting the same key can deadlock when all slots are held.

## Android

Android is an OS, while Termux is an Android runtime. Detection checks Android's
system properties even when `uname` says Linux, then Termux environment markers.
`em_current_os`, `em_current_runtime`, `em_current_arch`, and `em_platform` expose
these separately. `.linux.sh` does not match native Android. Set
`ENVMANAGER_OS=linux ENVMANAGER_RUNTIME=system` explicitly inside a Linux guest
when Android properties or inherited Termux variables would be misleading.
Supported runtime overrides are `system` and `termux`; Termux requires Android.
Architecture aliases such as `arm64` normalize to `aarch64`.

`em_status` explains which files are enabled, user-disabled, or unsupported,
including when a file is both unsupported and user-disabled.
Loading and completion use the same compatibility check. `em_enable` removes a
user choice; it does not make an unsupported installer compatible. Explicit
commands can still manage names for another OS/runtime, including stale entries.

The Termux adapters configure existing Python/uv, pnpm, tmux, Java, and
`termux-open-url`. They do not install packages, clone tool configurations, launch
Android intents, or download desktop binaries. Install required tools yourself
through your Android runtime's package manager. uv defaults to
`UV_PYTHON_DOWNLOADS=never` to avoid managed desktop Python downloads. Existing
`JAVA_HOME`, `BROWSER`, and other nonempty preferences are preserved.
NVM, SDKMAN, WASI, Emscripten, Doppler and Cursor desktop providers are skipped on
Android until a compatible provider is supplied; Node installed by Termux works
without NVM. Other shared configuration scripts run only after being audited in
`em_script_unsupported_reason`. New Android scripts should carry an explicit
Android suffix and use syntax supported by their intended shell.

The shared core and audited configuration scripts support Android's system mksh
without Bash, Zsh, Git, Python, systemd, or network access. Zsh completions and
Bash/Zsh lazy loading are optional shell integrations. Desktop editor/tmpdir
scripts require Bash/Zsh in Termux. Native Android support currently covers this
core/configuration layer, not a package manager or root/system provisioning.

Set a writable absolute `TMPDIR`, or a writable `HOME`; Termux otherwise uses
`$PREFIX/tmp`. Android never falls back to `/tmp`. XDG defaults are initialized
before providers run. Keep the checkout and writable state in storage accessible
to the calling app UID. No root access is needed or requested by Android support.

## Core modules

`00-core.sh` is the startup entry point. It loads the modules below and calls
`em_init` to configure defaults, install shell fallbacks, and register completions.
Existing `em_*` functions remain available to the numbered scripts.

| Module | Responsibility |
| --- | --- |
| `lib/platform.sh` | OS, runtime, and architecture detection and overrides |
| `lib/environment.sh` | Directory creation, variable lookup, fallback selection, search paths, exports, environment defaults |
| `lib/scripts.sh` | Script discovery, name and OS normalization, disabled scripts, loading |
| `lib/run-every.sh` | Duration parsing, clock access, hashing, expiration checks, throttled execution |
| `lib/run-concurrent.sh` | Cross-session command concurrency, keyed or based on exact arguments |
| `lib/shell.sh` | Portable logging, optional shell integration, initialization |
| `lib/shell-zsh.sh` | Zsh-only completion syntax, loaded only by Zsh |

Sourcing a module only defines functions. It does not create directories, change
environment defaults, install fallbacks, or register hooks. Tests can source an
individual module and call its decision helpers directly. Functions that perform
actions use the other modules as documented at the top of each file.

`em_first_nonempty` selects a value; `em_export_alternatives` applies it to the
current shell. `em_export_path` applies the path selection policy above without
changing the generic string fallback behavior. `em_add_path` manages entries in
colon-separated search paths using the policy above. `em_normalize_os` accepts an OS
name; `em_current_os` queries the host. `em_expiry_pending` accepts the current time and an expiration;
`em_run_every` reads state and executes commands. `em_now` wraps `date +%s` and
can be redefined by a test to provide a fixed clock.

Logging is disabled by default. With `ENVMANAGER_ENABLE_LOGGING=true`, startup
and helper messages omit environment dumps, exported values, and command arguments.
`ENVMANAGER_LOG_BACKEND=auto` uses systemd-cat when available, otherwise stderr.
Choose `stderr`, `systemd`, or `file` explicitly. The file backend requires an
absolute `ENVMANAGER_LOG_FILE`; newly created log files/directories are private.
For example, set `ENVMANAGER_LOG_FILE="$XDG_STATE_HOME/envmanager/startup.log"`
after setting your XDG paths. Logging remains off unless explicitly enabled.

## Tests

Run `python3 -m unittest discover -s tests -v`. Tests use temporary repositories
and the available Bash and Zsh executables. OS names are simulated to check
filtering without running installers or fetching updates. Python 3.9 or newer
is required. Install both shells to exercise both implementations locally.

The suite covers module imports, initialization, environment exports, script
selection and disabled scripts, completion hooks, lazy loading, throttling, and
concurrent commands across shell processes. Throttling tests use fixed times;
concurrency tests coordinate real processes with explicit release signals. Tests inspect exports
and loaded functions in the shell process that performs the operation.

The GitHub Actions workflow runs the suite with both shells on native Linux and
macOS runners, and requires both shell executables to be present.

The Linux CI job also runs `mksh tests/android-system-smoke.sh "$PWD"` with a
writable `TMPDIR`. On Android, set `TMPDIR` to an app-private directory, then run:

```sh
PATH=/system/bin /system/bin/sh tests/android-system-smoke.sh /absolute/checkout
```

 This checks loading, caller exports/functions, eligibility,
enable/disable persistence, throttling, concurrency and file logging without desktop tooling.
Desktop mksh checks syntax/behavior; testing `/system/bin/sh` on a real device
provides the native Android evidence.
