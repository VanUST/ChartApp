// PURPOSE: Turn a song the app is showing into the `.chart` document that will be written, in one
//          place, so that the save button, a probe and any future exporter all produce the same
//          file. A second construction of the metadata would be a second chance to write a document
//          id that does not match what the file records.
// INPUTS: A written [Song], and the instant to record as the document's modification time.
// OUTPUTS: A [ChartFile] whose snapshot is that song and whose operation tail is empty. Deliberately
//          free of Flutter, so it can be exercised by `dart run` without a window.
// KEYWORDS: chart-file, document, snapshot, metadata, doc-id, d19, d20, flutter-free
import 'package:chart_core/chart_core.dart';

/// The document id written when a song carries none of its own.
///
/// The container requires a non-empty document id, because an operation log needs a document to
/// belong to. A song that has never been assigned one — a chart typed from scratch, before any
/// store has given it an identity — is written under this one rather than being refused.
const String untitledDocumentId = 'chartapp-untitled';

// PURPOSE: Build the document a song is saved as.
// INPUTS: song — the WRITTEN chart, never the transposed view. modifiedAt — the instant to record,
//         or null to record none. Nothing here reads a clock: the caller that has one passes it.
// OUTPUTS: A [ChartFile] with an empty operation tail and no attachments. The tail is empty because
//          the reader has no editing UI yet; the container is built to carry one, and a document
//          with no operations is its ordinary empty-log case, not a special one.
// KEYWORDS: chart-file, snapshot, empty-log, written-form, metadata, doc-id
/// Returns the `.chart` document that represents [song] as it stands.
ChartFile chartFileFor(Song song, {DateTime? modifiedAt}) => ChartFile(
  metadata: ChartMetadata(
    docId: song.id.isEmpty ? untitledDocumentId : song.id,
    modifiedAt: modifiedAt?.toUtc(),
    writer: 'chartapp',
  ),
  snapshot: DocumentState(song: song),
);
