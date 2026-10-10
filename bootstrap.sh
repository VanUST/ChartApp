#!/usr/bin/env sh
# PURPOSE: Turn a fresh Linux or macOS checkout into a workspace that can build and verify
#          ChartApp, and fail with an actionable message at the first step that is not satisfied.
#          It is the POSIX counterpart of bootstrap.ps1 and performs the same checks in the same
#          order, so a report from either platform is read the same way.
# INPUTS: --skip-verify skips the melos verify gate. --skip-android skips the Android SDK check
#         for a developer who only runs pure-Dart tests.
# OUTPUTS: KEY=VALUE lines on stdout for every checked component, ending in BOOTSTRAP=ok, and
#          exit status 0. On failure it prints the failing KEY with the exact command that fixes
#          it and exits 1. Nothing is downloaded: installing an SDK is a deliberate act, so this
#          script reports what is missing instead of silently fetching gigabytes.
# KEYWORDS: bootstrap, linux, macos, posix, toolchain, fvm, flutter-pin, idempotent, ldd
#
# Idempotent: every step re-checks its condition, so re-running after a partial failure resumes
# rather than repeating completed work.
#
# Written for POSIX sh rather than bash so it runs unchanged in a minimal container image and
# under dash. Do not introduce bashisms such as `[[`, arrays or `local`.

set -eu

SKIP_VERIFY=0
SKIP_ANDROID=0
for arg in "$@"; do
  case "$arg" in
    --skip-verify) SKIP_VERIFY=1 ;;
    --skip-android) SKIP_ANDROID=1 ;;
    *) echo "bootstrap: unknown argument '$arg'" >&2; exit 2 ;;
  esac
done

# Resolve the repository root from this script's own location, so the script works regardless of
# the caller's working directory.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

note() {
  printf '    %s\n' "$1"
}

ok() {
  printf '%s=%s\n' "$1" "$2"
}

