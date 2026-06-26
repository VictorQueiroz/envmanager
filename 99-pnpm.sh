#!/bin/bash

# PNPM version
PNPM_VERSION=11.9.0
export PNPM_VERSION

# PNPM home directory
PNPM_HOME="$XDG_DATA_HOME/pnpm"
export PNPM_HOME

PATH="$PNPM_HOME/bin:$PATH"
export PATH

_install_pnpm() {
  unset -f _install_pnpm

  if command -v pnpm &>/dev/null; then
    return 0
  fi

  curl -fsSL https://get.pnpm.io/install.sh | env PNPM_VERSION="$PNPM_VERSION" sh -
}

_install_pnpm

