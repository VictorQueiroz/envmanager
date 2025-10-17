#!/bin/bash

sdkman_init() {
  unset -f sdkman_init
  #
  # Initialize NVM
  if [[ -z "$SDKMAN_DIR" ]]; then
    printf 'SDKMAN_DIR must be defined\n'
    return 1
  fi

  # If SDKMAN_DIR is a directory, early return
  if [ -d "$SDKMAN_DIR" ]; then
    return 0
  fi

  curl -s "https://get.sdkman.io" | bash
}

sdkman_init

