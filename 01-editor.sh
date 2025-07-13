#!/bin/bash

set_editor_environment_variable() {
  unset -f set_editor_environment_variable

  # If `VISUAL` environment variable is set, set `EDITOR` environment variable
  if [ -n "$VISUAL" ]; then
    EDITOR="$VISUAL"
    export EDITOR
    return 0
  fi

  # If the `EDITOR` environment variable is already set, do nothing
  if [ -n "$EDITOR" ]; then
    return 0
  fi

  local editors

  # If `EDITORS` environment variable is set globally, use it
  if [ -n "$EDITORS" ]; then
    editors=("${EDITORS[@]}")
  else
    editors=(
      nvim
      vim
      vi
      nano
    )
  fi

  # Iterate over the editors and stop when one is found
  for editor in "${editors[@]}"; do
    if command -v "$editor" &>/dev/null; then
      EDITOR="$editor"
      export EDITOR
      break
    fi
  done

  # If `VISUAL` environment variable is not set, inherits the value of `EDITOR`
  if [ -z "$VISUAL" ]; then
    VISUAL="$EDITOR"
    export VISUAL
  fi
}

set_editor_environment_variable
