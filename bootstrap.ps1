#!/usr/bin/env pwsh
# PURPOSE: Turn a fresh Windows checkout into a workspace that can build and verify ChartApp, and
#          fail with an actionable message at the first step that is not satisfied. It exists so
#          that "works on my machine" is replaced by a printed report of the toolchain every
#          developer and agent shares.
# INPUTS: -SkipVerify skips the melos verify gate. -SkipAndroid skips the JDK and Android SDK
#         checks for a developer who only runs pure-Dart tests. No other arguments.
# OUTPUTS: KEY=VALUE lines on stdout for every checked component, ending in BOOTSTRAP=ok, and
#          process exit code 0. On failure it prints the failing KEY with the exact command that
#          fixes it and exits 1. Nothing is downloaded: installing an SDK is a deliberate act, so
#          this script reports what is missing rather than silently fetching gigabytes.
# KEYWORDS: bootstrap, windows, toolchain, fvm, flutter-pin, idempotent, ldd, android-cli
#
# Idempotent: every step re-checks its condition, so re-running after a partial failure resumes
# rather than repeating completed work.
#
# Environment variables set by an installer are only visible to processes started afterwards.
# A shell that was already open when JAVA_HOME was set will not see it, and this script will
# report JDK=missing correctly. Open a new shell rather than working around it.

