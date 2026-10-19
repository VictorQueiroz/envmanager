#!/system/bin/sh

# Run with /system/bin/sh on Android (PATH=/system/bin), or mksh in desktop CI.
# Fixtures stay under TMPDIR for inspection; no Git, Python or network is needed.
set -eu
umask 077
em_test_source="${1:?pass the envmanager checkout path}"
em_test_root="$(mktemp -d "${TMPDIR:?set a writable TMPDIR}/envmanager-smoke.XXXXXX")"
mkdir "$em_test_root/repo"
cp "$em_test_source/00-core.sh" "$em_test_root/repo/00-core.sh"
cp -R "$em_test_source/lib" "$em_test_root/repo/lib"
ENVMANAGER_DIR="$em_test_root/repo"
ENVMANAGER_OS=android
ENVMANAGER_RUNTIME=system
ENVMANAGER_AUTO_UPDATE=false
ENVMANAGER_ENABLE_LOGGING=false
TMPDIR="$em_test_root/tmp"
mkdir "$TMPDIR"
export ENVMANAGER_DIR ENVMANAGER_OS ENVMANAGER_RUNTIME TMPDIR

printf '%s\n' 'export EM_TEST_VALUE="caller export"' 'em_test_function() { printf "caller function\n"; }' > "$ENVMANAGER_DIR/01-test.android.sh"
for em_test_file in 02-test.linux.sh 03-test.android.termux.sh 90-python.sh; do
  printf 'return 91\n' > "$ENVMANAGER_DIR/$em_test_file"
done
printf 'export EM_SYSTEM_VALUE=yes\n' > "$ENVMANAGER_DIR/04-native.android.system.sh"

# Any attempt to update or bootstrap fails the smoke check.
git() { printf 'unexpected Git invocation\n' >&2; exit 92; }
curl() { printf 'unexpected download\n' >&2; exit 93; }
wget() { printf 'unexpected download\n' >&2; exit 93; }
. "$em_test_source/envmanagerrc"
[ "$EM_TEST_VALUE" = 'caller export' ]
[ "$(em_test_function)" = 'caller function' ]
[ "$EM_SYSTEM_VALUE" = yes ]
[ "$(em_available_script_names)" = "native
test" ]
em_disable test
em_is_disabled test
em_enable test
if em_is_disabled test; then exit 94; fi

em_test_count=0
em_test_record() { em_test_count=$((em_test_count + 1)); }
em_run_every 1d em_test_record
em_run_every 1d em_test_record
[ "$em_test_count" = 1 ]

ENVMANAGER_ENABLE_LOGGING=true
ENVMANAGER_LOG_BACKEND=file
ENVMANAGER_LOG_FILE="$em_test_root/log with spaces/messages.log"
em_print 'portable logging\n'
[ "$(cat "$ENVMANAGER_LOG_FILE")" = 'portable logging' ]
em_status
printf 'Android system-shell smoke passed: %s\n' "$em_test_root"
