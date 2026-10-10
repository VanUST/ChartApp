// PURPOSE: Provide the single entry point for the Phase 1 spikes, so that each spike is run
//          the same way and records its result in the same shape, and so a spike that is not
//          yet written fails with a clear message instead of a null dereference.
// INPUTS: arguments — the process argv tail. The first positional argument is the spike id
//         (s1, s3, s4, s5). `--list` prints the registered spikes.
// OUTPUTS: A process exit code. 0 when the named spike ran to completion; 2 for an unknown or
//          missing spike id. Spike programs are added in Phase 1; until then every id reports
//          that it is not implemented and exits 2, rather than pretending to have measured
//          something.
// KEYWORDS: spike, dispatch, entrypoint, phase-1, honest-failure
import 'dart:io';

import 'package:args/args.dart';

/// Spike ids this harness knows about, with the question each one answers.
///
/// Registered here in Phase 0 so the CI job and the documentation can name them; the bodies
/// are Phase 1 work.
const Map<String, String> registeredSpikes = <String, String>{
  's1': 'iReal Pro import: can the codec reproduce structure 100% and chords >= 99%?',
  's3': 'Transposer: does a 12-key round-trip return the original spelling?',
  's4': 'Layout: is a page laid out in under 16 ms?',
  's5': 'Storage: is cold-open under 1000 ms at p95?',
};

void main(List<String> arguments) {
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
      stdout.writeln('  ${entry.key.padRight(4)} ${entry.value}');
    }
    exit(results.rest.isEmpty ? 2 : 0);
  }

  final String id = results.rest.first;
  final String? question = registeredSpikes[id];
  if (question == null) {
    stderr.writeln('spike: unknown spike "$id"');
    stderr.writeln('spike: known ids are ${registeredSpikes.keys.join(', ')}');
    exit(2);
  }

  stderr.writeln('spike: "$id" is not implemented yet ($question)');
  stderr.writeln(
    'spike: implementation is Phase 1 work; no measurement was taken.',
  );
  exit(2);
}
