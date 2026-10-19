#!/bin/sh

# Definitions only. Android is an OS; Termux is an Android runtime.
em_normalize_os() {
  case "$1" in
    Android|android) printf 'android\n' ;;
    Darwin|macos) printf 'macos\n' ;;
    CYGWIN*|MINGW*|MSYS*|windows) printf 'windows\n' ;;
    *) printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' ;;
  esac
}

em_android_sdk() {
  [ -x /system/bin/getprop ] || return 1
  /system/bin/getprop ro.build.version.sdk 2>/dev/null
}

em_current_os() {
  local os sdk
  if [ -n "${ENVMANAGER_OS:-}" ]; then
    os="$(em_normalize_os "$ENVMANAGER_OS")"
    case "$os" in
      android|linux|macos|freebsd|openbsd|netbsd|windows) printf '%s\n' "$os"; return ;;
      *) printf 'envmanager: unsupported ENVMANAGER_OS\n' >&2; return 2 ;;
    esac
  fi
  os="$(uname -s)" || return
  if [ "$os" = Linux ]; then
    sdk="$(em_android_sdk)" || sdk=""
    case "$sdk" in
      ''|*[!0-9]*) ;;
      *) printf 'android\n'; return ;;
    esac
    if [ -n "${TERMUX_VERSION:-}" ] && [ -n "${PREFIX:-}" ]; then
      printf 'android\n'
      return
    fi
  fi
  em_normalize_os "$os"
}

em_current_runtime() {
  local os
  os="$(em_current_os)" || return
  case "${ENVMANAGER_RUNTIME:-}" in
    system) printf 'system\n'; return ;;
    termux)
      [ "$os" = android ] || { printf 'envmanager: termux runtime requires Android\n' >&2; return 2; }
      printf 'termux\n'; return ;;
    '') ;;
    *) printf 'envmanager: unsupported ENVMANAGER_RUNTIME\n' >&2; return 2 ;;
  esac
  if [ "$os" = android ] && [ -n "${TERMUX_VERSION:-}" ] && [ -n "${PREFIX:-}" ]; then
    printf 'termux\n'
  else
    printf 'system\n'
  fi
}

em_current_arch() {
  local arch
  arch="${ENVMANAGER_ARCH:-$(uname -m)}" || return
  case "$arch" in
    arm64|aarch64) printf 'aarch64\n' ;;
    amd64|x86_64) printf 'x86_64\n' ;;
    armv7*|armv8l|arm) printf 'arm\n' ;;
    i?86) printf 'i686\n' ;;
    *) printf '%s\n' "$arch" ;;
  esac
}

em_platform() {
  local os runtime arch
  os="$(em_current_os)" || return
  runtime="$(em_current_runtime)" || return
  arch="$(em_current_arch)" || return
  printf 'os=%s\nruntime=%s\narch=%s\n' "$os" "$runtime" "$arch"
}
