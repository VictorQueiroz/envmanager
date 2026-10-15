#!/bin/bash

# Definitions only; em_init uses environment.sh to configure defaults, then
# activates shell integration. Completion candidates come from scripts.sh.

# Register now if compinit has run, or at the first prompt after it runs.
# The #compdef file also supports compinit running after this file is sourced.
em_register_completions() {
  [ -n "${ZSH_VERSION:-}" ] || return 0
  local completion_dir="$ENVMANAGER_DIR/completions"
  case ":$FPATH:" in
    *":$completion_dir:"*) ;;
    *) fpath=("$completion_dir" "${fpath[@]}") ;;
  esac
  autoload -Uz _em_disable add-zsh-hook
  if typeset -p _comps >/dev/null 2>&1; then
    compdef _em_disable em_disable
    add-zsh-hook -d precmd em_register_completions
  else
    add-zsh-hook precmd em_register_completions
  fi
}

em_systemd-cat() {
  if [ "$ENVMANAGER_ENABLE_LOGGING" != "true" ]; then
    return
  fi
  systemd-cat --stderr-priority=err --identifier="$ENVMANAGER_SYSTEMD_IDENTIFIER" "$@"
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
  em_init_environment
  em_install_shell_fallbacks
  em_register_completions

  em_print 'Configuring EnvManager...\n'
}
