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

## Where it runs

The application is distributed as a **web page**, installable to the home screen, and the
native targets stay for the quality they give where it matters. That is a recorded decision
(D20 in `docs/sdd.md`) rather than a preference: the stores are not reachable from every
country a musician may live in, and a page needs no account, no signing step and no review.

The same Dart code serves every target. The only platform-bound part is the ink, and it sits
behind one seam (`packages/ink_native`): Android supplies raw stylus input through a
PlatformView, the web supplies Pointer Events, and a stroke is canonicalised into ONE stored
form either way — so a chart written on one device opens on the other.

User data lives in **files the musician keeps**, not in browser storage. That is not tidiness:
Safari deletes script-writable storage after seven days of no interaction, and a file the user
holds is what makes that harmless.

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

**`lefthook install` is a step, not a claim.** As committed, `.git/hooks` holds only the shipped
samples and `lefthook` is not on most machines' PATH, so NOTHING RUNS ON COMMIT until someone
runs that command in their own checkout. The project declaration lists that honestly: see
`.dsh/project.json`, rule `commit-runs-the-fast-checks`, which is marked pending rather than
enforced.

`bootstrap` does not install the hook either, so the gate you actually depend on is the one you
run: `melos run verify`.

## The project declaration

`.dsh/project.json` names this project's languages, its verification commands, and every rule
it claims **together with the command that fails when that rule is broken**. A rule with no such
command is listed as pending rather than as enforced, so the file states what is true — including
the rules nothing currently checks. Read it with the `context_rules` tool, or as a file.

## Layout

```
apps/mobile/                       Flutter application (android, ios, linux, windows, web)
apps/mobile/web/                   The web target's shell, manifest and icons
packages/chart_core/               Pure Dart domain: model, grammar, transposer, layout,
                                     the op-log, the .chart container, the play-order derivation
packages/chart_ui/                 Design system, painters, gestures
packages/ink_native/               Federated plugin container
  ink_native/                        App-facing package
  ink_native_platform_interface/      Contract shared by all implementations
  ink_native_ios/                     Swift + PencilKit
  ink_native_android/                 Kotlin InkView
packages/storage_drift/            SQLite schema, repositories, migrations
packages/telemetry/                Structured event schemas, batching, sinks
tools/logview/                     JSONL bench-log analyser (p50/p95)
tools/spike_harness/               Executable spikes S1-S5
tools/web_pen_spike/               Page that measures what a browser gives a stylus
.dsh/project.json                  Languages, verification commands and rules
docs/sdd.md                        The design record: decisions, and what is NOT done
docs/fixtures/                     Hand-transcribed sketch fixtures
docs/ux/                           Gesture legend, tap budgets, test protocol
```
