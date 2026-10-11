// PURPOSE: Be the one library the `.setlist` container is declared in. A `.setlist` file is a
//          programme: the setlist the musician built — its name and its ordered entries, each
//          naming a chart and how it is played — stored as a snapshot plus the tail of `setlist.*`
//          operations that come after it, so that a saved programme and a running programme are the
//          same thing and there is no second representation to keep in step.
// INPUTS: None. Every import the parts need is declared here, because a part file may not carry its
//         own imports.
// OUTPUTS: The public surface of the container: [SetlistFile] and its parts, the warnings a decode
//          reports, and [SetlistFileCodec]. The failures are the shared [ContainerException] family
//          declared in `container_frame.dart`, which this library re-exports, so a caller catches
//          one family around both a `.chart` and a `.setlist` file.
//          Import this file as `package:chart_core/src/container/setlist_file.dart`.
// KEYWORDS: setlist-file, container, codec, snapshot, op-log, programme, pure-dart
//
// WHY THIS IS A SECOND FORMAT AND NOT A SECOND FRAMING.
//
// The bytes before the header — the magic, the fixed prefix, the lengths, the two CRC-32 values and
// every check that decides a wrong file is truncated, corrupt or of an unknown version — are
// `container_frame.dart`, the same implementation `.chart` uses. What differs is what goes INSIDE:
// this header carries a setlist instead of a document and has no attachment region at all. A second
// framing beside a working one would be two places to fix the day a checksum or a length rule was
// wrong, and the two would drift; there is one framing and two headers.
//
// WHY THE ENVELOPE VERSION IS ITS OWN NUMBER.
//
// `setlistContainerVersion` is independent of `chartContainerVersion` even though the frame is
// shared, because the number describes the set of header keys a reader may treat as REQUIRED: the
// day a `.setlist` key becomes required, bumping the number must not make an old build refuse every
// `.chart` file as well.
//
// WHAT A `.setlist` FILE NAMES, AND WHAT IT DOES NOT.
//
// It names charts by `SetlistItem.chartIdentity` — a fact about the chart's own music — and not by
// the id the import happened to give the chart, which is a position in the payload the chart came
// from. It does NOT contain the charts themselves: a programme is a list of what to play, and
// copying each chart into it would make two copies of a tune that is played in several programmes.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../oplog/oplog.dart';
import 'container_frame.dart';

export 'container_frame.dart';

part 'setlist_file_codec.dart';
part 'setlist_file_format.dart';
part 'setlist_file_model.dart';
