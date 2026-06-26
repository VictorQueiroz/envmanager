#!/bin/bash


WASI_SDK_PATH="$XDG_DATA_HOME/wasi-sdk"

download_wasi_sdk() {
  if [ -d "$WASI_SDK_PATH" ]; then
    return 0
  fi
  local wasi_major_version=29
  local wasi_url="https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-$wasi_major_version/wasi-sdk-$wasi_major_version.0-x86_64-linux.tar.gz"
  unset -f download_wasi_sdk
  mkdir -p "$WASI_SDK_PATH"
  wget -o /tmp/wasi-sdk.tar.gz -O- "$wasi_url" | tar xz -C "$WASI_SDK_PATH" --strip-components=1
}

download_wasi_sdk

export WASI_SDK_PATH
