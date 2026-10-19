#!/bin/zsh

# Definitions only. Keep Zsh array syntax out of the portable core.
em_register_zsh_completions() {
  local completion_dir="$ENVMANAGER_DIR/completions"
  case ":$FPATH:" in
    *":$completion_dir:"*) ;;
    *) fpath=("$completion_dir" "${fpath[@]}") ;;
  esac
  autoload -Uz _em_disable _em_enable add-zsh-hook
  if typeset -p _comps >/dev/null 2>&1; then
    compdef _em_disable em_disable
    compdef _em_enable em_enable
    add-zsh-hook -d precmd em_register_completions
  else
    add-zsh-hook precmd em_register_completions
  fi
}
