// PURPOSE: Fix the shape of a ChartApp log event and the interface every destination must
//          implement, so that any package can record a structured fact in one line and any
//          later reader — tools/logview today, a server endpoint later — can consume it
//          without the producer knowing where the bytes end up.
// INPUTS: None.
// OUTPUTS: A library with no public API in Phase 0. The event envelope, the sink interface and
//          the local JSON Lines sink are the first work of Phase 1; this package exists now so
//          that every package written against it depends on a stable name.
// KEYWORDS: telemetry, event-envelope, jsonl, sink, ldd, phase-0, no-api-yet
//
// The event shape is the contract between a producer and tools/logview, and it is fixed here
// rather than inferred from whatever the first writer happens to emit:
//
//   {"v":1,"ts":"<ISO-8601 UTC>","run":"<run id>","name":"ink.stroke.committed",
//    "device":"Tab S8+","fields":{"pointerType":"sPen","durationMs":12.4}}
//
// The two fields that carry the design's weight are `name` and `fields`. `name` is a stable
// dotted identifier, because a dashboard grouping on free text is worthless. `fields` is a
// flat map of scalars, because logview selects a metric by one dotted path and groups by
// another; a nested structure would make a group key a serialised object rather than a label.
//
// Rationale for JSON Lines as the on-disk form: it appends without rewriting, survives a
// process killed mid-write by losing at most the final partial line, and is read line by line
// by tools/logview, which is written to report a malformed line and continue rather than
// abandon a whole bench run.
//
// What must never be recorded here: anything identifying a person, and any document content.
// Events describe what the editor did, not what the musician wrote.

/// Structured event schemas, batching and sinks for ChartApp.
library;