fail() {
  # fail KEY REASON FIX...
  key=$1
  reason=$2
  shift 2
  printf '%s=missing\n' "$key" >&2
  printf '  %s\n' "$reason" >&2
  for fix in "$@"; do
    printf '  fix: %s\n' "$fix" >&2
  done
  printf 'BOOTSTRAP=failed\n' >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Git
# ---------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || fail GIT 'git is not on PATH.' \
  'Install git with your package manager, e.g. apt-get install git'

GIT_VERSION=$(git --version | sed 's/^git version //')
git config --global core.longpaths true >/dev/null 2>&1 || true
ok GIT "$GIT_VERSION"

# ---------------------------------------------------------------------------
# 2. Flutter at the pinned version
# ---------------------------------------------------------------------------
[ -f "$ROOT/.fvmrc" ] || fail FLUTTER '.fvmrc is missing, so there is no pinned Flutter version.' \
  'Restore .fvmrc from version control.'

# Pull the "flutter" field out of .fvmrc without requiring jq or a Dart SDK.
PINNED=$(sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/.fvmrc" | head -n 1)
[ -n "$PINNED" ] || fail FLUTTER 'Could not read the pinned Flutter version from .fvmrc.' \
  'Check that .fvmrc contains a "flutter": "<version>" entry.'
note "pinned Flutter is $PINNED (from .fvmrc)"

FLUTTER_SOURCE=''
if [ -x "$ROOT/.fvm/flutter_sdk/bin/flutter" ]; then
  # FVM's stable symlink is preferred: it is the only source that cannot drift from .fvmrc.
  FLUTTER_SOURCE='fvm-link'
  flutter_run() { "$ROOT/.fvm/flutter_sdk/bin/flutter" "$@"; }
  # The Dart SDK is taken from the same place as Flutter rather than from PATH. On an FVM setup
  # Flutter is deliberately not on PATH, so a bare `dart` would resolve to nothing; and on a
  # machine with a standalone Dart it could be a different version than the pinned Flutter ships.
  dart_run() { "$ROOT/.fvm/flutter_sdk/bin/dart" "$@"; }
elif command -v fvm >/dev/null 2>&1; then
  FLUTTER_SOURCE='fvm-cli'
  flutter_run() { fvm flutter "$@"; }
  dart_run() { fvm dart "$@"; }
elif command -v flutter >/dev/null 2>&1; then
  FLUTTER_SOURCE='path'
  flutter_run() { flutter "$@"; }
  dart_run() { dart "$@"; }
else
  fail FLUTTER 'No Flutter SDK found and none is pinned locally.' \
    'Install FVM (https://fvm.app), then run: fvm install' \
    "Then: fvm use $PINNED"
fi

FLUTTER_VERSION_OUTPUT=$(flutter_run --version 2>&1 || true)
FLUTTER_VERSION=$(printf '%s\n' "$FLUTTER_VERSION_OUTPUT" | sed -n 's/^Flutter \([0-9][0-9.]*\).*/\1/p' | head -n 1)
[ -n "$FLUTTER_VERSION" ] || fail FLUTTER 'Could not parse the version out of `flutter --version`.' \
  'Run `flutter doctor -v` and resolve the reported problem.'

[ "$FLUTTER_VERSION" = "$PINNED" ] || fail FLUTTER \
  "Installed Flutter is $FLUTTER_VERSION but .fvmrc pins $PINNED." \
  "fvm install $PINNED" \
  "fvm use $PINNED"
ok FLUTTER "$FLUTTER_VERSION ($FLUTTER_SOURCE)"

# ---------------------------------------------------------------------------
# 3. Dart, which ships inside the Flutter SDK
# ---------------------------------------------------------------------------
# `flutter --version` also reports the bundled Dart version on the "Tools" line.
DART_VERSION=$(printf '%s\n' "$FLUTTER_VERSION_OUTPUT" | sed -n 's/.*Dart \([0-9][0-9.]*\).*/\1/p' | head -n 1)
[ -n "$DART_VERSION" ] || DART_VERSION='unknown'
ok DART "$DART_VERSION"

# ---------------------------------------------------------------------------
# 4. JDK 17, needed to build for Android
# ---------------------------------------------------------------------------
JAVA_VERSION=''
if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
  JAVA_VERSION=$("$JAVA_HOME/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1)
elif command -v java >/dev/null 2>&1; then
  JAVA_VERSION=$(java -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -n 1)
fi
if [ "$JAVA_VERSION" = '17' ]; then
  ok JDK '17'
elif [ "$SKIP_ANDROID" -eq 1 ]; then
  ok JDK "skipped (found: ${JAVA_VERSION:-none})"
else
  fail JDK "JDK 17 is required to build for Android; found: ${JAVA_VERSION:-none}." \
    'Install Eclipse Temurin 17: https://adoptium.net/temurin/releases/?version=17' \
    'Then set JAVA_HOME to that installation.'
fi

# ---------------------------------------------------------------------------
# 5. Android SDK
#
# This checks for the SDK PACKAGES, not merely for the presence of a tool. That distinction is
# not pedantic: the legacy `sdkmanager` splits a package id such as `platforms;android-35` on
# the semicolon, reports "Package platforms not found" for each fragment, and still exits 0. A
# check that only asked whether sdkmanager exists would pass on an SDK with nothing installed.
# ---------------------------------------------------------------------------
if [ "$SKIP_ANDROID" -eq 1 ]; then
  ok ANDROID_SDK 'skipped'
else
  ANDROID_HOME_EFFECTIVE="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  [ -n "$ANDROID_HOME_EFFECTIVE" ] || fail ANDROID_SDK \
    'Neither ANDROID_HOME nor ANDROID_SDK_ROOT is set.' \
    'Install the Android command line tools: https://developer.android.com/studio#command-tools' \
    'Set ANDROID_HOME to the extracted sdk directory, then open a NEW shell.'
  [ -d "$ANDROID_HOME_EFFECTIVE" ] || fail ANDROID_SDK \
    "ANDROID_HOME points at '$ANDROID_HOME_EFFECTIVE', which does not exist." \
    'Correct or unset ANDROID_HOME.'

  # The modern `android` CLI supersedes `sdkmanager`, which now prints a deprecation warning.
  ANDROID_CLI="$ANDROID_HOME_EFFECTIVE/cmdline-tools/latest/bin/android"
  [ -x "$ANDROID_CLI" ] || [ -x "$ANDROID_HOME_EFFECTIVE/cmdline-tools/latest/bin/sdkmanager" ] || \
    fail ANDROID_SDK "No command line tools found under '$ANDROID_HOME_EFFECTIVE/cmdline-tools'." \
      "Extract the Android command line tools so that $ANDROID_CLI exists" \
      'Download: https://developer.android.com/studio#command-tools'

  MISSING=''
  [ -e "$ANDROID_HOME_EFFECTIVE/platform-tools/adb" ] || MISSING="$MISSING platform-tools"
  [ -d "$ANDROID_HOME_EFFECTIVE/platforms/android-35" ] || MISSING="$MISSING platforms;android-35"
  [ -d "$ANDROID_HOME_EFFECTIVE/build-tools/35.0.0" ] || MISSING="$MISSING build-tools;35.0.0"

  if [ -n "$MISSING" ]; then
    if [ -x "$ANDROID_CLI" ]; then
      INSTALLER="\"$ANDROID_CLI\" --sdk=$ANDROID_HOME_EFFECTIVE sdk install"
    else
      INSTALLER="sdkmanager --sdk_root=$ANDROID_HOME_EFFECTIVE"
    fi
    # shellcheck disable=SC2086
    fail ANDROID_SDK "The SDK is missing:$MISSING" \
      "$INSTALLER 'platforms;android-35'" \
      "$INSTALLER 'build-tools;35.0.0'" \
      "$INSTALLER 'platform-tools'" \
      'Use the android CLI, not sdkmanager: the legacy tool splits the ";" in a package id, installs nothing and still exits 0.'
  fi
  ok ANDROID_SDK "ok ($ANDROID_HOME_EFFECTIVE)"
fi

# ---------------------------------------------------------------------------
# 6. Resolve the workspace
# ---------------------------------------------------------------------------
note 'resolving workspace dependencies...'
flutter_run pub get >/dev/null || fail WORKSPACE 'Dependency resolution failed.' \
  'Run `flutter pub get` by hand to see the full output.'
ok WORKSPACE 'ok'

# ---------------------------------------------------------------------------
# 7. Verify
# ---------------------------------------------------------------------------
if [ "$SKIP_VERIFY" -eq 1 ]; then
  ok VERIFY 'skipped'
else
  note 'running melos run verify...'
  if ! dart_run run melos run verify; then
    fail VERIFY 'The acceptance gate did not pass.' \
      'Run `dart run melos run verify` by hand to see the full output.'
  fi
  ok VERIFY 'pass'
fi

printf 'BOOTSTRAP=ok\n'
exit 0
