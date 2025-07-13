#!/bin/bash

# WARNING: If using ZSH, do not attempt to load NVM bash completions here, it will fail

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
    source "$NVM_DIR/nvm.sh"
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
  mkdir --parents --verbose "${NVM_DIR}"

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
