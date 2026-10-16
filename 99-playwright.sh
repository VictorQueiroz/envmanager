#!/bin/bash

_setup_playwright() {
  unset -f _setup_playwright

  local playwright_temp_root_dir
  playwright_temp_root_dir="${TMPDIR}/playwright"

  PWTEST_CACHE_DIR="${playwright_temp_root_dir}/cache"
  export PWTEST_CACHE_DIR

  PLAYWRIGHT_BROWSERS_PATH="${playwright_temp_root_dir}/browsers"
  export PLAYWRIGHT_BROWSERS_PATH
}

_setup_playwright
