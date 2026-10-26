#!/bin/sh
# All work happens in main, after the complete script has been read.
# Install: curl -fsSL https://projects.envmanager.victorqueiroz.dev/install.sh | sh

em_i_error() { printf 'envmanager: %s\n' "$*" >&2; exit 1; }
em_i_help() {
  cat <<'HELP'
EnvManager installer — macOS and Linux, Bash and Zsh
Usage: sh install.sh [OPTIONS]
  --shell auto|bash|zsh|both  Shell integration (default: login shell)
  --dir ABSOLUTE_PATH        Checkout location (respects ENVMANAGER_DIR/XDG_CONFIG_HOME)
  --version vX.Y.Z           Install a specific published release
  --profile core|full        New installs only; full enables optional tool installers
  --upgrade                 Upgrade a clean checkout; retain local configuration
  --uninstall               Remove managed shell integration; retain checkout/tool data
  --dry-run                 Describe work without writing files or downloading
  --help                    Show this help
HELP
}
em_i_fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl --fail --silent --show-error --location --retry 2 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else em_i_error 'install curl or wget first'; fi
}
em_i_quote() { printf "'"; printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf "'"; }
em_i_resolve() {
  em_i_path=$1
  em_i_links=0
  while [ -L "$em_i_path" ]; do
    em_i_links=$((em_i_links + 1))
    [ "$em_i_links" -le 40 ] || em_i_error "symlink loop: $1"
    em_i_link=$(readlink "$em_i_path") || return
    case "$em_i_link" in /*) em_i_path=$em_i_link ;; *) em_i_path=${em_i_path%/*}/$em_i_link ;; esac
  done
  printf '%s\n' "$em_i_path"
}
em_i_write() {
  # Resolve the leaf symlink, then replace its target without replacing the link.
  em_i_target=$(em_i_resolve "$1") || return
  if [ -f "$em_i_target" ] && cmp -s "$em_i_target" "$2"; then return; fi
  [ ! -e "$em_i_target" ] || [ -f "$em_i_target" ] || em_i_error "not a regular file: $1"
  mkdir -p "${em_i_target%/*}"
  em_i_write_temp=$(mktemp "$em_i_target.envmanager.XXXXXX") || return
  if [ -f "$em_i_target" ]; then
    cp -p "$em_i_target" "$em_i_write_temp"
    cp -p "$em_i_target" "$em_i_target.envmanager-backup.$em_i_stamp"
  fi
  cat "$2" > "$em_i_write_temp"
  mv -f "$em_i_write_temp" "$em_i_target"
}
em_i_block() {
  cat <<'BLOCK'
# >>> EnvManager >>>
if [ -n "${BASH_VERSION:-}${ZSH_VERSION:-}" ] && [ "${_ENVMANAGER_STARTUP_PID:-}" != "$$" ] && [ -r "$HOME/.envmanagerrc" ]; then
  _ENVMANAGER_STARTUP_PID=$$
  . "$HOME/.envmanagerrc"
fi
# <<< EnvManager <<<
BLOCK
}
em_i_rc_files() {
  if [ -f "$em_i_state/rc-files" ]; then cat "$em_i_state/rc-files" || return; fi
  [ "$em_i_remove" != true ] || return 0
  case "$em_i_shell" in bash|both)
    printf '%s\n' "$HOME/.bashrc"
    em_i_login=$HOME/.bash_profile
    for em_i_candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      if [ -f "$em_i_candidate" ]; then em_i_login=$em_i_candidate; break; fi
    done
    printf '%s\n' "$em_i_login" ;;
  esac
  case "$em_i_shell" in zsh|both) printf '%s\n' "${ZDOTDIR:-$HOME}/.zshrc" ;; esac
}

# This same read-only planner describes and renders every migration. Its small
# lexical matcher never sources configuration or evaluates a path expression.
em_i_plan_rc() {
  [ ! -e "$1" ] || [ -f "$1" ] || em_i_error "not a shell configuration file: $1"
  em_i_input=$1
  [ -f "$em_i_input" ] || em_i_input=/dev/null
  EM_I_PLAN_FILE="$1" EM_I_PLAN_MODE="$2" EM_I_PLAN_REMOVE="$em_i_remove" \
  EM_I_PLAN_BLOCK="$(em_i_block)" awk '
    function trimmed(value) { sub(/^[ \t]+/, "", value); sub(/[ \t]+$/, "", value); return value }
    function fail(line, message) {
      printf "envmanager: %s:%d: %s; review this integration before retrying.\n", file, line, message > "/dev/stderr"
      failed=1
      exit 2
    }
    function hook(value, rest, i) {
      value=trimmed(value)
      if(value !~ /^(source|\.)[ \t]+/) return 0
      sub(/^(source|\.)[ \t]+/, "", value)
      for(i=1; i<=path_count; i++) {
        if(substr(value, 1, length(paths[i])) != paths[i]) continue
        rest=substr(value, length(paths[i])+1)
        if(rest ~ /^[ \t]*$/ || rest ~ /^[ \t]+#/ || rest ~ /^[ \t]*;[ \t]*(#.*)?$/) return 1
      }
      return 0
    }
    function emit(command) {
      print template[1]; print template[2]; print template[3]
      print command
      print template[5]; print template[6]
    }
    BEGIN {
      file=ENVIRON["EM_I_PLAN_FILE"]
      mode=ENVIRON["EM_I_PLAN_MODE"]
      remove=ENVIRON["EM_I_PLAN_REMOVE"]=="true"
      split(ENVIRON["EM_I_PLAN_BLOCK"], template, "\n")
      paths[++path_count]="\"$HOME/.envmanagerrc\""
      paths[++path_count]="\"$HOME\"/.envmanagerrc"
      paths[++path_count]="\"${HOME}/.envmanagerrc\""
      paths[++path_count]="\"${HOME}\"/.envmanagerrc"
      paths[++path_count]="~/.envmanagerrc"
    }
    {
      lines[NR]=$0
      if($0==template[1]) {
        if(start || inside) fail(NR, "conflicting managed markers")
        start=NR; inside=1; next
      }
      if($0==template[6]) {
        if(!inside) fail(NR, "conflicting managed markers")
        finish=NR; inside=0; next
      }
      if(inside) { body[++body_count]=$0; next }
      if(remove) next
      value=trimmed($0)
      if(value=="" || substr(value,1,1)=="#") next
      if(hook($0)) {
        if(legacy) fail(NR, "multiple legacy EnvManager hooks")
        legacy=NR
      } else if(index(value,"envmanagerrc")) fail(NR, "unrecognized EnvManager reference")
    }
    END {
      if(failed) exit 2
      if(inside) fail(start, "conflicting managed markers")
      if(start && (body_count!=4 || body[1]!=template[2] || body[2]!=template[3] || !hook(body[3]) || body[4]!=template[5]))
        fail(start, "edited managed block")
      position=legacy ? legacy : (start ? start : NR+1)
      if(remove) action=start ? "remove managed hook" : "unchanged"
      else if(legacy) action=start ? "repair duplicate hook in place" : "adopt existing hook in place"
      else action=start ? "unchanged" : "append managed hook"
      if(mode=="describe") { printf "%s:%d: %s\n", file, position, action; exit }
      command=legacy ? lines[legacy] : (start ? body[3] : template[4])
      for(i=1; i<=NR; i++) {
        if(remove) {
          if(i==start) print ": # EnvManager integration removed"
        } else if(i==position) emit(command)
        if(start && i>=start && i<=finish) continue
        if(!remove && i==legacy) continue
        print lines[i]
      }
      if(!remove && !start && !legacy) { if(NR) print ""; emit(command) }
    }
  ' "$em_i_input"
}

em_i_edit_rc() {
  if [ "$em_i_remove" = true ] && [ ! -f "$1" ]; then return; fi
  em_i_plan_rc "$1" render > "$em_i_tmp/rc"
  em_i_write "$1" "$em_i_tmp/rc"
}
em_i_names() {
  # The production normalizer is definition-only, also parseable by /bin/sh.
  . "$1/lib/scripts.sh"
  for em_i_script in "$1"/*.sh; do
    [ -f "$em_i_script" ] || continue
    em_script_name "$em_i_script"
  done | LC_ALL=C sort -u
}
em_i_core() {
  em_i_names "$1" > "$em_i_tmp/names"
  if [ "$em_i_profile" = core ]; then
    { [ ! -f "$1/disabled-scripts" ] || cat "$1/disabled-scripts"
      while IFS= read -r em_i_name; do
        case "$em_i_name" in core|home-bin-folders|disable-telemetry) continue ;; esac
        if ! grep -Fqx -- "$em_i_name" "$em_i_tmp/old-names"; then printf '%s\n' "$em_i_name"; fi
      done < "$em_i_tmp/names"
    } | LC_ALL=C sort -u > "$em_i_tmp/disabled"
    # Configuration is ignored by Git and retained by checkout/upgrade.
    cp "$em_i_tmp/disabled" "$1/disabled-scripts"
  fi
  cp "$em_i_tmp/names" "$1/.envmanager-script-names"
}
em_i_release() {
  case "$em_i_version" in
    latest) em_i_manifest_url=$em_i_release_base/latest/download/envmanager-release.txt ;;
    *) printf '%s\n' "$em_i_version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || em_i_error 'version must be vX.Y.Z'
       em_i_manifest_url=$em_i_release_base/download/$em_i_version/envmanager-release.txt ;;
  esac
  em_i_fetch "$em_i_manifest_url" "$em_i_tmp/release"
  em_i_tag= em_i_commit=
  while IFS='=' read -r em_i_key em_i_value; do
    case "$em_i_key" in version) em_i_tag=$em_i_value ;; commit) em_i_commit=$em_i_value ;; esac
  done < "$em_i_tmp/release"
  printf '%s\n' "$em_i_tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || em_i_error 'invalid release version'
  printf '%s\n' "$em_i_commit" | grep -Eq '^[0-9a-f]{40}$' || em_i_error 'invalid release commit'
  [ "$em_i_version" = latest ] || [ "$em_i_version" = "$em_i_tag" ] || em_i_error 'release version mismatch'
}
em_i_marker() {
  printf 'version=%s\ncommit=%s\nprofile=%s\n' "$em_i_tag" "$em_i_commit" "$em_i_profile" > "$em_i_tmp/marker"
  em_i_write "$em_i_dir/.envmanager-release" "$em_i_tmp/marker"
}
em_i_cleanup() {
  [ -z "${em_i_tmp:-}" ] || rm -rf "$em_i_tmp"
  [ -z "${em_i_stage:-}" ] || [ ! -d "$em_i_stage" ] || rm -rf "$em_i_stage"
  if [ "${em_i_locked:-false}" = true ]; then rm -f "$em_i_state/install.lock/pid"; rmdir "$em_i_state/install.lock" 2>/dev/null || :; fi
}
em_i_main() {
  set -eu
  [ -n "${HOME:-}" ] || em_i_error 'HOME must be set'
  em_i_shell=auto em_i_dir=${ENVMANAGER_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/envmanager}
  em_i_dir_explicit=false em_i_profile=core em_i_profile_explicit=false em_i_version=latest
  em_i_upgrade=false em_i_remove=false em_i_dry=false em_i_tmp= em_i_locked=false
  em_i_repository=${ENVMANAGER_INSTALL_REPOSITORY:-https://github.com/VictorQueiroz/envmanager.git}
  em_i_release_base=${ENVMANAGER_INSTALL_RELEASE_BASE:-https://github.com/VictorQueiroz/envmanager/releases}
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --shell|--dir|--version|--profile)
        [ "$#" -ge 2 ] && [ -n "$2" ] || em_i_error "$1 needs a value"
        case "$1" in --shell) em_i_shell=$2 ;; --dir) em_i_dir=$2; em_i_dir_explicit=true ;; --version) em_i_version=$2 ;; --profile) em_i_profile=$2; em_i_profile_explicit=true ;; esac
        shift 2 ;;
      --upgrade) em_i_upgrade=true; shift ;; --uninstall) em_i_remove=true; shift ;;
      --dry-run) em_i_dry=true; shift ;; --help|-h) em_i_help; return ;;
      *) em_i_error "unknown option: $1 (see --help)" ;;
    esac
  done
  [ -n "${HOME:-}" ] || em_i_error 'HOME must be set'
  em_i_state=${XDG_STATE_HOME:-$HOME/.local/state}/envmanager
  if [ "$em_i_dir_explicit" = false ] && [ -z "${ENVMANAGER_DIR:-}" ] && [ -f "$em_i_state/install-directory" ]; then
    IFS= read -r em_i_dir < "$em_i_state/install-directory"
  fi
  case "$em_i_dir" in /*) ;; *) em_i_error '--dir must be absolute' ;; esac
  case "$em_i_dir$HOME$em_i_state${ZDOTDIR:-}" in *'
'*) em_i_error 'paths containing newlines are unsupported' ;; esac
  case "$em_i_profile" in core|full) ;; *) em_i_error 'profile must be core or full' ;; esac
  case "$em_i_shell" in auto) em_i_shell=${SHELL:-bash}; em_i_shell=${em_i_shell##*/}; case "$em_i_shell" in bash|zsh) ;; *) em_i_shell=bash ;; esac ;; bash|zsh|both) ;; *) em_i_error 'shell must be auto, bash, zsh or both' ;; esac
  case "$(uname -s)" in Darwin|Linux) ;; *) em_i_error 'this installer supports macOS and Linux' ;; esac
  [ ! -x /system/bin/getprop ] || em_i_error 'use the documented manual Android installation'
  printf 'EnvManager: %s; shell=%s; directory=%s\n' "$([ "$em_i_remove" = true ] && printf uninstall || printf install)" "$em_i_shell" "$em_i_dir"
  em_i_paths=$(em_i_rc_files) || return
  em_i_paths=$(printf '%s\n' "$em_i_paths" | LC_ALL=C sort -u) || return
  printf '%s\n' "$em_i_paths" | while IFS= read -r em_i_config; do
    [ -n "$em_i_config" ] || continue
    em_i_plan_rc "$em_i_config" describe
  done
  if [ "$em_i_dry" = true ]; then printf 'Dry run: no files, downloads, or shell settings changed.\n'; return; fi
  umask 077
  mkdir -p "$em_i_state"
  if ! mkdir "$em_i_state/install.lock" 2>/dev/null; then
    em_i_owner=$(cat "$em_i_state/install.lock/pid" 2>/dev/null || :)
    case "$em_i_owner" in ''|*[!0-9]*) em_i_error 'installer lock needs inspection; another installation may be starting' ;; esac
    if kill -0 "$em_i_owner" 2>/dev/null; then em_i_error 'another installer is running'; fi
    rm -f "$em_i_state/install.lock/pid"
    rmdir "$em_i_state/install.lock" || em_i_error 'installer lock needs inspection'
    mkdir "$em_i_state/install.lock"
  fi
  em_i_locked=true
  printf '%s\n' "$$" > "$em_i_state/install.lock/pid"
  trap em_i_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  em_i_tmp=$(mktemp -d "${TMPDIR:-/tmp}/envmanager-install.XXXXXX")
  em_i_stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
  printf '%s\n' "$em_i_paths" | sed '/^$/d' > "$em_i_tmp/rc-sorted"
  : > "$em_i_tmp/old-names"

  if [ "$em_i_remove" != true ]; then
    command -v git >/dev/null 2>&1 || em_i_error 'install Git first (see the macOS/Linux guide)'
    if [ -e "$em_i_dir" ]; then
      [ -f "$em_i_dir/envmanagerrc" ] && [ -f "$em_i_dir/00-core.sh" ] && [ -f "$em_i_dir/lib/scripts.sh" ] || em_i_error "directory is not an EnvManager installation: $em_i_dir"
      if [ -f "$em_i_dir/.envmanager-release" ]; then
        em_i_installed_profile=$(sed -n 's/^profile=//p' "$em_i_dir/.envmanager-release")
        [ "$em_i_profile_explicit" = false ] || [ "$em_i_profile" = "$em_i_installed_profile" ] || em_i_error 'use em_enable/em_disable to change an existing installation'
        em_i_profile=$em_i_installed_profile
      else em_i_profile=existing; fi
      if [ "$em_i_version" != latest ] && [ "$em_i_upgrade" != true ]; then
        em_i_installed_version=$(sed -n 's/^version=//p' "$em_i_dir/.envmanager-release" 2>/dev/null || :)
        [ "$em_i_installed_version" = "$em_i_version" ] || em_i_error 'use --upgrade to change the version of an existing installation'
      fi
      if [ "$em_i_upgrade" = true ]; then
        [ -d "$em_i_dir/.git" ] || em_i_error 'upgrading requires a Git checkout'
        [ -z "$(git -C "$em_i_dir" status --porcelain --untracked-files=normal)" ] || em_i_error 'checkout has local changes; preserve or commit them before upgrading'
        em_i_origin=$(git -C "$em_i_dir" remote get-url origin)
        [ "$em_i_origin" = "$em_i_repository" ] || [ "$em_i_origin" = git@github.com:VictorQueiroz/envmanager.git ] || em_i_error 'checkout origin differs from the installer repository'
        if [ "$em_i_profile" = existing ]; then
          [ "$em_i_version" = latest ] || em_i_error 'existing branch installations use fast-forward upgrades; version pinning applies to managed release installs'
          git -C "$em_i_dir" pull --ff-only
        else
          [ ! -f "$em_i_dir/.envmanager-script-names" ] || cp "$em_i_dir/.envmanager-script-names" "$em_i_tmp/old-names"
          em_i_release
          git -C "$em_i_dir" fetch --depth 1 origin "refs/tags/$em_i_tag"
          [ "$(git -C "$em_i_dir" rev-parse 'FETCH_HEAD^{commit}')" = "$em_i_commit" ] || em_i_error 'release tag does not match its published commit'
          git -C "$em_i_dir" checkout --detach "$em_i_commit"
          em_i_core "$em_i_dir"
          em_i_marker
        fi
      fi
    else
      em_i_release
      mkdir -p "${em_i_dir%/*}"
      # Clone on the destination filesystem so publishing the directory is atomic.
      em_i_stage=$(mktemp -d "${em_i_dir}.install.XXXXXX")
      if ! git clone --quiet --depth 1 --branch "$em_i_tag" "$em_i_repository" "$em_i_stage"; then rmdir "$em_i_stage" 2>/dev/null || :; em_i_error 'download interrupted; rerun the installer'; fi
      if [ "$(git -C "$em_i_stage" rev-parse HEAD)" != "$em_i_commit" ]; then rm -rf "$em_i_stage"; em_i_error 'release tag does not match its published commit'; fi
      em_i_core "$em_i_stage"
      printf 'version=%s\ncommit=%s\nprofile=%s\n' "$em_i_tag" "$em_i_commit" "$em_i_profile" > "$em_i_stage/.envmanager-release"
      mv "$em_i_stage" "$em_i_dir"
      em_i_stage=
    fi
    # Keep custom legacy loaders. New managed loaders follow the versioned file.
    if [ ! -e "$HOME/.envmanagerrc" ] || grep -q '^# EnvManager managed loader$' "$HOME/.envmanagerrc"; then
      { printf '# EnvManager managed loader\nENVMANAGER_DIR='; em_i_quote "$em_i_dir"; printf '\nexport ENVMANAGER_DIR\n. "$ENVMANAGER_DIR/envmanagerrc"\n'; } > "$em_i_tmp/loader"
      em_i_write "$HOME/.envmanagerrc" "$em_i_tmp/loader"
    else
      printf 'Keeping your custom ~/.envmanagerrc; its checkout path remains under your control.\n'
    fi
    while IFS= read -r em_i_config; do em_i_edit_rc "$em_i_config"; done < "$em_i_tmp/rc-sorted"
    em_i_write "$em_i_state/rc-files" "$em_i_tmp/rc-sorted"
    printf '%s\n' "$em_i_dir" > "$em_i_tmp/directory"
    em_i_write "$em_i_state/install-directory" "$em_i_tmp/directory"
    printf 'Ready. Open a new shell, then run em_status. Optional tools: em_enable NAME.\n'
  else
    while IFS= read -r em_i_config; do em_i_edit_rc "$em_i_config"; done < "$em_i_tmp/rc-sorted"
    { printf '# EnvManager managed loader\nENVMANAGER_DIR='; em_i_quote "$em_i_dir"; printf '\nexport ENVMANAGER_DIR\n. "$ENVMANAGER_DIR/envmanagerrc"\n'; } > "$em_i_tmp/loader"
    if [ -f "$HOME/.envmanagerrc" ] && [ ! -L "$HOME/.envmanagerrc" ] && cmp -s "$HOME/.envmanagerrc" "$em_i_tmp/loader"; then
      cp -p "$HOME/.envmanagerrc" "$HOME/.envmanagerrc.envmanager-backup.$em_i_stamp"
      rm "$HOME/.envmanagerrc"
    fi
    rm -f "$em_i_state/rc-files" "$em_i_state/install-directory"
    printf 'Shell integration removed. Checkout, local overrides and tool data retained at %s.\n' "$em_i_dir"
  fi
}
em_i_main "$@"
