#!/bin/sh

# Discover an installed Termux JDK. SDKMAN's desktop bootstrap is not used.
if [ -z "${JAVA_HOME:-}" ] && [ -n "${PREFIX:-}" ]; then
  # An unmatched glob aborts Zsh startup; discovery also handles absent/empty JVM
  # directories. Only the selected path leaves the discovery subshell.
  em_java_directory="$(
    if [ -d "$PREFIX/lib/jvm" ]; then
      find "$PREFIX/lib/jvm" -mindepth 1 -maxdepth 1 -print | sort |
        while IFS= read -r em_java_candidate; do
          if [ -x "$em_java_candidate/bin/java" ]; then
            printf '%s\n' "$em_java_candidate"
            break
          fi
        done
    fi
  )"
  if [ -n "$em_java_directory" ]; then
    JAVA_HOME="$em_java_directory"
    export JAVA_HOME
  fi
  unset em_java_directory
fi
