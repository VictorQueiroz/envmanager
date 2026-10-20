#!/bin/bash

_setup_playwright() {
  unset -f _setup_playwright

  local playwright_temp_root_dir
  playwright_temp_root_dir="${TMPDIR}/playwright"

  em_export_path PWTEST_CACHE_DIR "$playwright_temp_root_dir/cache"

  em_export_path PLAYWRIGHT_BROWSERS_PATH "$playwright_temp_root_dir/browsers"
}

_setup_playwright
