# envmanager

## Installation

### 1. Create `"$HOME"/.envmanagerrc`

```sh
#!/bin/bash

envmanager_load() {
  local envmanager_repo_url
  envmanager_repo_url="https://github.com/VictorQueiroz/envmanager.git"

  local home_dir
  home_dir="$HOME"

  if [[ ! -d "$home_dir" ]]; then
    return 1
  fi

  local envmanager_root_directory
  envmanager_root_directory="${XDG_CONFIG_HOME:-$home_dir/.config}"
  ENVMANAGER_DIR="$envmanager_root_directory"/envmanager

  if [[ ! -d "$ENVMANAGER_DIR" ]]; then
    command mkdir -p "$envmanager_root_directory" || return
    git clone "$envmanager_repo_url" "$ENVMANAGER_DIR" || return
  fi

  source "$ENVMANAGER_DIR/00-core.sh" || return
  em_load_scripts

  # Update the repository every 1 day
  em_run_every 1d git -C "$ENVMANAGER_DIR" pull
}

envmanager_load
unset -f envmanager_load
```

### 2. Source it from your `~/.bashrc` or `~/.zshrc`

```sh
source "$HOME"/.envmanagerrc
```

For an existing installation, update `~/.envmanagerrc` to the loader above to
enable blacklist and OS filtering.

## Disable scripts

Run `em_disable sdkman` to skip SDKMAN on future shell loads. Names omit the
numeric prefix and the `.sh`, OS and `.local` suffixes. The blacklist applies to
all variants of a name, so `em_disable gpg` also skips `01-gpg.linux.sh`.

Multiple names are accepted, for example `em_disable sdkman wasi`. Run
`em_disable` without arguments to list disabled names. Disabling a script takes
effect on the next load; it does not undo exports or functions already loaded.

The list is saved in `$ENVMANAGER_DIR/disabled-scripts` and ignored by Git. Remove
a name from that file to enable it again. Set `ENVMANAGER_DISABLED_FILE` before
loading envmanager to use another file. Core helpers cannot be disabled.

Zsh completion suggests available script names, excluding disabled names. It
works with the standard `compinit` completion system whether envmanager loads
before or after it. If your Zsh configuration does not initialize completion,
add `autoload -Uz compinit; compinit` to `~/.zshrc`.

## OS-specific scripts

Unsuffixed scripts run on every OS. Add an OS suffix immediately before `.sh`
(or before `.local.sh` for a local override):

| Filename | Runs on |
| --- | --- |
| `01-gpg.linux.sh` | Linux |
| `99-example.macos.sh` | macOS |
| `99-example.darwin.sh` | macOS, alias for `.macos.sh` |
| `99-example.linux.local.sh` | Linux, local override |

`.freebsd.sh`, `.openbsd.sh`, `.netbsd.sh` and `.windows.sh` are also supported.
Windows detection covers Cygwin, MSYS and MinGW shells. Eligible scripts still
load in filename order, after core helpers.

## Core modules

`00-core.sh` is the startup entry point. It loads the modules below and calls
`em_init` to configure defaults, install shell fallbacks, and register completions.
Existing `em_*` functions remain available to the numbered scripts.

| Module | Responsibility |
| --- | --- |
| `lib/environment.sh` | Directory creation, variable lookup, fallback selection, exports, environment defaults |
| `lib/scripts.sh` | Script discovery, name and OS normalization, disabled scripts, loading |
| `lib/run-every.sh` | Duration parsing, clock access, hashing, expiration checks, throttled execution |
| `lib/shell.sh` | Logging, completion registration, lazy-loading fallbacks, initialization |

Sourcing a module only defines functions. It does not create directories, change
environment defaults, install fallbacks, or register hooks. Tests can source an
individual module and call its decision helpers directly. Functions that perform
actions use the other modules as documented at the top of each file.

`em_first_nonempty` selects a value; `em_export_alternatives` applies it to the
current shell. `em_normalize_os` accepts an OS name; `em_current_os` queries the
host. `em_expiry_pending` accepts the current time and an expiration;
`em_run_every` reads state and executes commands. `em_now` wraps `date +%s` and
can be redefined by a test to provide a fixed clock.

Logging is disabled by default. With `ENVMANAGER_ENABLE_LOGGING=true`, startup
and helper messages omit environment dumps, exported values, and command arguments.

## Tests

Run `python3 -m unittest discover -s tests -v`. Tests use temporary repositories
and the available Bash and Zsh executables. OS names are simulated to check
filtering without running installers or fetching updates. Python 3.9 or newer
is required. Install both shells to exercise both implementations locally.

The suite covers module imports, initialization, environment exports, script
selection and disabled scripts, completion hooks, lazy loading, and throttling.
Clock-dependent tests use fixed times and require no sleeps. Tests inspect exports
and loaded functions in the shell process that performs the operation.

The GitHub Actions workflow runs the suite with both shells on native Linux and
macOS runners, and requires both shell executables to be present.
