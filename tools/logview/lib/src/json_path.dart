// PURPOSE: Resolve a dotted field path such as "payload.durationMs" against a decoded JSON
//          value, so logview can address nested bench fields without the tool knowing any
//          particular event schema in advance. The bench log shape is decided by the spike
//          harness that produces it, not by this analyser, so the analyser must not hard-code
//          field names.
// INPUTS: root — any decoded JSON value (map, list, scalar or null). path — a non-empty
//         dot-separated string; a segment of digits indexes into a list.
// OUTPUTS: The value found at path, or null when any segment is missing, when a list index is
//          out of range, or when the path descends through a scalar. Never throws for missing
//          data. A path that reaches an explicit JSON null and a path that does not exist both
//          yield null; callers cannot distinguish them, and do not need to, because both mean
//          "there is no value here".
// KEYWORDS: json, path, lookup, field-selection, schema-agnostic, dotted-path
/// Returns the value at [path] inside [root], or null when it is absent.
Object? selectPath(Object? root, String path) {
  Object? current = root;
  for (final String segment in path.split('.')) {
    if (segment.isEmpty) {
      return null;
    }
    if (current is Map<Object?, Object?>) {
      if (!current.containsKey(segment)) {
        return null;
      }
      current = current[segment];
    } else if (current is List<Object?>) {
      final int? index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        return null;
      }
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}
