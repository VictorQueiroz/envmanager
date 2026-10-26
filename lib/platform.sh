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

# Cache only inside an explicit operation. Overrides changed by a sourced
# script invalidate the snapshot immediately; the next operation detects anew.
em_platform_cache_valid() {
  [ "${_EM_PLATFORM_CACHE:-false}" = true ] &&
    [ "${ENVMANAGER_OS:-}" = "$_EM_PLATFORM_INPUT_OS" ] &&
    [ "${ENVMANAGER_RUNTIME:-}" = "$_EM_PLATFORM_INPUT_RUNTIME" ] &&
    [ "${TERMUX_VERSION:-}" = "$_EM_PLATFORM_INPUT_TERMUX" ] &&
    [ "${PREFIX:-}" = "$_EM_PLATFORM_INPUT_PREFIX" ]
}

em_with_platform() {
  local _EM_PLATFORM_CACHE=false _EM_PLATFORM_OS="" _EM_PLATFORM_RUNTIME=""
  local _EM_PLATFORM_INPUT_OS="${ENVMANAGER_OS:-}" _EM_PLATFORM_INPUT_RUNTIME="${ENVMANAGER_RUNTIME:-}"
  local _EM_PLATFORM_INPUT_TERMUX="${TERMUX_VERSION:-}" _EM_PLATFORM_INPUT_PREFIX="${PREFIX:-}"
  _EM_PLATFORM_OS="$(em_current_os)" || return
  _EM_PLATFORM_CACHE=true
  _EM_PLATFORM_RUNTIME="$(em_current_runtime)" || return
  "$@"
}

em_current_os() {
  if em_platform_cache_valid && [ -n "${_EM_PLATFORM_OS:-}" ]; then
    printf '%s\n' "$_EM_PLATFORM_OS"
    return
  fi
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
  if em_platform_cache_valid && [ -n "${_EM_PLATFORM_RUNTIME:-}" ]; then
    printf '%s\n' "$_EM_PLATFORM_RUNTIME"
    return
  fi
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
