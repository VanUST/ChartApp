// PURPOSE: The `logview` process entry point. It is deliberately one statement long: all
//          behaviour lives in `runLogview`, which takes its output sinks as arguments and is
//          therefore exercised by the package's tests without spawning a process.
// INPUTS: arguments — the process argv tail.
// OUTPUTS: Never returns: terminates the process with runLogview's exit code.
// KEYWORDS: entrypoint, executable, logview, thin-shell
import 'dart:io';

import 'package:logview/logview.dart';

void main(List<String> arguments) {
  exit(runLogview(arguments, out: stdout, err: stderr));
}
