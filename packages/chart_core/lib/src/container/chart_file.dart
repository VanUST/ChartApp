// PURPOSE: Be the one library the `.chart` container is declared in. Everything a chart file is
//          made of — its envelope, its metadata, the document snapshot, the operation tail it
//          carries and its embedded PDFs — is one file format with one codec, and it is written
//          here as one library split for readability so that a `sealed` class (an exception, a
//          PDF placement) can be extended by its own part and by nothing else.
// INPUTS: None. Every import the parts need is declared here, because a part file may not carry
//         its own imports.
// OUTPUTS: The public surface of the container: [ChartFile] and its parts, the exception
//          hierarchy a caller catches, the warnings a decode reports, and [ChartFileCodec].
//          Import this file as `package:chart_core/src/container/chart_file.dart`.
// KEYWORDS: chart-file, container, codec, snapshot, op-log, pdf, d19, pure-dart
//
// WHAT A `.chart` FILE IS, AND WHY IT IS BUILT AROUND THE OP-LOG.
//
// A `.chart` file is the serialised form of one document: the song, its anchored marks and the
// operation log that produced them. The log is already the spine of undo, autosave and a future
// sync, so making it the spine of the file means a saved chart and a running chart are the same
// thing — there is no second representation to keep in step.
//
// The file carries BOTH a materialised snapshot of the document and the tail of operations that
// come after it. That is deliberate, and it is what makes the format usable by a build that does
// not understand every operation in it: the snapshot still yields the song the writer saw, and
// the operations the reader cannot read are reported as warnings rather than silently dropped.
// A reader that cannot understand an operation is therefore not forced to choose between
// "whole file refused" and "empty document", which is the failure this container must not have.
//
// WHY THE ENVELOPE IS BINARY AND THE PAYLOAD IS NOT.
//
// D19 embeds a PDF inline when it is at most 50 MB per song. Base64 inside a JSON text file would
// inflate that by a third and put a 67 MB string through the JSON encoder, so the envelope is a
// fixed binary frame with a checksummed UTF-8 JSON header and a raw byte region for the embedded
// PDFs. The header is JSON, so the metadata, the snapshot and the operations are still readable by
// any tool; only the bytes a PDF already is are kept as bytes.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../oplog/oplog.dart';

part 'chart_file_codec.dart';
part 'chart_file_format.dart';
part 'chart_file_model.dart';
