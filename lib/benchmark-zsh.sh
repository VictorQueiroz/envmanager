#!/bin/zsh

# Definitions only. Call em_benchmark_auto early in .zshrc to include plugins.
# The DEBUG trap runs only until the first prompt (or em_benchmark_stop).
em_benchmark_start() {
  if [[ ! -o debugbeforecmd ]]; then
    print -ru2 -- 'envmanager: startup benchmark requires DEBUG_BEFORE_CMD'
    return 0
  fi
  emulate -L zsh
  [[ ${_em_benchmark_active:-false} != true ]] || return 0
  local budget=${1:-${ENVMANAGER_BENCHMARK_BUDGET_MS:-200}}
  local width=${ENVMANAGER_BENCHMARK_MAX_COMMAND_LENGTH:-100}
  if [[ -z $budget || $budget == *[!0-9]* || -z $width || $width == *[!0-9]* ]] ||
     (( ${#budget} > 8 || ${#width} > 5 || width < 4 )); then
    print -ru2 -- 'envmanager: benchmark budget must be a nonnegative integer (ms); command length must be 4-99999'
    return 2
  fi
  # A debugger may own DEBUG; leave its handler and options intact.
  if [[ $'\n'"$(trap)"$'\n' == *' DEBUG'$'\n'* ]] || (( $+functions[TRAPDEBUG] )); then
    print -ru2 -- 'envmanager: startup benchmark skipped because a DEBUG trap is already installed'
    return 0
  fi
  zmodload zsh/datetime || return
  zmodload zsh/parameter || return
  autoload -Uz add-zsh-hook
  typeset -g _em_benchmark_active=true
  typeset -gi _em_benchmark_budget=$(( 10#$budget ))
  typeset -gi _em_benchmark_width=$(( 10#$width ))
  typeset -gi _em_benchmark_subshell=$ZSH_SUBSHELL _em_benchmark_depth=0
  typeset -gF _em_benchmark_started=$EPOCHREALTIME
  typeset -ga _em_benchmark_times=() _em_benchmark_commands=()
  typeset -ga _em_benchmark_locations=() _em_benchmark_children=() _em_benchmark_rows=()
  add-zsh-hook precmd em_benchmark_stop
  add-zsh-hook zshexit em_benchmark_stop
  # The handler must survive this function; keep other options local.
  unsetopt localtraps
  TRAPDEBUG() {
    emulate -L zsh
    # Substitutions/pipelines are timed as a unit by their enclosing command.
    # Keeping the trap in children inert also keeps stdout captures untouched.
    [[ $ZSH_SUBSHELL == $_em_benchmark_subshell && ${funcstack[2]} != em_benchmark_start ]] || return 0
    local now=$EPOCHREALTIME location=${funcfiletrace[1]} command=$ZSH_DEBUG_CMD
    local depth=${#funcstack}
    # Stopping must happen before the stop function itself is profiled.
    if [[ $command == em_benchmark_stop* || ${funcstack[2]} == em_benchmark_stop ]]; then
      _em_benchmark_flush "$now" 1
      unfunction TRAPDEBUG
      return 0
    fi
    _em_benchmark_flush "$now" "$depth"
    # The pending parent is a shell function/source/eval, whose children have
    # their own timings. Omit these overlapping wrappers from the slow list.
    if (( depth > _em_benchmark_depth && _em_benchmark_depth > 0 )); then
      _em_benchmark_children[_em_benchmark_depth]=true
    fi
    _em_benchmark_depth=$depth
    _em_benchmark_times[depth]=$EPOCHREALTIME
    _em_benchmark_commands[depth]=$command
    _em_benchmark_locations[depth]=$location
    _em_benchmark_children[depth]=false
    return 0
  }
  return 0
}

# Close pending commands when execution returns to the same or an outer frame.
_em_benchmark_flush() {
  emulate -L zsh
  local now=$1 depth=$2 text row
  local -F elapsed
  local -i i
  for (( i = _em_benchmark_depth; i >= depth; --i )); do
    if [[ -n ${_em_benchmark_times[i]} && ${_em_benchmark_children[i]} != true ]]; then
      elapsed=$(( (now - _em_benchmark_times[i]) * 1000 ))
      if (( elapsed > _em_benchmark_budget )); then
        text=${_em_benchmark_commands[i]//$'\n'/ }
        text=${text//$'\r'/ }
        text=${text//$'\t'/ }
        # Escape terminal controls without expanding command arguments.
        text=${(V)text}
        if (( ${#text} > _em_benchmark_width )); then
          text="${text[1,$((_em_benchmark_width - 3))]}..."
        fi
        printf -v row '%.3f\t%s\t%s' "$elapsed" "${_em_benchmark_locations[i]}" "$text"
        _em_benchmark_rows+=("$row")
      fi
    fi
    _em_benchmark_times[i]=''
  done
}

em_benchmark_stop() {
  # Must be the first command: an inherited exit hook cannot stop the parent.
  [[ ${_em_benchmark_active:-false} == true && $ZSH_SUBSHELL == $_em_benchmark_subshell ]] || return 0
  local now=$EPOCHREALTIME
  unfunction TRAPDEBUG 2>/dev/null
  _em_benchmark_flush "$now" 1
  emulate -L zsh
  local -F total=$(( (now - _em_benchmark_started) * 1000 ))
  local elapsed location text
  _em_benchmark_active=false
  add-zsh-hook -d precmd em_benchmark_stop
  add-zsh-hook -d zshexit em_benchmark_stop
  printf 'envmanager: startup %.1f ms; %d commands > %d ms\n' "$total" "${#_em_benchmark_rows}" "$_em_benchmark_budget" >&2
  if (( ${#_em_benchmark_rows} )); then
    printf '       ms  file:line  command (max %d characters)\n' "$_em_benchmark_width" >&2
    while IFS=$'\t' read -r elapsed location text; do
      printf '%9.1f  %s  %s\n' "$elapsed" "$location" "$text" >&2
    done < <(printf '%s\n' "${_em_benchmark_rows[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr)
  fi
  unset _em_benchmark_times _em_benchmark_commands _em_benchmark_locations
  unset _em_benchmark_children _em_benchmark_rows
  return 0
}

em_benchmark_auto() {
  [[ -o interactive && ${ENVMANAGER_BENCHMARK:-true} == true ]] || return 0
  em_benchmark_start
}
