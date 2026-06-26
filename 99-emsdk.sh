#!/bin/bash

emsdk_download() {
  unset -f emsdk_download

  local emsdk_url
  emsdk_url=https://github.com/emscripten-core/emsdk.git

  EMSDK_DIR="${EMSDK_DIR:-$XDG_DATA_HOME/emsdk}"
  export EMSDK_DIR

  if [ ! -d "$EMSDK_DIR" ]; then
    printf 'Cloning emsdk into %s...\n' "$EMSDK_DIR"
    git clone "$emsdk_url" "$EMSDK_DIR" || return 1
  else
    em_run_every 1d git -C "$EMSDK_DIR" pull --quiet || return 1
  fi

  znap function _emsdk emsdk 'source "$EMSDK_DIR/emsdk_env.sh"'

  return 0
}

emsdk_download
