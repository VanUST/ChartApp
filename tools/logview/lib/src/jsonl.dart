// PURPOSE: Parse a JSON Lines bench log into records plus diagnostics. A bench run is
//          long-lived and writes while the device is under load, so a truncated final line or
//          an interleaved native log line is expected rather than exceptional; the analyser
//          must report such lines and keep going instead of aborting the whole run.
// INPUTS: parseJsonl(contents) takes the whole log as text. Blank and whitespace-only lines
//         are skipped silently because trailing newlines are normal.
// OUTPUTS: A JsonlReadResult holding every line that decoded to a JSON object, in file order,
//          each tagged with its 1-based line number, plus one JsonlIssue per line that did
//          not. A line that is valid JSON but not an object (a bare number, string, array) is
//          an issue, not a record. Never throws for malformed content.
// KEYWORDS: jsonl, json-lines, parser, diagnostics, resilience, bench-log
//
// Split out from the analyser so that reading is testable without touching the filesystem.

import 'dart:convert';

/// One successfully decoded JSON-object line.
class JsonlRecord {
  /// Creates a record for [line] (1-based) carrying the decoded object [data].
  const JsonlRecord({required this.line, required this.data});

  /// 1-based line number in the source log, used to point a human at the offending input.
  final int line;

  /// The decoded JSON object. Always a `Map<String, Object?>` in practice.
  final Map<String, Object?> data;
}

/// One line that could not be used, with the reason.
class JsonlIssue {
  /// Creates an issue for [line] (1-based) with a human-readable [message].
  const JsonlIssue({required this.line, required this.message});

  /// 1-based line number in the source log.
  final int line;

  /// Why the line was rejected.
  final String message;

  @override
  String toString() => 'line $line: $message';
}

/// The outcome of parsing a log: usable records and rejected lines.
class JsonlReadResult {
  /// Creates a result from [records] and [issues].
  const JsonlReadResult({required this.records, required this.issues});

  /// Every line that decoded to a JSON object, in file order.
  final List<JsonlRecord> records;

  /// Every line that did not, in file order.
  final List<JsonlIssue> issues;
}

/// Parses [contents] as JSON Lines into records and issues.
JsonlReadResult parseJsonl(String contents) {
  final List<JsonlRecord> records = <JsonlRecord>[];
  final List<JsonlIssue> issues = <JsonlIssue>[];
  final List<String> lines = contents.split('\n');

  for (int index = 0; index < lines.length; index++) {
    final int lineNumber = index + 1;
    // A Windows-written log uses CRLF; strip the carriage return so it does not reach the
    // JSON decoder and so a trailing blank line is recognised as blank.
    final String raw = lines[index].endsWith('\r')
        ? lines[index].substring(0, lines[index].length - 1)
        : lines[index];
    if (raw.trim().isEmpty) {
      continue;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      issues.add(
        JsonlIssue(
          line: lineNumber,
          message: 'invalid JSON (${error.message})',
        ),
      );
      continue;
    }
    if (decoded is! Map<String, Object?>) {
      issues.add(JsonlIssue(line: lineNumber, message: 'not a JSON object'));
      continue;
    }
    records.add(JsonlRecord(line: lineNumber, data: decoded));
  }
  return JsonlReadResult(records: records, issues: issues);
}
