#!/bin/bash

# PNPM version
PNPM_VERSION="${PNPM_VERSION:-11.9.0}"
export PNPM_VERSION

# PNPM home directory
PNPM_HOME=${PNPM_HOME:-"$XDG_DATA_HOME/pnpm"}
export PNPM_HOME

_pnpm_get_binary_directory() {
  local pnpm_binary_directory
  local pnpm_available_binary_directories
  pnpm_available_binary_directories=(
    # 10.23.0
    "$PNPM_HOME"
    # 11.9.0
    "$PNPM_HOME"/bin
  )

  for current_pnpm_binary_directory in "${pnpm_available_binary_directories[@]}"; do
    if [[ -n "$pnpm_binary_directory" ]]; then
      break
    fi

    if command -v "$current_pnpm_binary_directory"/pnpm &>/dev/null; then
      pnpm_binary_directory="$current_pnpm_binary_directory"
    fi
  done

  if [[ -z "$pnpm_binary_directory" ]]; then
    return 1
  fi

  printf '%s' "$pnpm_binary_directory"
}

_add_pnpm_to_path() {
  local pnpm_binary_directory
  pnpm_binary_directory="$(_pnpm_get_binary_directory)"

  if [[ -z "$pnpm_binary_directory" ]]; then
    return 1
  fi

  PATH="$pnpm_binary_directory:$PATH"
  export PATH
}

_install_pnpm() {
  unset -f _install_pnpm

  local pnpm_binary_directory
  pnpm_binary_directory="$(_pnpm_get_binary_directory)"

  if [[ -n "$pnpm_binary_directory" ]]; then
    return 0
  fi

  local pnpm_installer_args
  pnpm_installer_args=(
    PNPM_VERSION="$PNPM_VERSION"
    ENV=/dev/null
    SHELL=/bin/sh
  )
  curl -fsSL https://get.pnpm.io/install.sh | env "${pnpm_installer_args[@]}" sh -
}

_install_pnpm

_add_pnpm_to_path