[CmdletBinding()]
param(
  [switch]$SkipVerify,
  [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $root

# PURPOSE: Run an external command and capture both output streams without letting the strict
#          error preference terminate the script. Several tools this bootstrap calls report
#          normally on stderr — `java -version` and `flutter --version` both do — and PowerShell
#          turns a native command's stderr into a terminating error record when
#          $ErrorActionPreference is 'Stop'. Capturing those calls through this helper is what
#          keeps a successful `java -version` from being reported as a crash.
# INPUTS: Command — an executable name or path. Arguments — its argument array, possibly empty.
# OUTPUTS: An object with `Output` (stdout and stderr merged as one string, because these tools
#          split a single logical message across both) and `ExitCode`. Never throws for a
#          non-zero exit; the caller decides whether that matters.
# KEYWORDS: native-command, stderr, error-action-preference, exit-code, capture
function Invoke-Native {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @()
  )
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $code = -1
  $output = ''
  try {
    $output = (& $Command @Arguments 2>&1 | Out-String)
    $code = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  return [pscustomobject]@{ Output = $output; ExitCode = $code }
}

function Write-Ok {
  param([string]$Key, [string]$Value)
  Write-Host "$Key=$Value"
}

function Write-Note {
  param([string]$Message)
  Write-Host "    $Message" -ForegroundColor DarkGray
}

function Fail {
  param([string]$Key, [string]$Reason, [string[]]$Fix)
  Write-Host "$Key=missing" -ForegroundColor Red
  Write-Host "  $Reason" -ForegroundColor Red
  foreach ($line in $Fix) {
    Write-Host "  fix: $line" -ForegroundColor Yellow
  }
  Write-Host 'BOOTSTRAP=failed'
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Git
# ---------------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Fail -Key 'GIT' -Reason 'git is not on PATH.' -Fix @('Install Git for Windows: https://git-scm.com/download/win')
}
$gitResult = Invoke-Native -Command 'git' -Arguments @('--version')
$gitVersion = ($gitResult.Output.Trim()) -replace '^git version ', ''
# Windows path limit: a Flutter workspace nests deeply enough to exceed MAX_PATH without this.
Invoke-Native -Command 'git' -Arguments @('config', '--global', 'core.longpaths', 'true') | Out-Null
Write-Ok 'GIT' $gitVersion

# ---------------------------------------------------------------------------
# 2. Flutter at the pinned version
# ---------------------------------------------------------------------------
$fvmrcPath = Join-Path $root '.fvmrc'
if (-not (Test-Path $fvmrcPath)) {
  Fail -Key 'FLUTTER' -Reason '.fvmrc is missing, so there is no pinned Flutter version.' -Fix @('Restore .fvmrc from version control.')
}
$pinned = (Get-Content $fvmrcPath -Raw | ConvertFrom-Json).flutter
Write-Note "pinned Flutter is $pinned (from .fvmrc)"

$flutterSource = $null
$flutterCommand = $null
if (Test-Path (Join-Path $root '.fvm\flutter_sdk\bin\flutter.bat')) {
  # FVM's stable symlink is preferred: it is the only source that cannot drift from .fvmrc.
  $flutterSource = 'fvm-link'
  $flutterCommand = Join-Path $root '.fvm\flutter_sdk\bin\flutter.bat'
} elseif (Get-Command fvm -ErrorAction SilentlyContinue) {
  $flutterSource = 'fvm-cli'
  $flutterCommand = 'fvm'
} elseif (Get-Command flutter -ErrorAction SilentlyContinue) {
  $flutterSource = 'path'
  $flutterCommand = 'flutter'
} else {
  Fail -Key 'FLUTTER' -Reason 'No Flutter SDK found and none is pinned locally.' -Fix @(
    'Install FVM (https://fvm.app), then run: fvm install',
    "Then: fvm use $pinned"
  )
}

# `fvm flutter ...` takes the subcommand as its first argument; a direct flutter executable does
# not. Resolving that difference once keeps every later call site identical.
function Invoke-Flutter {
  param([string[]]$Arguments)
  if ($flutterSource -eq 'fvm-cli') {
    return Invoke-Native -Command 'fvm' -Arguments (@('flutter') + $Arguments)
  }
  return Invoke-Native -Command $flutterCommand -Arguments $Arguments
}

# PURPOSE: Run the Dart SDK that belongs to the pinned Flutter, not whatever `dart` a PATH lookup
#          happens to find. On a machine that uses FVM the Flutter SDK is deliberately NOT on
#          PATH, so a bare `dart` resolves to nothing at all — and on a machine that does have a
#          standalone Dart, a bare `dart` could be a different version than the pinned Flutter
#          ships. Both cases are avoided by deriving the command from the same source that
#          supplied Flutter.
# INPUTS: Arguments — the dart subcommand and its flags.
# OUTPUTS: The same capture object as Invoke-Native.
# KEYWORDS: dart-sdk, fvm, path-shadowing, version-pinning, melos
function Invoke-Dart {
  param([string[]]$Arguments)
  if ($flutterSource -eq 'fvm-cli') {
    return Invoke-Native -Command 'fvm' -Arguments (@('dart') + $Arguments)
  }
  if ($flutterSource -eq 'fvm-link') {
    return Invoke-Native -Command (Join-Path $root '.fvm\flutter_sdk\bin\dart.bat') -Arguments $Arguments
  }
  return Invoke-Native -Command 'dart' -Arguments $Arguments
}

$flutterVersionResult = Invoke-Flutter -Arguments @('--version')
if ($flutterVersionResult.Output -match 'Flutter (\d+\.\d+\.\d+)') {
  $flutterVersion = $Matches[1]
} else {
  Fail -Key 'FLUTTER' -Reason 'Could not parse the version out of `flutter --version`.' -Fix @(
    'Run `flutter doctor -v` and resolve the reported problem.',
    $flutterVersionResult.Output
  )
}

if ($flutterVersion -ne $pinned) {
  Fail -Key 'FLUTTER' -Reason "Installed Flutter is $flutterVersion but .fvmrc pins $pinned." -Fix @(
    "fvm install $pinned",
    "fvm use $pinned"
  )
}
Write-Ok 'FLUTTER' "$flutterVersion ($flutterSource)"

# ---------------------------------------------------------------------------
# 3. Dart, which ships inside the Flutter SDK
# ---------------------------------------------------------------------------
if ($flutterVersionResult.Output -match 'Dart (\d+\.\d+\.\d+)') {
  Write-Ok 'DART' $Matches[1]
} else {
  Write-Ok 'DART' 'unknown'
}

# ---------------------------------------------------------------------------
# 4. JDK 17, needed to build for Android
# ---------------------------------------------------------------------------
$javaCommand = $null
if ($env:JAVA_HOME -and (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
  $javaCommand = Join-Path $env:JAVA_HOME 'bin\java.exe'
} elseif (Get-Command java -ErrorAction SilentlyContinue) {
  $javaCommand = 'java'
}

$javaVersion = 'none'
if ($javaCommand) {
  $javaResult = Invoke-Native -Command $javaCommand -Arguments @('-version')
  if ($javaResult.Output -match 'version "(\d+)') {
    $javaVersion = $Matches[1]
  }
}

if ($javaVersion -eq '17') {
  Write-Ok 'JDK' '17'
} elseif ($SkipAndroid) {
  Write-Ok 'JDK' "skipped (found: $javaVersion)"
} else {
  Fail -Key 'JDK' -Reason "JDK 17 is required to build for Android; found: $javaVersion." -Fix @(
    'Install Eclipse Temurin 17: https://adoptium.net/temurin/releases/?version=17',
    'Set JAVA_HOME to that installation, then open a NEW shell so the variable is visible.'
  )
}

# ---------------------------------------------------------------------------
# 5. Android SDK
#
# This checks for the SDK PACKAGES, not merely for the presence of a tool. That distinction is
# not pedantic: the legacy `sdkmanager.bat` splits a package id such as `platforms;android-35`
# on the semicolon, reports "Package platforms not found" for each fragment, and still exits 0.
# A check that only asked whether sdkmanager exists would pass on an SDK with nothing installed.
# ---------------------------------------------------------------------------
$androidHome = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $null }
if ($SkipAndroid) {
  Write-Ok 'ANDROID_SDK' 'skipped'
} elseif (-not $androidHome) {
  Fail -Key 'ANDROID_SDK' -Reason 'Neither ANDROID_HOME nor ANDROID_SDK_ROOT is set.' -Fix @(
    'Install the Android command line tools: https://developer.android.com/studio#command-tools',
    'Set ANDROID_HOME to the extracted sdk directory, then open a NEW shell.'
  )
} elseif (-not (Test-Path $androidHome)) {
  Fail -Key 'ANDROID_SDK' -Reason "ANDROID_HOME points at '$androidHome', which does not exist." -Fix @('Correct or unset ANDROID_HOME.')
} else {
  $cmdlineTools = Join-Path $androidHome 'cmdline-tools'
  # The modern `android` CLI supersedes `sdkmanager`, which now prints a deprecation warning.
  $androidCli = Get-ChildItem -Path $cmdlineTools -Recurse -Filter 'android.exe' -ErrorAction SilentlyContinue | Select-Object -First 1

  $missingPackages = @()
  if (-not (Test-Path (Join-Path $androidHome 'platform-tools\adb.exe'))) { $missingPackages += 'platform-tools' }
  if (-not (Test-Path (Join-Path $androidHome 'platforms\android-35'))) { $missingPackages += 'platforms;android-35' }
  if (-not (Test-Path (Join-Path $androidHome 'build-tools\35.0.0'))) { $missingPackages += 'build-tools;35.0.0' }

  if (-not $androidCli -and -not (Test-Path (Join-Path $cmdlineTools 'latest\bin\sdkmanager.bat'))) {
    Fail -Key 'ANDROID_SDK' -Reason "No command line tools found under '$cmdlineTools'." -Fix @(
      "Extract the Android command line tools so that $cmdlineTools\latest\bin\android.exe exists",
      'Download: https://developer.android.com/studio#command-tools'
    )
  }

  if ($missingPackages.Count -gt 0) {
    $installer = if ($androidCli) { "& `"$($androidCli.FullName)`" --sdk=$androidHome sdk install" } else { "sdkmanager --sdk_root=$androidHome" }
    Fail -Key 'ANDROID_SDK' -Reason "The SDK is missing: $($missingPackages -join ', ')." -Fix @(
      "$installer 'platforms;android-35'",
      "$installer 'build-tools;35.0.0'",
      "$installer 'platform-tools'",
      'Use the android CLI, not sdkmanager: the legacy .bat splits the ";" in a package id, installs nothing and still exits 0.'
    )
  }

  Write-Ok 'ANDROID_SDK' "ok ($androidHome)"
}

# ---------------------------------------------------------------------------
# 6. Resolve the workspace
# ---------------------------------------------------------------------------
Write-Note 'resolving workspace dependencies...'
$pubResult = Invoke-Flutter -Arguments @('pub', 'get')
if ($pubResult.ExitCode -ne 0) {
  Fail -Key 'WORKSPACE' -Reason 'Dependency resolution failed.' -Fix @($pubResult.Output)
}
Write-Ok 'WORKSPACE' 'ok'

# ---------------------------------------------------------------------------
# 7. Verify
# ---------------------------------------------------------------------------
if ($SkipVerify) {
  Write-Ok 'VERIFY' 'skipped'
} else {
  Write-Note 'running melos run verify...'
  $verifyResult = Invoke-Dart -Arguments @('run', 'melos', 'run', 'verify')
  if ($verifyResult.ExitCode -ne 0) {
    Fail -Key 'VERIFY' -Reason 'The acceptance gate did not pass.' -Fix @($verifyResult.Output)
  }
  Write-Ok 'VERIFY' 'pass'
}

Write-Host 'BOOTSTRAP=ok' -ForegroundColor Green
exit 0
