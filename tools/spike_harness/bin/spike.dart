// PURPOSE: Provide the single entry point for the Phase 1 spikes, so that each spike is run the
//          same way and records its result in the same shape, and so a spike that is not yet
//          written fails with a clear message instead of pretending to have measured something.
// INPUTS: arguments — the process argv tail. The first positional argument is the spike id
//         (s1, s3, s4, s5). `--list` prints the registered spikes and which of them run.
// OUTPUTS: A process exit code, chosen so that a caller can tell the three outcomes apart:
//
//           0  the spike ran and every claim held
//           1  the spike ran and at least one claim failed — the design question is answered
//              NO, which is a result, not a crash
//           2  usage error, or the spike is registered but not implemented
//
//          The structured report goes to stdout as JSON Lines; progress and the human-readable
//          summary go to stderr, so `spike s3 > run.jsonl` yields a clean analysable file.
// KEYWORDS: spike, dispatch, entrypoint, exit-code, honest-failure, structured-logging
import 'dart:io';

import 'package:args/args.dart';
import 'package:spike_harness/spike_harness.dart';

/// Spike ids this harness knows about, with the question each one answers.
///
/// Kept complete even where the body is missing, so that `--list` shows the whole Phase 1
/// programme and an unimplemented spike is reported as unimplemented rather than as unknown.
const Map<String, String> registeredSpikes = <String, String>{
  's1': 'iReal Pro import: can the codec reproduce structure 100% and chords >= 99%?',
  's3': 'Transposer: does a 12-key round-trip return the original spelling?',
  's4': 'Layout: is a page laid out in under 16 ms?',
  's5': 'Storage: is cold-open under 1000 ms at p95?',
};

/// The spikes that can actually be run, keyed by id.
///
/// A spike is added here in the same change that makes its claim measurable. S1 is absent
/// because it cannot be measured without real iReal exports, and a body that reported numbers
/// from nowhere would be worse than an absent one.
///
/// The runners return futures because S5 measures a database, and drift's API is asynchronous
/// throughout. Rather than special-case the one spike, every runner is awaited, so a later spike
/// that needs to do I/O is added without touching the dispatcher.
final Map<String, Future<SpikeOutcome> Function()> _runnable =
    <String, Future<SpikeOutcome> Function()>{
      's3': () async => runSpikeS3(),
      's4': () async => runSpikeS4(),
      's5': runSpikeS5,
    };

Future<void> main(List<String> arguments) async {
  final ArgParser parser = ArgParser()
    ..addFlag('list', negatable: false, help: 'List the registered spikes.');

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('spike: ${error.message}');
    exit(2);
  }

  if (results.flag('list') || results.rest.isEmpty) {
    stdout.writeln('Registered spikes:');
    for (final MapEntry<String, String> entry in registeredSpikes.entries) {
      final String state = _runnable.containsKey(entry.key)
          ? 'runnable'
          : 'not implemented';
      stdout.writeln('  ${entry.key.padRight(4)} [$state] ${entry.value}');
    }
    // No spike named is a usage error; `--list` on its own is not.
    exit(results.flag('list') ? 0 : 2);
  }

  final String id = results.rest.first;
  if (!registeredSpikes.containsKey(id)) {
    stderr.writeln('spike: unknown spike "$id"');
    stderr.writeln('spike: known ids are ${registeredSpikes.keys.join(', ')}');
    exit(2);
  }

  final Future<SpikeOutcome> Function()? run = _runnable[id];
  if (run == null) {
    stderr.writeln(
      'spike: "$id" is registered but not implemented: ${registeredSpikes[id]}',
    );
    stderr.writeln(
      'spike: it needs input this harness cannot supply yet. No measurement was taken.',
    );
    exit(2);
  }

  final SpikeOutcome outcome = await run();
  outcome.report(stdout);

  stderr.writeln('spike ${outcome.id}: ${outcome.question}');
  for (final SpikeClaim claim in outcome.claims) {
    stderr.writeln(
      '  ${claim.passed ? 'PASS' : 'FAIL'}  ${claim.name}: ${claim.detail}',
    );
  }
  stderr.writeln('  verdict: ${outcome.passed ? 'PASS' : 'FAIL'}');

  exit(outcome.passed ? 0 : 1);
}
