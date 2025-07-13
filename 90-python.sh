#!/bin/bash

install_pyenv_plugins() {
  unset -f install_pyenv_plugins

  local pyenv_git_repository_uri="$1"

  # If `pyenv_git_repository_uri` is not set, prints an error
  if [ -z "$pyenv_git_repository_uri" ]; then
    printf 'pyenv_git_repository_uri must be given '
    printf 'as an argument to %s function\n' 'install_pyenv_plugins'
    return 1
  fi

  # If `PYENV_PLUGINS` is not set, defaults to all plugins
  if [ -z "$PYENV_PLUGINS" ]; then
    PYENV_PLUGINS=(
      pyenv-ccache
      pyenv-doctor
      pyenv-implicit
      pyenv-pip-migrate
      pyenv-update
      pyenv-users
      pyenv-version-ext
      pyenv-virtualenv
      pyenv-virtualenvwrapper
    )
  elif [ "${#PYENV_PLUGINS[@]}" -eq 0 ]; then
    # If it's an empty array, do nothing
    return 0
  fi

  local pyenv_plugins
  pyenv_plugins=("${PYENV_PLUGINS[@]}")

  # Unset the `PYENV_PLUGINS` environment variable
  unset -v PYENV_PLUGINS

  local pyenv_plugins_dir
  pyenv_plugins_dir="$PYENV_ROOT/plugins"

  # Ensure the `plugins` directory exists
  if [ ! -d "$pyenv_plugins_dir" ]; then
    mkdir --parents --verbose "$pyenv_plugins_dir"
  fi

  local plugin_destination
  for plugin_name in "${pyenv_plugins[@]}"; do
    plugin_destination="$pyenv_plugins_dir/$plugin_name"

    if [ ! -d "${plugin_destination}/.git" ]; then
      printf 'Installing %s plugin...' "$plugin_name"
      git clone "${pyenv_git_repository_uri}/${plugin_name}.git" "$pyenv_plugins_dir/$plugin_name"
    else
      # Update the plugin repository
      printf 'Updating %s plugin...' "$plugin_name"
      git -C "$pyenv_plugins_dir/$plugin_name" pull
    fi
  done
}

compile_pyenv_bash_extension() {
  unset -f compile_pyenv_bash_extension

  cd "$PYENV_ROOT" || return 1
  src/configure || return 1
  make || return 1
}

install_pyenv() {
  unset -f install_pyenv

  local pyenv_git_repository_uri
  pyenv_git_repository_uri="https://github.com/pyenv"

  # Clone pyenv if it's not already installed
  if [ ! -d "$PYENV_ROOT" ]; then
    printf 'Cloning pyenv into %s...' "$PYENV_ROOT"
    git clone "$pyenv_git_repository_uri"/pyenv.git "$PYENV_ROOT" || return 1
  fi

  # Try to compile a dynamic Bash extension to speed up Pyenv. See: https://github.com/pyenv/pyenv?tab=readme-ov-file#2-basic-github-checkout
  compile_pyenv_bash_extension || return 1

  # Install plugins
  install_pyenv_plugins "$pyenv_git_repository_uri" || return 1

  # Load pyenv
  if [ -d "$PYENV_ROOT"/bin ]; then
    PATH="$PYENV_ROOT/bin:$PATH"
    export PATH
  fi

  SHELL_NAME="$(basename "$SHELL")"

  if [ "$SHELL_NAME" = "zsh" ]; then
    pyenv_shell="zsh"
  elif [ "$SHELL_NAME" = "bash" ]; then
    pyenv_shell="bash"
  fi

  eval "$(pyenv init - "$pyenv_shell")"
}

PYENV_ROOT="$HOME/.pyenv"
export PYENV_ROOT

# Install pyenv and friends if it's not already installed
install_pyenv
