#!/bin/sh

# Discover an installed Termux JDK. SDKMAN's desktop bootstrap is not used.
if [ -z "${JAVA_HOME:-}" ] && [ -n "${PREFIX:-}" ]; then
  for em_java_directory in "$PREFIX"/lib/jvm/*; do
    if [ -x "$em_java_directory/bin/java" ]; then
      JAVA_HOME="$em_java_directory"
      export JAVA_HOME
      break
    fi
  done
  unset em_java_directory
fi
