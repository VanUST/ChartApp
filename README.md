# ChartApp

Mobile-first chord-chart editor with native handwriting. The design lives in
<docs/sdd.md>; this file only covers how to get a working checkout and how to prove a
change is acceptable.

## Toolchain

| Component | Pinned value | Pinned by |
|---|---|---|
| Flutter | 3.47.7 (stable) | `.fvmrc` |
| Dart | 3.13.5 (ships with Flutter 3.47.7) | `.fvmrc` |
| JDK | 17 (Temurin) | `bootstrap` |
| Android SDK | platform 35, build-tools 35.0.0, emulator API 34 | `bootstrap` |
| Melos | 8.9.0 | root `pubspec.yaml` |

Melos 8 has no `melos.yaml`. Workspace configuration is the `melos:` section of the root
`pubspec.yaml`, and package discovery is the Dart `workspace:` field.

## Getting a working checkout

```sh
# Linux / macOS
./bootstrap.sh

# Windows
pwsh -File ./bootstrap.ps1
```

Both scripts perform the same steps in the same order and print `KEY=VALUE` lines, so a
failed bootstrap names the step that failed:

```
GIT=ok
FLUTTER=3.47.7
DART=3.13.5
JDK=17
ANDROID_SDK=ok
WORKSPACE=ok
BOOTSTRAP=ok
```

`bootstrap` is idempotent. Re-running it after a partial failure resumes rather than
redoing completed work.

## Proving a change is acceptable

```sh
melos run verify
```

This runs `dart analyze`, `dart format --set-exit-if-changed` and both test suites (pure Dart
and Flutter). It is the same sequence CI runs on Linux, so a green local result predicts a green
CI result for everything that does not require a physical device.

After changing a drift table, run `melos run generate` and commit the regenerated `.g.dart`. CI
regenerates it and fails if the result differs, so a stale committed file is caught rather than
silently describing an older schema.

`storage_drift` deliberately does not depend on Flutter: `drift` opens a database file directly
and the path is an ordinary argument. That keeps every storage test, and the cold-open
measurement, runnable under `dart test` with no device and no widget binding.

Device-only measurements (ink latency, frame rate, cold-open) are a manual CI job; see
`docs/ux/test-protocol.md` for the bench procedure and `tools/logview` for reading its
output.

## Commands

| Command | What it does |
|---|---|
| `melos run verify` | The acceptance gate: lint + format-check + both test suites |
| `melos run generate` | Run drift's code generator (needed after a schema change) |
| `melos run lint` | Static analysis across the whole workspace |
| `melos run format-check` | Fail if any file is not `dart format` clean |
| `melos run format-fix` | Rewrite files into `dart format` shape |
| `melos run test-dart` | Unit tests of packages that need no Flutter SDK |
| `melos run test-flutter` | Widget tests of Flutter packages |
| `dart run logview bench.jsonl --metric ms --agg p50,p95` | Summarise a bench log |
| `lefthook install` | Install the pre-commit hook (once per checkout) |

## Layout

```
apps/mobile/                       Flutter application (android, ios, linux, windows)
packages/chart_core/               Pure Dart domain: model, grammar, transposer, layout
packages/chart_ui/                 Design system, docks, gestures
packages/ink_native/               Federated plugin container
  ink_native/                        App-facing package
  ink_native_platform_interface/      Contract shared by all implementations
  ink_native_ios/                     Swift + PencilKit
  ink_native_android/                 Kotlin InkView
packages/storage_drift/            SQLite schema, repositories, migrations
packages/telemetry/                Structured event schemas, batching, sinks
tools/logview/                     JSONL bench-log analyser (p50/p95)
tools/spike_harness/               Executable spikes S1-S5
docs/sdd.md                        The system design document
docs/contracts/                    Per-module PURPOSE/INPUTS/OUTPUTS/KEYWORDS
docs/fixtures/                     Hand-transcribed sketch fixtures
docs/ux/                           Gesture legend, tap budgets, test protocol
```
