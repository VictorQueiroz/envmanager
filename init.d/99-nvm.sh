#!/bin/bash

# Initialize NVM
export NVM_DIR="${XDG_CONFIG_HOME}/nvm"

# WARNING: If using ZSH, do not attempt to load NVM bash completions here, it will fail
nvm_init() {
  # Unset this function, we only need to run it once
  unset -f nvm_init

  # If NVM folder does not exist, install it
  if [ ! -d "$NVM_DIR" ]; then
    # Get the latest NVM version from GitHub
    local NVM_VERSION_LATEST="$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | jq -r .tag_name | sed 's/^v//')"
    nvm_install "$NVM_VERSION_LATEST" || return 1
  fi

  # Load NVM
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
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

  env "${env_args[@]}" "${install_nvm_bash_args[@]}"
}

# Unset NODE_PATH just in case
unset NODE_PATH

# Creates `js` alias to run node with NODE_PATH set to global npm modules
js() {
  NODE_PATH=$(npm root -g) node "$@"
}

nvm_man() {
  env MAN=$(which man) MANPATH="$MAN_PATH:$NVM_DIR/versions/node/$(node -v)/share" \
    $SHELL -l -c "\$MAN $@"
}

nvm_init