#!/bin/bash

em_export_path NVM_DIR "$XDG_DATA_HOME/nvm" "${HOME:+$HOME/.nvm}"

# Resolve only an unambiguous numeric default using shell builtins. Named/LTS
# aliases, alias chains and multiple matching installations stay with NVM.
em_nvm_default_version() {
  local requested candidate version resolved=""
  [ -r "$NVM_DIR/alias/default" ] || return 1
  IFS= read -r requested < "$NVM_DIR/alias/default" || [ -n "$requested" ] || return 1
  requested="${requested#v}"
  case "$requested" in
    ''|*[!0-9.]*|.*|*.|*..*|*.*.*.*) return 1 ;;
    0|0.*|1|1.*|2|2.*|3|3.*) return 1 ;; # legacy Node/io.js layouts
  esac
  [ ! -e "$NVM_DIR/alias/$requested" ] && [ ! -e "$NVM_DIR/alias/v$requested" ] || return 1
  if [ -n "${ZSH_VERSION:-}" ]; then setopt localoptions nonomatch; fi
  for candidate in "$NVM_DIR"/versions/node/v*; do
    [ -d "$candidate" ] || continue
    version="${candidate##*/v}"
    case "$version" in
      ''|*[!0-9.]*|.*|*.|*..*|*.*.*.*) continue ;;
    esac
    case "$version" in *.*.*) ;; *) continue ;; esac
    case "$version" in
      "$requested"|"$requested".*)
        [ -z "$resolved" ] || return 1
        resolved="v$version" ;;
    esac
  done
  [ -n "$resolved" ] && [ -x "$NVM_DIR/versions/node/$resolved/bin/node" ] || return 1
  printf '%s\n' "$resolved"
}

# Backport NVM's Zsh output optimization only for the known legacy helper.
# Compare parsed function bodies so custom and already-fixed helpers survive.
em_nvm_enable_builtin_printf() {
  [ -n "${ZSH_VERSION:-}" ] || return 0
  local original expected
  original="$(typeset -f nvm_echo)" || return 0
  expected="$(
    em_nvm_legacy_echo() { command printf %s\\n "$*" 2>/dev/null; }
    typeset -f em_nvm_legacy_echo
  )" || return 0
  [ "${original#*\{}" = "${expected#*\{}" ] || return 0
  nvm_echo() {
    # Zsh's builtin can report success on closed stdout where GNU printf fails.
    # Keep the legacy command for that case; temporary fd 3 is restored after
    # the probe, and normal output still needs no external printf process.
    if { : 3>&1; } 2>/dev/null; then
      builtin printf '%s\n' "$*" 2>/dev/null
    else
      command printf '%s\n' "$*" 2>/dev/null
    fi
  }
}

nvm_init() {
  # Initialize NVM
  if [[ -z "$NVM_DIR" ]]; then
    printf 'NVM_DIR must be defined\n'
    return 1
  fi

  # Unset this function, we only need to run it once
  unset -f nvm_init

  # If NVM folder does not exist, install it
  if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
    # Get the latest NVM version from GitHub
    local NVM_VERSION_LATEST
    NVM_VERSION_LATEST="$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r .tag_name | sed 's/^v//')"

    nvm_install "$NVM_VERSION_LATEST" || return 1
  fi

  # Load NVM
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    local default_version current_version
    if [ "${ENVMANAGER_NVM_FAST_STARTUP:-true}" = true ] && default_version="$(em_nvm_default_version)"; then
      # Keep NVM and Node available immediately, but avoid its costly general
      # alias resolver when the numeric default has exactly one installation.
      source "$NVM_DIR/nvm.sh" --no-use || return
      em_nvm_enable_builtin_printf
      current_version="$(nvm current)" || :
      case "$current_version" in
        none|system) current_version="$default_version" ;;
      esac
      nvm use --silent "$current_version" >/dev/null
    elif [ -n "${ZSH_VERSION:-}" ] && [ "${ENVMANAGER_NVM_FAST_STARTUP:-true}" = true ]; then
      # Standard NVM invokes this handler at the end of nvm.sh. Defer that
      # invocation only long enough to install the builtin output helper,
      # then run the original handler with its normal startup arguments.
      case "$(< "$NVM_DIR/nvm.sh")" in
        *'nvm_process_parameters() {'*)
          source "$NVM_DIR/nvm.sh" --no-use || return
          em_nvm_enable_builtin_printf
          nvm_process_parameters ;;
        *) source "$NVM_DIR/nvm.sh" ;;
      esac
    else
      source "$NVM_DIR/nvm.sh"
    fi
  else
    printf 'Failed to load NVM\n'
  fi
}

nvm_install() {
  # Unset this function, we only need to run it once
  unset -f nvm_install

  # If first argument is empty, print an error
  if [ -z "$1" ]; then
    printf 'No version specified for NVM\n'
    return 1
  fi

  # First argument is the desired NVM version
  local NVM_VERSION="$1"
  local NVM_DOWNLOAD_URL="https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
  local CURL
  local BASH

  # Get explicit executable paths
  BASH="$(which bash)"
  CURL="$(which curl)"

  local install_nvm_bash_args=(
    "$BASH"
    '-c'
    '"$CURL" -o- "$NVM_DOWNLOAD_URL" | bash'
  )

  local env_args=(
    # Make sure NVM is installed without changing `.zshrc` or `.bashrc`
    "PROFILE=/dev/null"

    # Pass `curl` absolute executable path
    "CURL=$CURL"

    # Pass NVM download URL
    "NVM_DOWNLOAD_URL=$NVM_DOWNLOAD_URL"
  )

  # Create NVM_DIR
  em_mkdir "${NVM_DIR}"

  env "${env_args[@]}" "${install_nvm_bash_args[@]}"
}

# Creates `js` alias to run node with NODE_PATH set to global npm modules
js() {
  NODE_PATH=$(npm root -g) node "$@"
}

nvm_man() {
  local env_args=(
    "MANPATH='$MAN_PATH:$NVM_DIR/versions/node/$(node -v)/share'"
  )
  "${env_args[@]}" man "$@"
}

nvm_init

# Unset NODE_PATH just in case
unset NODE_PATH
