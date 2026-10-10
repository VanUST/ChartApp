// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $DocumentsTable extends Documents
    with TableInfo<$DocumentsTable, Document> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _songKeyMeta = const VerificationMeta(
    'songKey',
  );
  @override
  late final GeneratedColumn<String> songKey = GeneratedColumn<String>(
    'song_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('C major'),
  );
  static const VerificationMeta _bpmMeta = const VerificationMeta('bpm');
  @override
  late final GeneratedColumn<int> bpm = GeneratedColumn<int>(
    'bpm',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotJsonMeta = const VerificationMeta(
    'snapshotJson',
  );
  @override
  late final GeneratedColumn<String> snapshotJson = GeneratedColumn<String>(
    'snapshot_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snapshotSeqMeta = const VerificationMeta(
    'snapshotSeq',
  );
  @override
  late final GeneratedColumn<int> snapshotSeq = GeneratedColumn<int>(
    'snapshot_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    songKey,
    bpm,
    updatedAt,
    snapshotJson,
    snapshotSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<Document> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('song_key')) {
      context.handle(
        _songKeyMeta,
        songKey.isAcceptableOrUnknown(data['song_key']!, _songKeyMeta),
      );
    }
    if (data.containsKey('bpm')) {
      context.handle(
        _bpmMeta,
        bpm.isAcceptableOrUnknown(data['bpm']!, _bpmMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('snapshot_json')) {
      context.handle(
        _snapshotJsonMeta,
        snapshotJson.isAcceptableOrUnknown(
          data['snapshot_json']!,
          _snapshotJsonMeta,
        ),
      );
    }
    if (data.containsKey('snapshot_seq')) {
      context.handle(
        _snapshotSeqMeta,
        snapshotSeq.isAcceptableOrUnknown(
          data['snapshot_seq']!,
          _snapshotSeqMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Document map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Document(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      songKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_key'],
      )!,
      bpm: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bpm'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}updated_at'],
      )!,
      snapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_json'],
      ),
      snapshotSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_seq'],
      )!,
    );
  }

  @override
  $DocumentsTable createAlias(String alias) {
    return $DocumentsTable(attachedDatabase, alias);
  }
}

class Document extends DataClass implements Insertable<Document> {
  /// Document identity, and the key every other table refers to.
  final String id;

  /// The title as written.
  final String title;

  /// The key the chart is written in, as a spelled tonic plus mode.
  ///
  /// Stored as text because a key is not a number: C-sharp major and D-flat major sound alike and
  /// are different keys, and a numeric pitch class would throw that distinction away at the
  /// storage boundary, where it is hardest to recover.
  ///
  /// The design document names this column `key`. It is called `songKey` here because `key` is a
  /// name Dart reserves in enough contexts to make the generated accessors awkward.
  final String songKey;

  /// Tempo in beats per minute, or 0 when the chart sets none.
  final int bpm;

  /// When this row was last written, as an ISO-8601 UTC string.
  ///
  /// Text rather than a native date type so that the stored value is exactly what the writer
  /// produced: no timezone interpretation happens on the way in or out, and ISO-8601 UTC sorts
  /// lexicographically, so "most recently updated" is still an ordinary ORDER BY.
  final String updatedAt;

  /// The snapshot: a serialised document as of [snapshotSeq], or null when no snapshot has been
  /// taken and the whole history is in the event tail.
  final String? snapshotJson;

