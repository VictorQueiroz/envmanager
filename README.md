# envmanager

## Installation

### 1. Install the checkout and loader

```sh
git clone https://github.com/VictorQueiroz/envmanager.git "${XDG_CONFIG_HOME:-$HOME/.config}/envmanager"
cp "${XDG_CONFIG_HOME:-$HOME/.config}/envmanager/envmanagerrc" "$HOME/.envmanagerrc"
```

For an existing installation, back up `~/.envmanagerrc`, update the checkout,
and copy the versioned `envmanagerrc` over the old loader. Preserve any local
settings before the loader is sourced. `ENVMANAGER_DIR` can select another checkout.

### 2. Source it from your shell configuration

```sh
. "$HOME/.envmanagerrc"
```

Use `~/.bashrc` or `~/.zshrc` for Bash/Zsh. For Android's system shell, source the
loader explicitly or from your own shell's startup file. An existing checkout
starts offline without Git or Python. Desktop auto-updates use a daily
`git pull --ff-only`; Android auto-updates are off by default. Set
`ENVMANAGER_AUTO_UPDATE=false` to disable them on any OS, or `true` to opt in.
A first clone needs Git and network access; Android users can instead copy the
checkout and loader into an app-private writable directory.

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
| `lib/environment.sh` | Directory creation, variable lookup, fallback selection, exports, environment defaults |
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
changing the generic string fallback behavior. `em_normalize_os` accepts an OS
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
