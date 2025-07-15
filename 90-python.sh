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

  # In case plugins are going to be updated, use these Git arguments to do so.
  local pyenv_update_plugin_git_command_args
  pyenv_update_plugin_git_command_args=(
    "-C" "$pyenv_plugins_dir/$plugin_name"
    pull
    --quiet
  )

  local plugin_destination
  for plugin_name in "${pyenv_plugins[@]}"; do
    plugin_destination="$pyenv_plugins_dir/$plugin_name"

    if [ ! -d "${plugin_destination}/.git" ]; then
      printf 'Installing %s plugin...\n' "$plugin_name"
      git clone "${pyenv_git_repository_uri}/${plugin_name}.git" "$pyenv_plugins_dir/$plugin_name"
    elif $PYENV_UPDATE_PLUGINS; then
      # Update the plugin repository quietly
      git "${pyenv_update_plugin_git_command_args[@]}"
    fi
  done
}

compile_pyenv_bash_extension() {
  unset -f compile_pyenv_bash_extension

  local config_script="$PYENV_ROOT/src/configure"
  local make_dir="$PYENV_ROOT"

  if [ ! -x "$config_script" ]; then
    printf 'Configure script not found or not executable: %s\n' "$config_script"
    return 1
  fi

  "$config_script" --prefix="$PYENV_ROOT" || return 1
  make -C "$make_dir" || return 1
}

install_pyenv() {
  unset -f install_pyenv

  # Only compile the bash extension once
  local pyenv_compile_bash_extension
  pyenv_compile_bash_extension=false

  # Clone pyenv if it's not already installed
  if [ ! -d "$PYENV_ROOT" ]; then
    local pyenv_git_repository_uri
    pyenv_git_repository_uri="https://github.com/pyenv"

    printf 'Cloning pyenv into %s...' "$PYENV_ROOT"

    git clone "$pyenv_git_repository_uri"/pyenv.git "$PYENV_ROOT" || return 1

    pyenv_compile_bash_extension=true

    # Install plugins
    install_pyenv_plugins "$pyenv_git_repository_uri" || return 1
  fi

  # Load `pyenv` into the current shell
  load_pyenv

  # Try to compile a dynamic Bash extension to speed up Pyenv.
  # See: https://github.com/pyenv/pyenv?tab=readme-ov-file#2-basic-github-checkout
  # This needs to specifically be done after `load_pyenv` is executed.
  if $pyenv_compile_bash_extension; then
    compile_pyenv_bash_extension || true
  fi
}

load_pyenv() {
  unset -f load_pyenv

  # Add `$PYENV_ROOT/bin` to `$PATH`
  if [ -d "$PYENV_ROOT"/bin ]; then
    PATH="$PYENV_ROOT/bin:$PATH"
    export PATH
  fi

  # If `SHELL` is not set, just run `pyenv init -`
  if [ -z "$SHELL" ]; then
    eval "$(pyenv init -)"
    return 0
  fi

  local shell_name
  shell_name="$(basename "$SHELL")"

  eval "$(pyenv init - "$shell_name")"

  source "${PYENV_ROOT}/completions/pyenv.${shell_name}"
}

# Set the `PYENV_ROOT` environment variable
PYENV_ROOT="$USER_INSTALL_PREFIX/pyenv"
export PYENV_ROOT

# Install pyenv and friends if it's not already installed
install_pyenv || return 1
