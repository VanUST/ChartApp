// PURPOSE: Be the one library the document event catalogue is declared in. Dart allows a sealed
//          class to be extended only inside its own library, so the catalogue's exhaustiveness
//          guarantee — a consumer that switches over the events is told by the compiler when a
//          family is added — costs this file: every part below is a section of the same library
//          rather than a library of its own. The alternative, a hierarchy that is not sealed,
//          would compile and would let a new event family be applied by nobody.
// INPUTS: None. Every import the parts need is declared here, because a part file may not carry
//         its own imports.
// OUTPUTS: The public surface of the catalogue: the event hierarchy, the codec, the reducer, and
//          the value types an event payload carries. Import this file as
//          `package:chart_core/src/oplog/oplog.dart`.
// KEYWORDS: op-log, event-catalogue, library, part, sealed-hierarchy, exhaustive-switch
//
// WHY THE FILES ARE PARTS AND NOT SEPARATE LIBRARIES.
//
// The requirement that a `switch` over the events be exhaustive is what a sealed hierarchy buys,
// and Dart grants `sealed` only within one library. The files below are therefore one library
// split for readability: the base and its branches in one part, a family per part, the codec in
// one, the reducer in one. Adding a part here and an event class in it makes the compiler demand
// a case in the reducer and a case in the codec, which is exactly the pressure this design wants.
library;

import 'dart:convert';

import '../anchored_place.dart';
import '../chord.dart';
import '../key.dart';
import '../pitch.dart';
import '../song/bar.dart';
import '../song/section.dart';
import '../song/song.dart';
import '../song/time_signature.dart';
import '../spelling_table.dart';

// The place type lives outside this library, because the song model carries places too and a
// model may not depend on the operation log. It is RE-EXPORTED rather than merely imported for two
// reasons: every event's `anchor` getter returns one, so a caller of this library has to be able to
// name the type; and until this change it lived in `anchor.dart` as a part of this very library, so
// re-exporting it is what keeps the public surface of the catalogue the same shape it was.
//
// library cannot carry imports of their own, and the edit session — a part — still builds a place
// from a cell while the surface speaks in beats. Both exports go together when the shim dies.
export '../anchored_place.dart';

part '../editing/edit_session.dart';
part '../editing/setlist_session.dart';
part 'document_edits.dart';
part 'document_event.dart';
part 'document_reducer.dart';
part 'document_state.dart';
part 'event_codec.dart';
part 'event_json.dart';
part 'ink.dart';
part 'ink_events.dart';
part 'model_json.dart';
part 'setlist.dart';
part 'setlist_events.dart';
part 'size_events.dart';
part 'song_events.dart';
part 'text_cue.dart';
part 'textcue_events.dart';
