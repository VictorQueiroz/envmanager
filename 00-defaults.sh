#!/bin/bash

if [ -n "$XDG_DATA_HOME" ]; then
  USER_INSTALL_PREFIX="$XDG_DATA_HOME"
elif [ -n "$XDG_CONFIG_HOME" ]; then
  USER_INSTALL_PREFIX="$XDG_CONFIG_HOME"
elif [ -n "$HOME" ]; then
  USER_INSTALL_PREFIX="$HOME"
else
  printf 'Unable to determine parent directory for user-level installations. '
  printf 'Defaulting to /tmp\n'
  USER_INSTALL_PREFIX="/tmp"
fi

export USER_INSTALL_PREFIX
