#!/bin/bash

ENVMANAGER_SYSTEMD_IDENTIFIER=envmanager

em_systemd-cat() {
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

em_get_var_value() {
    var_name="$1"
    # Try bash/zsh method first
    if value=$(eval "echo \"\${$var_name}\"" 2>/dev/null); then
        echo "$value"
    else
        # POSIX-compliant fallback
        eval "echo \"\${$var_name}\""
    fi
}

em_export_alternatives() {
  local var_name="$1"
  shift  # Remove variable name from arguments

  local original_value
  original_value="$(em_get_var_value "${var_name}")"
  
  # Return immediately if variable is already set
  if [ -n "$original_value" ]; then
    em_print_debug '%s is already set: %s\n' "$var_name" "$original_value"
    return
  fi
  
  # No alternatives provided - exit early
  if [ $# -eq 0 ]; then
    return
  fi
  
  local selected_value=""
  local last_alt

  # Process alternatives in order
  for alt in "$@"; do
    # Always remember the last alternative
    last_alt="$alt"
    # Use first non-empty alternative found
    if [ -n "$alt" ]; then
      selected_value="$alt"
      break
    fi
  done
  
  # If no non-empty alternative found, use last alternative (even if empty)
  if [ -z "$selected_value" ]; then
    selected_value="$last_alt"
  fi
  
  # Export the final value
  export "$var_name"="$selected_value"

  em_print '%s=%s\n' "$var_name" "$selected_value"
}

em_print 'Configuring EnvManager... Old environment below:\n'
em_print '---\n'
em_print '%s' "$(env)"
em_print '---\n'
