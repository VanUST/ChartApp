// PURPOSE: Name the two things a setting needs and nothing else: which language the interface is
//          in, and where that answer is kept between runs. It is deliberately Dart and not Flutter,
//          so the choice and its storage can be exercised without a widget tree, and so the two
//          platform implementations of [SettingsStore] are the only files that know a platform
//          exists at all.
// INPUTS: None — this file is a vocabulary. `settings_store.dart` re-exports it beside the
//         platform's own implementation, and `settings_store_io.dart` / `settings_store_web.dart`
//         each provide `loadSettingsStore()`.
// OUTPUTS: [LanguageChoice], the three states a musician can leave the language in, and
//          [SettingsStore], the read/write pair a platform must answer. Both `readLanguage` and
//          `writeLanguage` are SYNCHRONOUS, which is a decision rather than an oversight — see
//          [LanguageChoice] and `main.dart`.
// KEYWORDS: settings, language, preference, storage, platform-seam, contract, synchronous, d20
//
// WHY THE CHOICE IS THREE STATES AND NOT TWO. The requirement is that a Russian device opens in
// Russian with nobody finding a switch, and that an explicit choice then overrides the device from
// then on. Those are two different facts and a boolean cannot hold both: a two-state "russian:
// true/false" would make "I never chose" indistinguishable from "I chose English", so a Russian
// device whose owner once picked English and then cleared the preference could not be told from one
// that had never been touched. [LanguageChoice.system] is the absence of a choice; the other two are
// choices, and they win.
//
// WHY IT IS NOT A FILE LIKE THE MUSIC. Owner decision D20 puts the musician's DATA in files, and
// the language is not data: it is a property of the interface, it is worth nothing to the musician,
// it is meaningful on the device that holds it and nowhere else, and losing it costs one tap. A
// `.chart` file is the opposite of all four. So the setting lives where settings live on each
// platform, and `docs/sdd.md` records the consequence on the web rather than hiding it.

/// The language the interface is drawn in.
///
/// The three states exist because "no choice yet" and "chose English" must be distinguishable: a
/// device whose language is Russian must open in Russian until its owner says otherwise, and must
/// stay in English afterwards even though the device is still Russian.
enum LanguageChoice {
  /// Follow whatever the device is set to, re-decided on every launch.
  ///
  /// The state a first run is in. The device's own language is the right guess — a musician's phone
  /// is already in the language they read — and it costs no switch to be found.
  system,

  /// English, chosen explicitly. Outranks the device's language from then on.
  english,

  /// Russian, chosen explicitly. Outranks the device's language from then on.
  russian;

  /// The BCP-47 tag this choice names, or null when the device decides.
  ///
  /// Null rather than `en` for [system] because a null locale is what tells Flutter's own locale
  /// resolution to consult the device — resolving it here instead would hard-code the device's
  /// language at this layer and defeat `supportedLocales`.
  String? get languageCode => switch (this) {
    LanguageChoice.system => null,
    LanguageChoice.english => 'en',
    LanguageChoice.russian => 'ru',
  };

  /// The value a [SettingsStore] persists for this choice, and the value [fromLanguageCode] reads
  /// back.
  ///
  /// `system` is spelled out rather than left as an empty string or a missing key, because "the
  /// musician went back to following the device" is a decision and should be visible in the file as
  /// one.
  ///
  /// THIS IS THE TAG AND NOT THE ENUM'S `name`, AND THAT IS A CORRECTNESS REQUIREMENT RATHER THAN A
  /// STYLE CHOICE. Writing `name` here once shipped a store whose writer and reader disagreed about
  /// the format: `readLanguage` handed back `english`, [fromLanguageCode] recognized only tags, and
  /// an explicit choice silently degraded to [system]. On a Russian device that was INVISIBLE —
  /// falling back to the device produced Russian either way — so the defect looked like a passing
  /// test. It was found by asking a Russian browser for ENGLISH and checking that the answer
  /// survived a reload; see `docs/sdd.md`. One field, written by both stores and read by one
  /// function, is what keeps the two ends of that conversation in one vocabulary.
  String get storageValue => languageCode ?? 'system';

  /// The choice a stored value names, or [system] when the value names no choice at all.
  ///
  /// Reads what [storageValue] writes: `en`, `ru`, a region-qualified tag such as `en-US`, or the
  /// literal `system`.
  ///
  /// TOTAL ON PURPOSE. A settings file that was hand-edited, truncated by a half-written flush or
  /// written by a future version that knew a language this build does not is not a reason to fail
  /// to start: an unreadable preference degrades to "follow the device", which is the state the
  /// application ships in. The caller stores the return value rather than the raw tag, so the file
  /// is rewritten in the shape this build understands on the next change.
  static LanguageChoice fromLanguageCode(String? code) {
    if (code == null) {
      return LanguageChoice.system;
    }
    final String normalized = code.trim().toLowerCase();
    // A region-qualified tag such as `ru-RU` or `en_US` names the same choice as its language half,
    // because this application has one English and one Russian and no regional variants of either.
    final String language = normalized.split(RegExp('[-_]')).first;
    return switch (language) {
      'en' => LanguageChoice.english,
      'ru' => LanguageChoice.russian,
      _ => LanguageChoice.system,
    };
  }
}

/// Where a platform keeps the language choice between launches.
///
/// Both directions are SYNCHRONOUS. That is the whole reason this interface exists rather than a
/// future-returning one: `main()` reads the choice before the first frame, so the application never
/// paints in one language and then swaps to another, and a change takes effect on the next frame
/// rather than after an await that a test would have to pump. The two platforms this application
/// actually runs on both offer a synchronous answer — a file read on a native target, `localStorage`
/// in a browser — so a future here would buy nothing and cost a flash of the wrong language.
abstract interface class SettingsStore {
  /// The stored choice, or null when nothing has ever been stored.
  ///
  /// NULL IS NOT [LanguageChoice.system]. Null means the device has no opinion on file; `system` in
  /// the file means the musician went back to following the device on purpose. Both end up in the
  /// same place this build, and they are kept apart because they are different answers, and a later
  /// build that wants to distinguish them should not have to migrate the file to get them back.
  LanguageChoice? readLanguage();

  /// Store [choice] as the preference from now on.
  ///
  /// A failure to write is NOT reported to the caller: every implementation swallows it after
  /// logging, because the setting has already taken effect on screen and a musician who cannot
  /// write a preference file should not be told their language change failed when it visibly
  /// worked. What it costs is named at the implementation.
  void writeLanguage(LanguageChoice choice);
}

/// A [SettingsStore] that keeps nothing past the process, for tests and for any caller that does
/// not want to touch a platform.
///
/// It is the DEFAULT `ChartApp` is built with, so a widget test that pumps the application reads and
/// writes no file, and so the choice a test makes cannot leak into the next test or into the
/// developer's own machine.
class VolatileSettingsStore implements SettingsStore {
  /// The value most recently written, or null before the first write.
  LanguageChoice? _choice;

  @override
  LanguageChoice? readLanguage() => _choice;

  @override
  void writeLanguage(LanguageChoice choice) {
    _choice = choice;
  }
}
