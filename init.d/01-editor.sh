#!/bin/bash

set_editor_environment_variable() {
  unset -f set_editor_environment_variable

  # Create a fallback
  editors=(
    nvim
    vim
    vi
    nano
  )

  export editors

  # Iterate over the editors and stop when one is found
  for editor in "${editors[@]}"; do
    if command -v "$editor" &> /dev/null; then
      export EDITOR="$editor"
      break
    fi
  done
}

set_editor_environment_variable