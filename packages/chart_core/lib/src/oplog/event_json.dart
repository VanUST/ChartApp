// PURPOSE: Read the typed values an encoded document event is rebuilt from, turning every way an
//          event file can be wrong into one reported failure instead of a silently defaulted
//          field. A lost or mis-read field is a lost edit, so nothing here has a permissive
//          fallback: a missing key, a JSON value of the wrong type, an unknown enum name and an
//          unknown event type all raise [EventFormatException] naming the field that was wrong.
// INPUTS: A decoded JSON object and a key, or a JSON text holding one whole event line.
// OUTPUTS: The typed value. Every required reader throws [EventFormatException] rather than
//          returning null; the `optional` readers return null only when the key is absent or
//          carries JSON null, both of which are states the document model can represent (no
//          slash bass, no volta bracket). No reader ever returns a default invented on the
//          spot, because a default would make a corrupt event indistinguishable from a valid
//          one and the corruption would be found only when a musician noticed the wrong chart.
// KEYWORDS: json, decode, strict, event-format, failure-reporting, no-silent-default
part of 'oplog.dart';

/// Thrown when an encoded document event cannot be read back exactly.
///
/// A single exception type for every malformed event keeps the failure visible to a caller: the
/// alternative — skipping the line, or defaulting the field — is how an edit disappears from a
/// document without anybody being told.
class EventFormatException implements Exception {
  /// Creates a failure described by [message], optionally naming the offending [type].
  const EventFormatException(this.message, {this.type});

  /// What was wrong, in terms a caller can act on.
  final String message;

  /// The `type` discriminator of the event being read, when one was seen.
  final String? type;
  @override
  String toString() => type == null
      ? 'EventFormatException: $message'
      : 'EventFormatException: $message (event type "$type")';
}

/// Thrown when an encoded event names a `type` this build has no family for.
///
/// It extends [EventFormatException] rather than replacing it, so every existing caller that
/// treats a bad event as one failure keeps working. It is a separate type because it is not
/// corruption: it is the one ordinary way a file written by a NEWER build looks to an older one,
/// and a container that can keep reading the rest of such a file has to tell that case apart from
/// a field that was written wrong. Skipping the event is then a decision the container records,
/// not an accident.
class UnknownEventTypeException extends EventFormatException {
  /// Creates a failure describing the unknown [type] that was seen.
  const UnknownEventTypeException(super.message, {super.type});
}

/// Thrown when an encoded event carries a format version this build does not know.
///
/// Same reasoning as [UnknownEventTypeException]: a newer writer may bump the payload layout of an
/// event without changing the container envelope, and that is forward compatibility rather than a
/// malformed file. The message already names both versions, so no extra field is carried.
class UnsupportedEventVersionException extends EventFormatException {
  /// Creates a failure describing the version that was seen, naming its [type] when one was read.
  const UnsupportedEventVersionException(super.message, {super.type});
}

/// The strict readers used to rebuild an event from JSON.
///
/// Every reader is total in the sense that it either returns the value or throws; none of them
/// guesses. They are gathered here rather than repeated per event so that the rule "a required
/// field that is missing is a failure" is stated exactly once.
abstract final class EventJson {
  /// Parses [source] as a JSON object, which is the shape of one `events.jsonl` line.
  ///
  /// Throws [EventFormatException] when the text is not valid JSON or does not decode to an
  /// object. The line number is not reported here because this method sees one line at a time;
  /// [EventCodec] adds it when a whole file is read.
  static Map<String, Object?> decodeObject(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw EventFormatException('not valid JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw EventFormatException(
        'expected a JSON object, found ${_describe(decoded)}',
      );
    }
    return decoded;
  }

  /// Reads the object stored at [key], or throws when it is absent or of another type.
  static Map<String, Object?> object(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! Map<String, Object?>) {
      throw EventFormatException(
        'field "$key" must be a JSON object, found ${_describe(value)}',
      );
    }
    return value;
  }

  /// Reads the object stored at [key], or null when the key is absent or null.
  static Map<String, Object?>? optionalObject(
    Map<String, Object?> json,
    String key,
  ) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    return object(json, key);
  }

  /// Reads the array stored at [key], or throws when it is absent or of another type.
  static List<Object?> array(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! List<Object?>) {
      throw EventFormatException(
        'field "$key" must be a JSON array, found ${_describe(value)}',
      );
    }
    return value;
  }

  /// Reads the string stored at [key], or throws when it is absent or of another type.
  static String string(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! String) {
      throw EventFormatException(
        'field "$key" must be a string, found ${_describe(value)}',
      );
    }
    return value;
  }

  /// Reads the string stored at [key], or null when the key is absent or null.
  static String? optionalString(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    return string(json, key);
  }

  /// Reads the integer stored at [key], or throws when it is absent or not an `int`.
  ///
  /// A JSON `3.0` is NOT accepted for an integer field: it means the writer encoded a fractional
  /// value where the model holds none, and rounding it here would hide that.
  static int integer(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! int) {
      throw EventFormatException(
        'field "$key" must be an integer, found ${_describe(value)}',
      );
    }
    return value;
  }

  /// Reads the integer stored at [key], or null when the key is absent or null.
  static int? optionalInteger(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    return integer(json, key);
  }

  /// Reads the number stored at [key] as a `double`, or throws when it is not a number.
  ///
  /// An integral JSON value is accepted and widened, because JSON has no separate integer type
  /// and a writer is free to emit `0` where the model holds `0.0`.
  static double number(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is int) {
      return value.toDouble();
    }
    if (value is double) {
      return value;
    }
    throw EventFormatException(
      'field "$key" must be a number, found ${_describe(value)}',
    );
  }

  /// Reads the boolean stored at [key], or throws when it is absent or of another type.
  static bool boolean(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is! bool) {
      throw EventFormatException(
        'field "$key" must be a boolean, found ${_describe(value)}',
      );
    }
    return value;
  }

  /// Reads the number stored at [key], or null when the key is absent or null.
  static double? optionalNumber(Map<String, Object?> json, String key) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    return number(json, key);
  }

  /// Resolves an enum [name] against [values] for the field called [field].
  ///
  /// Throws [EventFormatException] for an unknown name rather than falling back to the first
  /// value: an enum that gained a member in a newer writer must be reported, not quietly mapped
  /// onto a different one.
  static T enumeration<T extends Enum>(
    List<T> values,
    String name,
    String field,
  ) {
    for (final T value in values) {
      if (value.name == name) {
        return value;
      }
    }
    throw EventFormatException(
      'field "$field" names no ${T.toString()}: "$name"',
    );
  }

  /// Describes [value] for a failure message, keeping null distinguishable from "wrong type".
  static String _describe(Object? value) {
    if (value == null) {
      return 'null';
    }
    return '${value.runtimeType}';
  }
}