  /// The sequence number the snapshot folds up to.
  ///
  /// Reading a document is: take this snapshot, then apply every event with a greater sequence.
  /// Nothing else is read, which is what makes open cost proportional to the tail rather than to
  /// the document's whole history.
  final int snapshotSeq;
  const Document({
    required this.id,
    required this.title,
    required this.songKey,
    required this.bpm,
    required this.updatedAt,
    this.snapshotJson,
    required this.snapshotSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['song_key'] = Variable<String>(songKey);
    map['bpm'] = Variable<int>(bpm);
    map['updated_at'] = Variable<String>(updatedAt);
    if (!nullToAbsent || snapshotJson != null) {
      map['snapshot_json'] = Variable<String>(snapshotJson);
    }
    map['snapshot_seq'] = Variable<int>(snapshotSeq);
    return map;
  }

  DocumentsCompanion toCompanion(bool nullToAbsent) {
    return DocumentsCompanion(
      id: Value(id),
      title: Value(title),
      songKey: Value(songKey),
      bpm: Value(bpm),
      updatedAt: Value(updatedAt),
      snapshotJson: snapshotJson == null && nullToAbsent
          ? const Value.absent()
          : Value(snapshotJson),
      snapshotSeq: Value(snapshotSeq),
    );
  }

  factory Document.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Document(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      songKey: serializer.fromJson<String>(json['songKey']),
      bpm: serializer.fromJson<int>(json['bpm']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      snapshotJson: serializer.fromJson<String?>(json['snapshotJson']),
      snapshotSeq: serializer.fromJson<int>(json['snapshotSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'songKey': serializer.toJson<String>(songKey),
      'bpm': serializer.toJson<int>(bpm),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'snapshotJson': serializer.toJson<String?>(snapshotJson),
      'snapshotSeq': serializer.toJson<int>(snapshotSeq),
    };
  }

  Document copyWith({
    String? id,
    String? title,
    String? songKey,
    int? bpm,
    String? updatedAt,
    Value<String?> snapshotJson = const Value.absent(),
    int? snapshotSeq,
  }) => Document(
    id: id ?? this.id,
    title: title ?? this.title,
    songKey: songKey ?? this.songKey,
    bpm: bpm ?? this.bpm,
    updatedAt: updatedAt ?? this.updatedAt,
    snapshotJson: snapshotJson.present ? snapshotJson.value : this.snapshotJson,
    snapshotSeq: snapshotSeq ?? this.snapshotSeq,
  );
  Document copyWithCompanion(DocumentsCompanion data) {
    return Document(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      songKey: data.songKey.present ? data.songKey.value : this.songKey,
      bpm: data.bpm.present ? data.bpm.value : this.bpm,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      snapshotJson: data.snapshotJson.present
          ? data.snapshotJson.value
          : this.snapshotJson,
      snapshotSeq: data.snapshotSeq.present
          ? data.snapshotSeq.value
          : this.snapshotSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Document(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('songKey: $songKey, ')
          ..write('bpm: $bpm, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('snapshotSeq: $snapshotSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    songKey,
    bpm,
    updatedAt,
    snapshotJson,
    snapshotSeq,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Document &&
          other.id == this.id &&
          other.title == this.title &&
          other.songKey == this.songKey &&
          other.bpm == this.bpm &&
          other.updatedAt == this.updatedAt &&
          other.snapshotJson == this.snapshotJson &&
          other.snapshotSeq == this.snapshotSeq);
}

class DocumentsCompanion extends UpdateCompanion<Document> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> songKey;
  final Value<int> bpm;
  final Value<String> updatedAt;
  final Value<String?> snapshotJson;
  final Value<int> snapshotSeq;
  final Value<int> rowid;
  const DocumentsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.songKey = const Value.absent(),
    this.bpm = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.snapshotJson = const Value.absent(),
    this.snapshotSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.songKey = const Value.absent(),
    this.bpm = const Value.absent(),
    required String updatedAt,
    this.snapshotJson = const Value.absent(),
    this.snapshotSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       updatedAt = Value(updatedAt);
  static Insertable<Document> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? songKey,
    Expression<int>? bpm,
    Expression<String>? updatedAt,
    Expression<String>? snapshotJson,
    Expression<int>? snapshotSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (songKey != null) 'song_key': songKey,
      if (bpm != null) 'bpm': bpm,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (snapshotJson != null) 'snapshot_json': snapshotJson,
      if (snapshotSeq != null) 'snapshot_seq': snapshotSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? songKey,
    Value<int>? bpm,
    Value<String>? updatedAt,
    Value<String?>? snapshotJson,
    Value<int>? snapshotSeq,
    Value<int>? rowid,
  }) {
    return DocumentsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      songKey: songKey ?? this.songKey,
      bpm: bpm ?? this.bpm,
      updatedAt: updatedAt ?? this.updatedAt,
      snapshotJson: snapshotJson ?? this.snapshotJson,
      snapshotSeq: snapshotSeq ?? this.snapshotSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (songKey.present) {
      map['song_key'] = Variable<String>(songKey.value);
    }
    if (bpm.present) {
      map['bpm'] = Variable<int>(bpm.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (snapshotJson.present) {
      map['snapshot_json'] = Variable<String>(snapshotJson.value);
    }
    if (snapshotSeq.present) {
      map['snapshot_seq'] = Variable<int>(snapshotSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('songKey: $songKey, ')
          ..write('bpm: $bpm, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('snapshotJson: $snapshotJson, ')
          ..write('snapshotSeq: $snapshotSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocumentEventsTable extends DocumentEvents
    with TableInfo<$DocumentEventsTable, DocumentEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocumentEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _tsMeta = const VerificationMeta('ts');
  @override
  late final GeneratedColumn<String> ts = GeneratedColumn<String>(
    'ts',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [docId, seq, deviceId, ts, type, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'document_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<DocumentEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {docId, seq};
  @override
  DocumentEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocumentEvent(
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      ts: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ts'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
    );
  }

  @override
  $DocumentEventsTable createAlias(String alias) {
    return $DocumentEventsTable(attachedDatabase, alias);
  }
}

class DocumentEvent extends DataClass implements Insertable<DocumentEvent> {
  /// The document this event belongs to.
  final String docId;

  /// Position in this document's log. Unique per document, assigned by the writer.
  final int seq;

  /// Identifier of the device that produced the event, for attributing a merge.
  final String deviceId;

  /// When the event was produced, as an ISO-8601 UTC string. Preserved exactly as written, which
  /// is why it is text: an event may arrive from another device with another clock, and
  /// reinterpreting its timestamp on this one would rewrite history.
  final String ts;

  /// The event type, such as `chord.insert`.
  final String type;

  /// The event payload and its anchor, as JSON.
  ///
  /// Opaque to this package. The payload's shape belongs to the op-log's owner, and parsing it
  /// here would mean this package had to be changed by every change to an event.
  final String json;
  const DocumentEvent({
    required this.docId,
    required this.seq,
    required this.deviceId,
    required this.ts,
    required this.type,
    required this.json,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['doc_id'] = Variable<String>(docId);
    map['seq'] = Variable<int>(seq);
    map['device_id'] = Variable<String>(deviceId);
    map['ts'] = Variable<String>(ts);
    map['type'] = Variable<String>(type);
    map['json'] = Variable<String>(json);
    return map;
  }

  DocumentEventsCompanion toCompanion(bool nullToAbsent) {
    return DocumentEventsCompanion(
      docId: Value(docId),
      seq: Value(seq),
      deviceId: Value(deviceId),
      ts: Value(ts),
      type: Value(type),
      json: Value(json),
    );
  }

  factory DocumentEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocumentEvent(
      docId: serializer.fromJson<String>(json['docId']),
      seq: serializer.fromJson<int>(json['seq']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      ts: serializer.fromJson<String>(json['ts']),
      type: serializer.fromJson<String>(json['type']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'docId': serializer.toJson<String>(docId),
      'seq': serializer.toJson<int>(seq),
      'deviceId': serializer.toJson<String>(deviceId),
      'ts': serializer.toJson<String>(ts),
      'type': serializer.toJson<String>(type),
      'json': serializer.toJson<String>(json),
    };
  }

  DocumentEvent copyWith({
    String? docId,
    int? seq,
    String? deviceId,
    String? ts,
    String? type,
    String? json,
  }) => DocumentEvent(
    docId: docId ?? this.docId,
    seq: seq ?? this.seq,
    deviceId: deviceId ?? this.deviceId,
    ts: ts ?? this.ts,
    type: type ?? this.type,
    json: json ?? this.json,
  );
  DocumentEvent copyWithCompanion(DocumentEventsCompanion data) {
    return DocumentEvent(
      docId: data.docId.present ? data.docId.value : this.docId,
      seq: data.seq.present ? data.seq.value : this.seq,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      ts: data.ts.present ? data.ts.value : this.ts,
      type: data.type.present ? data.type.value : this.type,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocumentEvent(')
          ..write('docId: $docId, ')
          ..write('seq: $seq, ')
          ..write('deviceId: $deviceId, ')
          ..write('ts: $ts, ')
          ..write('type: $type, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(docId, seq, deviceId, ts, type, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocumentEvent &&
          other.docId == this.docId &&
          other.seq == this.seq &&
          other.deviceId == this.deviceId &&
          other.ts == this.ts &&
          other.type == this.type &&
          other.json == this.json);
}

class DocumentEventsCompanion extends UpdateCompanion<DocumentEvent> {
  final Value<String> docId;
  final Value<int> seq;
  final Value<String> deviceId;
  final Value<String> ts;
  final Value<String> type;
  final Value<String> json;
  final Value<int> rowid;
  const DocumentEventsCompanion({
    this.docId = const Value.absent(),
    this.seq = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.ts = const Value.absent(),
    this.type = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocumentEventsCompanion.insert({
    required String docId,
    required int seq,
    this.deviceId = const Value.absent(),
    required String ts,
    required String type,
    required String json,
    this.rowid = const Value.absent(),
  }) : docId = Value(docId),
       seq = Value(seq),
       ts = Value(ts),
       type = Value(type),
       json = Value(json);
  static Insertable<DocumentEvent> custom({
    Expression<String>? docId,
    Expression<int>? seq,
    Expression<String>? deviceId,
    Expression<String>? ts,
    Expression<String>? type,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (docId != null) 'doc_id': docId,
      if (seq != null) 'seq': seq,
      if (deviceId != null) 'device_id': deviceId,
      if (ts != null) 'ts': ts,
      if (type != null) 'type': type,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocumentEventsCompanion copyWith({
    Value<String>? docId,
    Value<int>? seq,
    Value<String>? deviceId,
    Value<String>? ts,
    Value<String>? type,
    Value<String>? json,
    Value<int>? rowid,
  }) {
    return DocumentEventsCompanion(
      docId: docId ?? this.docId,
      seq: seq ?? this.seq,
      deviceId: deviceId ?? this.deviceId,
      ts: ts ?? this.ts,
      type: type ?? this.type,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (ts.present) {
      map['ts'] = Variable<String>(ts.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocumentEventsCompanion(')
          ..write('docId: $docId, ')
          ..write('seq: $seq, ')
          ..write('deviceId: $deviceId, ')
          ..write('ts: $ts, ')
          ..write('type: $type, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InkBlobsTable extends InkBlobs with TableInfo<$InkBlobsTable, InkBlob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InkBlobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _anchorJsonMeta = const VerificationMeta(
    'anchorJson',
  );
  @override
  late final GeneratedColumn<String> anchorJson = GeneratedColumn<String>(
    'anchor_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, docId, anchorJson, format, path];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ink_blobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<InkBlob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('anchor_json')) {
      context.handle(
        _anchorJsonMeta,
        anchorJson.isAcceptableOrUnknown(data['anchor_json']!, _anchorJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_anchorJsonMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  InkBlob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InkBlob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      anchorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anchor_json'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
    );
  }

  @override
  $InkBlobsTable createAlias(String alias) {
    return $InkBlobsTable(attachedDatabase, alias);
  }
}

class InkBlob extends DataClass implements Insertable<InkBlob> {
  /// Stroke identity.
  final String id;

  /// The document the stroke belongs to.
  final String docId;

  /// The anchor the stroke was captured against, as JSON.
  ///
  /// Coordinates inside the stroke file are anchor-local, which is what lets a stroke survive
  /// transposition and reflow: when the anchor moves, the stroke moves with it and its own
  /// geometry is unchanged.
  final String anchorJson;

  /// The native encoding of the stroke file, such as `pencilkit` or `inkview`.
  final String format;

  /// Where the stroke file lives, relative to the document's blob directory.
  final String path;
  const InkBlob({
    required this.id,
    required this.docId,
    required this.anchorJson,
    required this.format,
    required this.path,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['doc_id'] = Variable<String>(docId);
    map['anchor_json'] = Variable<String>(anchorJson);
    map['format'] = Variable<String>(format);
    map['path'] = Variable<String>(path);
    return map;
  }

  InkBlobsCompanion toCompanion(bool nullToAbsent) {
    return InkBlobsCompanion(
      id: Value(id),
      docId: Value(docId),
      anchorJson: Value(anchorJson),
      format: Value(format),
      path: Value(path),
    );
  }

  factory InkBlob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InkBlob(
      id: serializer.fromJson<String>(json['id']),
      docId: serializer.fromJson<String>(json['docId']),
      anchorJson: serializer.fromJson<String>(json['anchorJson']),
      format: serializer.fromJson<String>(json['format']),
      path: serializer.fromJson<String>(json['path']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'docId': serializer.toJson<String>(docId),
      'anchorJson': serializer.toJson<String>(anchorJson),
      'format': serializer.toJson<String>(format),
      'path': serializer.toJson<String>(path),
    };
  }

  InkBlob copyWith({
    String? id,
    String? docId,
    String? anchorJson,
    String? format,
    String? path,
  }) => InkBlob(
    id: id ?? this.id,
    docId: docId ?? this.docId,
    anchorJson: anchorJson ?? this.anchorJson,
    format: format ?? this.format,
    path: path ?? this.path,
  );
  InkBlob copyWithCompanion(InkBlobsCompanion data) {
    return InkBlob(
      id: data.id.present ? data.id.value : this.id,
      docId: data.docId.present ? data.docId.value : this.docId,
      anchorJson: data.anchorJson.present
          ? data.anchorJson.value
          : this.anchorJson,
      format: data.format.present ? data.format.value : this.format,
      path: data.path.present ? data.path.value : this.path,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InkBlob(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('anchorJson: $anchorJson, ')
          ..write('format: $format, ')
          ..write('path: $path')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, docId, anchorJson, format, path);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InkBlob &&
          other.id == this.id &&
          other.docId == this.docId &&
          other.anchorJson == this.anchorJson &&
          other.format == this.format &&
          other.path == this.path);
}

class InkBlobsCompanion extends UpdateCompanion<InkBlob> {
  final Value<String> id;
  final Value<String> docId;
  final Value<String> anchorJson;
  final Value<String> format;
  final Value<String> path;
  final Value<int> rowid;
  const InkBlobsCompanion({
    this.id = const Value.absent(),
    this.docId = const Value.absent(),
    this.anchorJson = const Value.absent(),
    this.format = const Value.absent(),
    this.path = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InkBlobsCompanion.insert({
    required String id,
    required String docId,
    required String anchorJson,
    required String format,
    required String path,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       docId = Value(docId),
       anchorJson = Value(anchorJson),
       format = Value(format),
       path = Value(path);
  static Insertable<InkBlob> custom({
    Expression<String>? id,
    Expression<String>? docId,
    Expression<String>? anchorJson,
    Expression<String>? format,
    Expression<String>? path,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (docId != null) 'doc_id': docId,
      if (anchorJson != null) 'anchor_json': anchorJson,
      if (format != null) 'format': format,
      if (path != null) 'path': path,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InkBlobsCompanion copyWith({
    Value<String>? id,
    Value<String>? docId,
    Value<String>? anchorJson,
    Value<String>? format,
    Value<String>? path,
    Value<int>? rowid,
  }) {
    return InkBlobsCompanion(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      anchorJson: anchorJson ?? this.anchorJson,
      format: format ?? this.format,
      path: path ?? this.path,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (anchorJson.present) {
      map['anchor_json'] = Variable<String>(anchorJson.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InkBlobsCompanion(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('anchorJson: $anchorJson, ')
          ..write('format: $format, ')
          ..write('path: $path, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SetlistsTable extends Setlists with TableInfo<$SetlistsTable, Setlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SetlistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [id, title];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setlist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Setlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setlist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
    );
  }

  @override
  $SetlistsTable createAlias(String alias) {
    return $SetlistsTable(attachedDatabase, alias);
  }
}

class Setlist extends DataClass implements Insertable<Setlist> {
  /// Setlist identity.
  final String id;

  /// The setlist's name.
  final String title;
  const Setlist({required this.id, required this.title});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    return map;
  }

  SetlistsCompanion toCompanion(bool nullToAbsent) {
    return SetlistsCompanion(id: Value(id), title: Value(title));
  }

  factory Setlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setlist(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
    };
  }

  Setlist copyWith({String? id, String? title}) =>
      Setlist(id: id ?? this.id, title: title ?? this.title);
  Setlist copyWithCompanion(SetlistsCompanion data) {
    return Setlist(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setlist(')
          ..write('id: $id, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setlist && other.id == this.id && other.title == this.title);
}

class SetlistsCompanion extends UpdateCompanion<Setlist> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> rowid;
  const SetlistsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SetlistsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<Setlist> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SetlistsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<int>? rowid,
  }) {
    return SetlistsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SetlistsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SetlistItemsTable extends SetlistItems
    with TableInfo<$SetlistItemsTable, SetlistItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SetlistItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _setlistIdMeta = const VerificationMeta(
    'setlistId',
  );
  @override
  late final GeneratedColumn<String> setlistId = GeneratedColumn<String>(
    'setlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _posMeta = const VerificationMeta('pos');
  @override
  late final GeneratedColumn<int> pos = GeneratedColumn<int>(
    'pos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
    'doc_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transposeSemMeta = const VerificationMeta(
    'transposeSem',
  );
  @override
  late final GeneratedColumn<int> transposeSem = GeneratedColumn<int>(
    'transpose_sem',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    setlistId,
    pos,
    docId,
    transposeSem,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setlist_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<SetlistItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('setlist_id')) {
      context.handle(
        _setlistIdMeta,
        setlistId.isAcceptableOrUnknown(data['setlist_id']!, _setlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_setlistIdMeta);
    }
    if (data.containsKey('pos')) {
      context.handle(
        _posMeta,
        pos.isAcceptableOrUnknown(data['pos']!, _posMeta),
      );
    } else if (isInserting) {
      context.missing(_posMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
        _docIdMeta,
        docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta),
      );
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('transpose_sem')) {
      context.handle(
        _transposeSemMeta,
        transposeSem.isAcceptableOrUnknown(
          data['transpose_sem']!,
          _transposeSemMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {setlistId, pos};
  @override
  SetlistItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SetlistItem(
      setlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}setlist_id'],
      )!,
      pos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pos'],
      )!,
      docId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_id'],
      )!,
      transposeSem: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transpose_sem'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
    );
  }

  @override
  $SetlistItemsTable createAlias(String alias) {
    return $SetlistItemsTable(attachedDatabase, alias);
  }
}

class SetlistItem extends DataClass implements Insertable<SetlistItem> {
  /// The setlist this entry belongs to.
  final String setlistId;

  /// Position in the setlist. Ordering is explicit rather than by insertion, so that a reorder is
  /// a rewrite of positions and not a dependency on rowid behaviour.
  final int pos;

  /// The document this entry plays.
  final String docId;

  /// Semitones to transpose this entry by, which may differ from the song's own key.
  final int transposeSem;

  /// Notes the performer attached to this entry.
  final String notes;
  const SetlistItem({
    required this.setlistId,
    required this.pos,
    required this.docId,
    required this.transposeSem,
    required this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['setlist_id'] = Variable<String>(setlistId);
    map['pos'] = Variable<int>(pos);
    map['doc_id'] = Variable<String>(docId);
    map['transpose_sem'] = Variable<int>(transposeSem);
    map['notes'] = Variable<String>(notes);
    return map;
  }

  SetlistItemsCompanion toCompanion(bool nullToAbsent) {
    return SetlistItemsCompanion(
      setlistId: Value(setlistId),
      pos: Value(pos),
      docId: Value(docId),
      transposeSem: Value(transposeSem),
      notes: Value(notes),
    );
  }

  factory SetlistItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SetlistItem(
      setlistId: serializer.fromJson<String>(json['setlistId']),
      pos: serializer.fromJson<int>(json['pos']),
      docId: serializer.fromJson<String>(json['docId']),
      transposeSem: serializer.fromJson<int>(json['transposeSem']),
      notes: serializer.fromJson<String>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'setlistId': serializer.toJson<String>(setlistId),
      'pos': serializer.toJson<int>(pos),
      'docId': serializer.toJson<String>(docId),
      'transposeSem': serializer.toJson<int>(transposeSem),
      'notes': serializer.toJson<String>(notes),
    };
  }

  SetlistItem copyWith({
    String? setlistId,
    int? pos,
    String? docId,
    int? transposeSem,
    String? notes,
  }) => SetlistItem(
    setlistId: setlistId ?? this.setlistId,
    pos: pos ?? this.pos,
    docId: docId ?? this.docId,
    transposeSem: transposeSem ?? this.transposeSem,
    notes: notes ?? this.notes,
  );
  SetlistItem copyWithCompanion(SetlistItemsCompanion data) {
    return SetlistItem(
      setlistId: data.setlistId.present ? data.setlistId.value : this.setlistId,
      pos: data.pos.present ? data.pos.value : this.pos,
      docId: data.docId.present ? data.docId.value : this.docId,
      transposeSem: data.transposeSem.present
          ? data.transposeSem.value
          : this.transposeSem,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SetlistItem(')
          ..write('setlistId: $setlistId, ')
          ..write('pos: $pos, ')
          ..write('docId: $docId, ')
          ..write('transposeSem: $transposeSem, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(setlistId, pos, docId, transposeSem, notes);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SetlistItem &&
          other.setlistId == this.setlistId &&
          other.pos == this.pos &&
          other.docId == this.docId &&
          other.transposeSem == this.transposeSem &&
          other.notes == this.notes);
}

class SetlistItemsCompanion extends UpdateCompanion<SetlistItem> {
  final Value<String> setlistId;
  final Value<int> pos;
  final Value<String> docId;
  final Value<int> transposeSem;
  final Value<String> notes;
  final Value<int> rowid;
  const SetlistItemsCompanion({
    this.setlistId = const Value.absent(),
    this.pos = const Value.absent(),
    this.docId = const Value.absent(),
    this.transposeSem = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SetlistItemsCompanion.insert({
    required String setlistId,
    required int pos,
    required String docId,
    this.transposeSem = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : setlistId = Value(setlistId),
       pos = Value(pos),
       docId = Value(docId);
  static Insertable<SetlistItem> custom({
    Expression<String>? setlistId,
    Expression<int>? pos,
    Expression<String>? docId,
    Expression<int>? transposeSem,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (setlistId != null) 'setlist_id': setlistId,
      if (pos != null) 'pos': pos,
      if (docId != null) 'doc_id': docId,
      if (transposeSem != null) 'transpose_sem': transposeSem,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SetlistItemsCompanion copyWith({
    Value<String>? setlistId,
    Value<int>? pos,
    Value<String>? docId,
    Value<int>? transposeSem,
    Value<String>? notes,
    Value<int>? rowid,
  }) {
    return SetlistItemsCompanion(
      setlistId: setlistId ?? this.setlistId,
      pos: pos ?? this.pos,
      docId: docId ?? this.docId,
      transposeSem: transposeSem ?? this.transposeSem,
      notes: notes ?? this.notes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (setlistId.present) {
      map['setlist_id'] = Variable<String>(setlistId.value);
    }
    if (pos.present) {
      map['pos'] = Variable<int>(pos.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (transposeSem.present) {
      map['transpose_sem'] = Variable<int>(transposeSem.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SetlistItemsCompanion(')
          ..write('setlistId: $setlistId, ')
          ..write('pos: $pos, ')
          ..write('docId: $docId, ')
          ..write('transposeSem: $transposeSem, ')
          ..write('notes: $notes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MetaTable extends Meta with TableInfo<$MetaTable, MetaData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kMeta = const VerificationMeta('k');
  @override
  late final GeneratedColumn<String> k = GeneratedColumn<String>(
    'k',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _vMeta = const VerificationMeta('v');
  @override
  late final GeneratedColumn<String> v = GeneratedColumn<String>(
    'v',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [k, v];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<MetaData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('k')) {
      context.handle(_kMeta, k.isAcceptableOrUnknown(data['k']!, _kMeta));
    } else if (isInserting) {
      context.missing(_kMeta);
    }
    if (data.containsKey('v')) {
      context.handle(_vMeta, v.isAcceptableOrUnknown(data['v']!, _vMeta));
    } else if (isInserting) {
      context.missing(_vMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {k};
  @override
  MetaData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MetaData(
      k: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}k'],
      )!,
      v: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}v'],
      )!,
    );
  }

  @override
  $MetaTable createAlias(String alias) {
    return $MetaTable(attachedDatabase, alias);
  }
}

class MetaData extends DataClass implements Insertable<MetaData> {
  /// The key.
  final String k;

  /// The value.
  final String v;
  const MetaData({required this.k, required this.v});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['k'] = Variable<String>(k);
    map['v'] = Variable<String>(v);
    return map;
  }

  MetaCompanion toCompanion(bool nullToAbsent) {
    return MetaCompanion(k: Value(k), v: Value(v));
  }

  factory MetaData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MetaData(
      k: serializer.fromJson<String>(json['k']),
      v: serializer.fromJson<String>(json['v']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'k': serializer.toJson<String>(k),
      'v': serializer.toJson<String>(v),
    };
  }

  MetaData copyWith({String? k, String? v}) =>
      MetaData(k: k ?? this.k, v: v ?? this.v);
  MetaData copyWithCompanion(MetaCompanion data) {
    return MetaData(
      k: data.k.present ? data.k.value : this.k,
      v: data.v.present ? data.v.value : this.v,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MetaData(')
          ..write('k: $k, ')
          ..write('v: $v')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(k, v);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaData && other.k == this.k && other.v == this.v);
}

class MetaCompanion extends UpdateCompanion<MetaData> {
  final Value<String> k;
  final Value<String> v;
  final Value<int> rowid;
  const MetaCompanion({
    this.k = const Value.absent(),
    this.v = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MetaCompanion.insert({
    required String k,
    required String v,
    this.rowid = const Value.absent(),
  }) : k = Value(k),
       v = Value(v);
  static Insertable<MetaData> custom({
    Expression<String>? k,
    Expression<String>? v,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (k != null) 'k': k,
      if (v != null) 'v': v,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MetaCompanion copyWith({
    Value<String>? k,
    Value<String>? v,
    Value<int>? rowid,
  }) {
    return MetaCompanion(
      k: k ?? this.k,
      v: v ?? this.v,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (k.present) {
      map['k'] = Variable<String>(k.value);
    }
    if (v.present) {
      map['v'] = Variable<String>(v.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MetaCompanion(')
          ..write('k: $k, ')
          ..write('v: $v, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ChartDatabase extends GeneratedDatabase {
  _$ChartDatabase(QueryExecutor e) : super(e);
  $ChartDatabaseManager get managers => $ChartDatabaseManager(this);
  late final $DocumentsTable documents = $DocumentsTable(this);
  late final $DocumentEventsTable documentEvents = $DocumentEventsTable(this);
  late final $InkBlobsTable inkBlobs = $InkBlobsTable(this);
  late final $SetlistsTable setlists = $SetlistsTable(this);
  late final $SetlistItemsTable setlistItems = $SetlistItemsTable(this);
  late final $MetaTable meta = $MetaTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    documents,
    documentEvents,
    inkBlobs,
    setlists,
    setlistItems,
    meta,
  ];
}

typedef $$DocumentsTableCreateCompanionBuilder = DocumentsCompanion Function({
  required String id,
  Value<String> title,
  Value<String> songKey,
  Value<int> bpm,
  required String updatedAt,
  Value<String?> snapshotJson,
  Value<int> snapshotSeq,
  Value<int> rowid,
});
typedef $$DocumentsTableUpdateCompanionBuilder = DocumentsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> songKey,
  Value<int> bpm,
  Value<String> updatedAt,
  Value<String?> snapshotJson,
  Value<int> snapshotSeq,
  Value<int> rowid,
});

class $$DocumentsTableFilterComposer
    extends Composer<_$ChartDatabase, $DocumentsTable> {
  $$DocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songKey => $composableBuilder(
    column: $table.songKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snapshotSeq => $composableBuilder(
    column: $table.snapshotSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DocumentsTableOrderingComposer
    extends Composer<_$ChartDatabase, $DocumentsTable> {
  $$DocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songKey => $composableBuilder(
    column: $table.songKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bpm => $composableBuilder(
    column: $table.bpm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snapshotSeq => $composableBuilder(
    column: $table.snapshotSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentsTableAnnotationComposer
    extends Composer<_$ChartDatabase, $DocumentsTable> {
  $$DocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get songKey =>
      $composableBuilder(column: $table.songKey, builder: (column) => column);

  GeneratedColumn<int> get bpm =>
      $composableBuilder(column: $table.bpm, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get snapshotJson => $composableBuilder(
    column: $table.snapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snapshotSeq => $composableBuilder(
    column: $table.snapshotSeq,
    builder: (column) => column,
  );
}

class $$DocumentsTableTableManager
    extends
        RootTableManager<
          _$ChartDatabase,
          $DocumentsTable,
          Document,
          $$DocumentsTableFilterComposer,
          $$DocumentsTableOrderingComposer,
          $$DocumentsTableAnnotationComposer,
          $$DocumentsTableCreateCompanionBuilder,
          $$DocumentsTableUpdateCompanionBuilder,
          (
            Document,
            BaseReferences<_$ChartDatabase, $DocumentsTable, Document>,
          ),
          Document,
          PrefetchHooks Function()
        > {
  $$DocumentsTableTableManager(_$ChartDatabase db, $DocumentsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> songKey = const Value.absent(),
                Value<int> bpm = const Value.absent(),
                Value<String> updatedAt = const Value.absent(),
                Value<String?> snapshotJson = const Value.absent(),
                Value<int> snapshotSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion(
                id: id,
                title: title,
                songKey: songKey,
                bpm: bpm,
                updatedAt: updatedAt,
                snapshotJson: snapshotJson,
                snapshotSeq: snapshotSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<String> songKey = const Value.absent(),
                Value<int> bpm = const Value.absent(),
                required String updatedAt,
                Value<String?> snapshotJson = const Value.absent(),
                Value<int> snapshotSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentsCompanion.insert(
                id: id,
                title: title,
                songKey: songKey,
                bpm: bpm,
                updatedAt: updatedAt,
                snapshotJson: snapshotJson,
                snapshotSeq: snapshotSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentsTable, Document>(table),
                  BaseReferences<_$ChartDatabase, $DocumentsTable, Document>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChartDatabase,
      $DocumentsTable,
      Document,
      $$DocumentsTableFilterComposer,
      $$DocumentsTableOrderingComposer,
      $$DocumentsTableAnnotationComposer,
      $$DocumentsTableCreateCompanionBuilder,
      $$DocumentsTableUpdateCompanionBuilder,
      (Document, BaseReferences<_$ChartDatabase, $DocumentsTable, Document>),
      Document,
      PrefetchHooks Function()
    >;
typedef $$DocumentEventsTableCreateCompanionBuilder =
    DocumentEventsCompanion Function({
      required String docId,
      required int seq,
      Value<String> deviceId,
      required String ts,
      required String type,
      required String json,
      Value<int> rowid,
    });
typedef $$DocumentEventsTableUpdateCompanionBuilder =
    DocumentEventsCompanion Function({
      Value<String> docId,
      Value<int> seq,
      Value<String> deviceId,
      Value<String> ts,
      Value<String> type,
      Value<String> json,
      Value<int> rowid,
    });

class $$DocumentEventsTableFilterComposer
    extends Composer<_$ChartDatabase, $DocumentEventsTable> {
  $$DocumentEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DocumentEventsTableOrderingComposer
    extends Composer<_$ChartDatabase, $DocumentEventsTable> {
  $$DocumentEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DocumentEventsTableAnnotationComposer
    extends Composer<_$ChartDatabase, $DocumentEventsTable> {
  $$DocumentEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$DocumentEventsTableTableManager
    extends
        RootTableManager<
          _$ChartDatabase,
          $DocumentEventsTable,
          DocumentEvent,
          $$DocumentEventsTableFilterComposer,
          $$DocumentEventsTableOrderingComposer,
          $$DocumentEventsTableAnnotationComposer,
          $$DocumentEventsTableCreateCompanionBuilder,
          $$DocumentEventsTableUpdateCompanionBuilder,
          (
            DocumentEvent,
            BaseReferences<
              _$ChartDatabase,
              $DocumentEventsTable,
              DocumentEvent
            >,
          ),
          DocumentEvent,
          PrefetchHooks Function()
        > {
  $$DocumentEventsTableTableManager(
    _$ChartDatabase db,
    $DocumentEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocumentEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocumentEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocumentEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> docId = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> ts = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DocumentEventsCompanion(
                docId: docId,
                seq: seq,
                deviceId: deviceId,
                ts: ts,
                type: type,
                json: json,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String docId,
                required int seq,
                Value<String> deviceId = const Value.absent(),
                required String ts,
                required String type,
                required String json,
                Value<int> rowid = const Value.absent(),
              }) => DocumentEventsCompanion.insert(
                docId: docId,
                seq: seq,
                deviceId: deviceId,
                ts: ts,
                type: type,
                json: json,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DocumentEventsTable, DocumentEvent>(table),
                  BaseReferences<
                    _$ChartDatabase,
                    $DocumentEventsTable,
                    DocumentEvent
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DocumentEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChartDatabase,
      $DocumentEventsTable,
      DocumentEvent,
      $$DocumentEventsTableFilterComposer,
      $$DocumentEventsTableOrderingComposer,
      $$DocumentEventsTableAnnotationComposer,
      $$DocumentEventsTableCreateCompanionBuilder,
      $$DocumentEventsTableUpdateCompanionBuilder,
      (
        DocumentEvent,
        BaseReferences<_$ChartDatabase, $DocumentEventsTable, DocumentEvent>,
      ),
      DocumentEvent,
      PrefetchHooks Function()
    >;
typedef $$InkBlobsTableCreateCompanionBuilder = InkBlobsCompanion Function({
  required String id,
  required String docId,
  required String anchorJson,
  required String format,
  required String path,
  Value<int> rowid,
});
typedef $$InkBlobsTableUpdateCompanionBuilder = InkBlobsCompanion Function({
  Value<String> id,
  Value<String> docId,
  Value<String> anchorJson,
  Value<String> format,
  Value<String> path,
  Value<int> rowid,
});

class $$InkBlobsTableFilterComposer
    extends Composer<_$ChartDatabase, $InkBlobsTable> {
  $$InkBlobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get anchorJson => $composableBuilder(
    column: $table.anchorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InkBlobsTableOrderingComposer
    extends Composer<_$ChartDatabase, $InkBlobsTable> {
  $$InkBlobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchorJson => $composableBuilder(
    column: $table.anchorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InkBlobsTableAnnotationComposer
    extends Composer<_$ChartDatabase, $InkBlobsTable> {
  $$InkBlobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<String> get anchorJson => $composableBuilder(
    column: $table.anchorJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);
}

class $$InkBlobsTableTableManager
    extends
        RootTableManager<
          _$ChartDatabase,
          $InkBlobsTable,
          InkBlob,
          $$InkBlobsTableFilterComposer,
          $$InkBlobsTableOrderingComposer,
          $$InkBlobsTableAnnotationComposer,
          $$InkBlobsTableCreateCompanionBuilder,
          $$InkBlobsTableUpdateCompanionBuilder,
          (InkBlob, BaseReferences<_$ChartDatabase, $InkBlobsTable, InkBlob>),
          InkBlob,
          PrefetchHooks Function()
        > {
  $$InkBlobsTableTableManager(_$ChartDatabase db, $InkBlobsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InkBlobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InkBlobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InkBlobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<String> anchorJson = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InkBlobsCompanion(
                id: id,
                docId: docId,
                anchorJson: anchorJson,
                format: format,
                path: path,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String docId,
                required String anchorJson,
                required String format,
                required String path,
                Value<int> rowid = const Value.absent(),
              }) => InkBlobsCompanion.insert(
                id: id,
                docId: docId,
                anchorJson: anchorJson,
                format: format,
                path: path,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InkBlobsTable, InkBlob>(table),
                  BaseReferences<_$ChartDatabase, $InkBlobsTable, InkBlob>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InkBlobsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChartDatabase,
      $InkBlobsTable,
      InkBlob,
      $$InkBlobsTableFilterComposer,
      $$InkBlobsTableOrderingComposer,
      $$InkBlobsTableAnnotationComposer,
      $$InkBlobsTableCreateCompanionBuilder,
      $$InkBlobsTableUpdateCompanionBuilder,
      (InkBlob, BaseReferences<_$ChartDatabase, $InkBlobsTable, InkBlob>),
      InkBlob,
      PrefetchHooks Function()
    >;
typedef $$SetlistsTableCreateCompanionBuilder = SetlistsCompanion Function({
  required String id,
  Value<String> title,
  Value<int> rowid,
});
typedef $$SetlistsTableUpdateCompanionBuilder = SetlistsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<int> rowid,
});

class $$SetlistsTableFilterComposer
    extends Composer<_$ChartDatabase, $SetlistsTable> {
  $$SetlistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SetlistsTableOrderingComposer
    extends Composer<_$ChartDatabase, $SetlistsTable> {
  $$SetlistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SetlistsTableAnnotationComposer
    extends Composer<_$ChartDatabase, $SetlistsTable> {
  $$SetlistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);
}

class $$SetlistsTableTableManager
    extends
        RootTableManager<
          _$ChartDatabase,
          $SetlistsTable,
          Setlist,
          $$SetlistsTableFilterComposer,
          $$SetlistsTableOrderingComposer,
          $$SetlistsTableAnnotationComposer,
          $$SetlistsTableCreateCompanionBuilder,
          $$SetlistsTableUpdateCompanionBuilder,
          (Setlist, BaseReferences<_$ChartDatabase, $SetlistsTable, Setlist>),
          Setlist,
          PrefetchHooks Function()
        > {
  $$SetlistsTableTableManager(_$ChartDatabase db, $SetlistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SetlistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SetlistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SetlistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SetlistsCompanion(id: id, title: title, rowid: rowid),
          createCompanionCallback: ({
            required String id,
            Value<String> title = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SetlistsCompanion.insert(id: id, title: title, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SetlistsTable, Setlist>(table),
                  BaseReferences<_$ChartDatabase, $SetlistsTable, Setlist>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SetlistsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChartDatabase,
      $SetlistsTable,
      Setlist,
      $$SetlistsTableFilterComposer,
      $$SetlistsTableOrderingComposer,
      $$SetlistsTableAnnotationComposer,
      $$SetlistsTableCreateCompanionBuilder,
      $$SetlistsTableUpdateCompanionBuilder,
      (Setlist, BaseReferences<_$ChartDatabase, $SetlistsTable, Setlist>),
      Setlist,
      PrefetchHooks Function()
    >;
typedef $$SetlistItemsTableCreateCompanionBuilder =
    SetlistItemsCompanion Function({
      required String setlistId,
      required int pos,
      required String docId,
      Value<int> transposeSem,
      Value<String> notes,
      Value<int> rowid,
    });
typedef $$SetlistItemsTableUpdateCompanionBuilder =
    SetlistItemsCompanion Function({
      Value<String> setlistId,
      Value<int> pos,
      Value<String> docId,
      Value<int> transposeSem,
      Value<String> notes,
      Value<int> rowid,
    });

class $$SetlistItemsTableFilterComposer
    extends Composer<_$ChartDatabase, $SetlistItemsTable> {
  $$SetlistItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get setlistId => $composableBuilder(
    column: $table.setlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pos => $composableBuilder(
    column: $table.pos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transposeSem => $composableBuilder(
    column: $table.transposeSem,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SetlistItemsTableOrderingComposer
    extends Composer<_$ChartDatabase, $SetlistItemsTable> {
  $$SetlistItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get setlistId => $composableBuilder(
    column: $table.setlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pos => $composableBuilder(
    column: $table.pos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get docId => $composableBuilder(
    column: $table.docId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transposeSem => $composableBuilder(
    column: $table.transposeSem,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SetlistItemsTableAnnotationComposer
    extends Composer<_$ChartDatabase, $SetlistItemsTable> {
  $$SetlistItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get setlistId =>
      $composableBuilder(column: $table.setlistId, builder: (column) => column);

  GeneratedColumn<int> get pos =>
      $composableBuilder(column: $table.pos, builder: (column) => column);

  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<int> get transposeSem => $composableBuilder(
    column: $table.transposeSem,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);
}

class $$SetlistItemsTableTableManager
    extends
        RootTableManager<
          _$ChartDatabase,
          $SetlistItemsTable,
          SetlistItem,
          $$SetlistItemsTableFilterComposer,
          $$SetlistItemsTableOrderingComposer,
          $$SetlistItemsTableAnnotationComposer,
          $$SetlistItemsTableCreateCompanionBuilder,
          $$SetlistItemsTableUpdateCompanionBuilder,
          (
            SetlistItem,
            BaseReferences<_$ChartDatabase, $SetlistItemsTable, SetlistItem>,
          ),
          SetlistItem,
          PrefetchHooks Function()
        > {
  $$SetlistItemsTableTableManager(_$ChartDatabase db, $SetlistItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SetlistItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SetlistItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SetlistItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> setlistId = const Value.absent(),
                Value<int> pos = const Value.absent(),
                Value<String> docId = const Value.absent(),
                Value<int> transposeSem = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SetlistItemsCompanion(
                setlistId: setlistId,
                pos: pos,
                docId: docId,
                transposeSem: transposeSem,
                notes: notes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String setlistId,
                required int pos,
                required String docId,
                Value<int> transposeSem = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SetlistItemsCompanion.insert(
                setlistId: setlistId,
                pos: pos,
                docId: docId,
                transposeSem: transposeSem,
                notes: notes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SetlistItemsTable, SetlistItem>(table),
                  BaseReferences<
                    _$ChartDatabase,
                    $SetlistItemsTable,
                    SetlistItem
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SetlistItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$ChartDatabase,
      $SetlistItemsTable,
      SetlistItem,
      $$SetlistItemsTableFilterComposer,
      $$SetlistItemsTableOrderingComposer,
      $$SetlistItemsTableAnnotationComposer,
      $$SetlistItemsTableCreateCompanionBuilder,
      $$SetlistItemsTableUpdateCompanionBuilder,
      (
        SetlistItem,
        BaseReferences<_$ChartDatabase, $SetlistItemsTable, SetlistItem>,
      ),
      SetlistItem,
      PrefetchHooks Function()
    >;
typedef $$MetaTableCreateCompanionBuilder = MetaCompanion Function({
  required String k,
  required String v,
  Value<int> rowid,
});
typedef $$MetaTableUpdateCompanionBuilder = MetaCompanion Function({
  Value<String> k,
  Value<String> v,
  Value<int> rowid,
});

class $$MetaTableFilterComposer extends Composer<_$ChartDatabase, $MetaTable> {
  $$MetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MetaTableOrderingComposer
    extends Composer<_$ChartDatabase, $MetaTable> {
  $$MetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get k => $composableBuilder(
    column: $table.k,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get v => $composableBuilder(
    column: $table.v,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MetaTableAnnotationComposer
    extends Composer<_$ChartDatabase, $MetaTable> {
  $$MetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get k =>
      $composableBuilder(column: $table.k, builder: (column) => column);

  GeneratedColumn<String> get v =>
      $composableBuilder(column: $table.v, builder: (column) => column);
}

class $$MetaTableTableManager
    extends
        RootTableManager<
          _$ChartDatabase,
          $MetaTable,
          MetaData,
          $$MetaTableFilterComposer,
          $$MetaTableOrderingComposer,
          $$MetaTableAnnotationComposer,
          $$MetaTableCreateCompanionBuilder,
          $$MetaTableUpdateCompanionBuilder,
          (MetaData, BaseReferences<_$ChartDatabase, $MetaTable, MetaData>),
          MetaData,
          PrefetchHooks Function()
        > {
  $$MetaTableTableManager(_$ChartDatabase db, $MetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> k = const Value.absent(),
            Value<String> v = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => MetaCompanion(k: k, v: v, rowid: rowid),
          createCompanionCallback: ({
            required String k,
            required String v,
            Value<int> rowid = const Value.absent(),
          }) => MetaCompanion.insert(k: k, v: v, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MetaTable, MetaData>(table),
                  BaseReferences<_$ChartDatabase, $MetaTable, MetaData>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MetaTableProcessedTableManager =
    ProcessedTableManager<
      _$ChartDatabase,
      $MetaTable,
      MetaData,
      $$MetaTableFilterComposer,
      $$MetaTableOrderingComposer,
      $$MetaTableAnnotationComposer,
      $$MetaTableCreateCompanionBuilder,
      $$MetaTableUpdateCompanionBuilder,
      (MetaData, BaseReferences<_$ChartDatabase, $MetaTable, MetaData>),
      MetaData,
      PrefetchHooks Function()
    >;

class $ChartDatabaseManager {
  final _$ChartDatabase _db;
  $ChartDatabaseManager(this._db);
  $$DocumentsTableTableManager get documents =>
      $$DocumentsTableTableManager(_db, _db.documents);
  $$DocumentEventsTableTableManager get documentEvents =>
      $$DocumentEventsTableTableManager(_db, _db.documentEvents);
  $$InkBlobsTableTableManager get inkBlobs =>
      $$InkBlobsTableTableManager(_db, _db.inkBlobs);
  $$SetlistsTableTableManager get setlists =>
      $$SetlistsTableTableManager(_db, _db.setlists);
  $$SetlistItemsTableTableManager get setlistItems =>
      $$SetlistItemsTableTableManager(_db, _db.setlistItems);
  $$MetaTableTableManager get meta => $$MetaTableTableManager(_db, _db.meta);
}
