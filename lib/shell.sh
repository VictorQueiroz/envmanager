#!/bin/bash

# Definitions only; em_init uses environment.sh to configure defaults, then
# activates shell integration. Completion candidates come from scripts.sh.

# Register now if compinit has run, or at the first prompt after it runs.
# The #compdef file also supports compinit running after this file is sourced.
em_register_completions() {
  [ -n "${ZSH_VERSION:-}" ] || return 0
  . "$ENVMANAGER_DIR/lib/shell-zsh.sh" || return
  em_register_zsh_completions
}

em_systemd-cat() {
  if [ "${ENVMANAGER_ENABLE_LOGGING:-false}" != "true" ]; then
    return
  fi
  local backend="${ENVMANAGER_LOG_BACKEND:-auto}"
  if [ "$backend" = auto ]; then
    if command -v systemd-cat >/dev/null 2>&1; then backend=systemd; else backend=stderr; fi
  fi
  case "$backend" in
    systemd) systemd-cat --stderr-priority=err --identifier="${ENVMANAGER_SYSTEMD_IDENTIFIER:-envmanager}" "$@" ;;
    stderr|file)
      case "$1" in --priority=*) shift ;; esac
      # Only our printf logging interface is supported by portable backends.
      [ "$1" = printf ] || return 2
      shift
      if [ "$backend" = stderr ]; then
        printf "$@" >&2
      else
        local log_file="${ENVMANAGER_LOG_FILE:-}" log_directory
        case "$log_file" in
          /*/*) log_directory="${log_file%/*}" ;;
          *) printf 'envmanager: ENVMANAGER_LOG_FILE must be an absolute file path\n' >&2; return 2 ;;
        esac
        # Restrict newly created directories and files, without changing caller umask.
        (umask 077; em_mkdir "$log_directory" && printf "$@" >> "$log_file")
      fi ;;
    *) printf 'envmanager: unknown logging backend: %s\n' "$backend" >&2; return 2 ;;
  esac
}

em_print_debug() {
  em_systemd-cat --priority=debug printf "$@"
}

em_print_err() {
  em_systemd-cat --priority=err printf "$@"
}

em_print() {
  em_print_debug "$@"
}

em_install_shell_fallbacks() {
  [ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] || return 0
  # zsh-snap (`znap`) provides lazy command loading in Zsh. In Bash — or any shell
  # without zsh-snap — provide a minimal shim so the same rc scripts work in both.
  # Only the `znap function <loader> <trigger> <snippet>` form is used here.
  if ! command -v znap >/dev/null 2>&1; then
    znap() {
      [ "$1" = function ] || return 0
      # $2 = loader name (Zsh completion only, ignored here)
      # $3 = trigger command, $4 = snippet that prepares the real command
      local trigger="$3" snippet
      # Parse loader definitions at invocation, after removing the wrapper.
      # Keeping nested definitions out of the wrapper also avoids a Zsh crash.
      snippet="$(printf '%q' "$4")"
      eval "${trigger}() {
        unset -f ${trigger}   # remove the stub
        eval ${snippet}       # install the real command
        ${trigger} \"\$@\"    # re-dispatch to it
      }"
    }

    # Provide the shim only when no real completion registration is available.
    if ! command -v compdef >/dev/null 2>&1; then
      compdef() { :; }
    fi
  fi
}

# Called by 00-core.sh after every module has been loaded.
em_init() {
  em_current_os >/dev/null || return
  em_current_runtime >/dev/null || return
  em_init_environment || return
  em_install_shell_fallbacks
  em_register_completions

  em_print 'Configuring EnvManager...\n'
}
