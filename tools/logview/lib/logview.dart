// PURPOSE: Publish the logview public surface from one import, so the executable and the tests
//          depend on the same entry points rather than reaching into src/ directly.
// INPUTS: None.
// OUTPUTS: The statistics, JSONL parsing, path selection, analysis and runner APIs.
// KEYWORDS: barrel, public-api, logview
library;

export 'src/bench_analysis.dart';
export 'src/json_path.dart';
export 'src/jsonl.dart';
export 'src/runner.dart';
export 'src/statistics.dart';
