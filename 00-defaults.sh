#!/bin/bash

envmanager_defaults_user_install_prefix="/tmp/user-0001"

if [ -n "$XDG_DATA_HOME" ]; then
  USER_INSTALL_PREFIX="$XDG_DATA_HOME"
elif [ -n "$XDG_CONFIG_HOME" ]; then
  USER_INSTALL_PREFIX="$XDG_CONFIG_HOME"
elif [ -n "$HOME" ]; then
  USER_INSTALL_PREFIX="$HOME"
else
  printf 'Unable to determine parent directory for user-level installations. '
  printf 'Defaulting to %s\n' "$envmanager_defaults_user_install_prefix"
  USER_INSTALL_PREFIX="$envmanager_defaults_user_install_prefix"
fi

export USER_INSTALL_PREFIX
