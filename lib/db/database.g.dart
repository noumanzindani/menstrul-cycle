// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PeriodEntriesTable extends PeriodEntries
    with TableInfo<$PeriodEntriesTable, PeriodEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeriodEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _startDateMeta = const VerificationMeta(
    'startDate',
  );
  @override
  late final GeneratedColumn<DateTime> startDate = GeneratedColumn<DateTime>(
    'start_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endDateMeta = const VerificationMeta(
    'endDate',
  );
  @override
  late final GeneratedColumn<DateTime> endDate = GeneratedColumn<DateTime>(
    'end_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    startDate,
    endDate,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'period_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeriodEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('start_date')) {
      context.handle(
        _startDateMeta,
        startDate.isAcceptableOrUnknown(data['start_date']!, _startDateMeta),
      );
    } else if (isInserting) {
      context.missing(_startDateMeta);
    }
    if (data.containsKey('end_date')) {
      context.handle(
        _endDateMeta,
        endDate.isAcceptableOrUnknown(data['end_date']!, _endDateMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PeriodEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeriodEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      startDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_date'],
      )!,
      endDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_date'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PeriodEntriesTable createAlias(String alias) {
    return $PeriodEntriesTable(attachedDatabase, alias);
  }
}

class PeriodEntry extends DataClass implements Insertable<PeriodEntry> {
  final int id;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  const PeriodEntry({
    required this.id,
    required this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['start_date'] = Variable<DateTime>(startDate);
    if (!nullToAbsent || endDate != null) {
      map['end_date'] = Variable<DateTime>(endDate);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PeriodEntriesCompanion toCompanion(bool nullToAbsent) {
    return PeriodEntriesCompanion(
      id: Value(id),
      startDate: Value(startDate),
      endDate: endDate == null && nullToAbsent
          ? const Value.absent()
          : Value(endDate),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory PeriodEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeriodEntry(
      id: serializer.fromJson<int>(json['id']),
      startDate: serializer.fromJson<DateTime>(json['startDate']),
      endDate: serializer.fromJson<DateTime?>(json['endDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'startDate': serializer.toJson<DateTime>(startDate),
      'endDate': serializer.toJson<DateTime?>(endDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  PeriodEntry copyWith({
    int? id,
    DateTime? startDate,
    Value<DateTime?> endDate = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => PeriodEntry(
    id: id ?? this.id,
    startDate: startDate ?? this.startDate,
    endDate: endDate.present ? endDate.value : this.endDate,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PeriodEntry copyWithCompanion(PeriodEntriesCompanion data) {
    return PeriodEntry(
      id: data.id.present ? data.id.value : this.id,
      startDate: data.startDate.present ? data.startDate.value : this.startDate,
      endDate: data.endDate.present ? data.endDate.value : this.endDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeriodEntry(')
          ..write('id: $id, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, startDate, endDate, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeriodEntry &&
          other.id == this.id &&
          other.startDate == this.startDate &&
          other.endDate == this.endDate &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class PeriodEntriesCompanion extends UpdateCompanion<PeriodEntry> {
  final Value<int> id;
  final Value<DateTime> startDate;
  final Value<DateTime?> endDate;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const PeriodEntriesCompanion({
    this.id = const Value.absent(),
    this.startDate = const Value.absent(),
    this.endDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PeriodEntriesCompanion.insert({
    this.id = const Value.absent(),
    required DateTime startDate,
    this.endDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : startDate = Value(startDate);
  static Insertable<PeriodEntry> custom({
    Expression<int>? id,
    Expression<DateTime>? startDate,
    Expression<DateTime>? endDate,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PeriodEntriesCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? startDate,
    Value<DateTime?>? endDate,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return PeriodEntriesCompanion(
      id: id ?? this.id,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (startDate.present) {
      map['start_date'] = Variable<DateTime>(startDate.value);
    }
    if (endDate.present) {
      map['end_date'] = Variable<DateTime>(endDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeriodEntriesCompanion(')
          ..write('id: $id, ')
          ..write('startDate: $startDate, ')
          ..write('endDate: $endDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $DailyLogsTable extends DailyLogs
    with TableInfo<$DailyLogsTable, DailyLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<FlowIntensity?, int> flow =
      GeneratedColumn<int>(
        'flow',
        aliasedName,
        true,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
      ).withConverter<FlowIntensity?>($DailyLogsTable.$converterflown);
  static const VerificationMeta _symptomsMeta = const VerificationMeta(
    'symptoms',
  );
  @override
  late final GeneratedColumn<String> symptoms = GeneratedColumn<String>(
    'symptoms',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _moodMeta = const VerificationMeta('mood');
  @override
  late final GeneratedColumn<String> mood = GeneratedColumn<String>(
    'mood',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bbtMeta = const VerificationMeta('bbt');
  @override
  late final GeneratedColumn<double> bbt = GeneratedColumn<double>(
    'bbt',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _opkMeta = const VerificationMeta('opk');
  @override
  late final GeneratedColumn<String> opk = GeneratedColumn<String>(
    'opk',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    flow,
    symptoms,
    mood,
    notes,
    bbt,
    opk,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('symptoms')) {
      context.handle(
        _symptomsMeta,
        symptoms.isAcceptableOrUnknown(data['symptoms']!, _symptomsMeta),
      );
    }
    if (data.containsKey('mood')) {
      context.handle(
        _moodMeta,
        mood.isAcceptableOrUnknown(data['mood']!, _moodMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('bbt')) {
      context.handle(
        _bbtMeta,
        bbt.isAcceptableOrUnknown(data['bbt']!, _bbtMeta),
      );
    }
    if (data.containsKey('opk')) {
      context.handle(
        _opkMeta,
        opk.isAcceptableOrUnknown(data['opk']!, _opkMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {date},
  ];
  @override
  DailyLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      flow: $DailyLogsTable.$converterflown.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}flow'],
        ),
      ),
      symptoms: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symptoms'],
      )!,
      mood: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mood'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      bbt: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}bbt'],
      ),
      opk: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}opk'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DailyLogsTable createAlias(String alias) {
    return $DailyLogsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<FlowIntensity, int, int> $converterflow =
      const EnumIndexConverter<FlowIntensity>(FlowIntensity.values);
  static JsonTypeConverter2<FlowIntensity?, int?, int?> $converterflown =
      JsonTypeConverter2.asNullable($converterflow);
}

class DailyLog extends DataClass implements Insertable<DailyLog> {
  final int id;
  final DateTime date;
  final FlowIntensity? flow;
  final String symptoms;
  final String? mood;
  final String? notes;
  final double? bbt;
  final String? opk;
  final DateTime createdAt;
  final DateTime updatedAt;
  const DailyLog({
    required this.id,
    required this.date,
    this.flow,
    required this.symptoms,
    this.mood,
    this.notes,
    this.bbt,
    this.opk,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<DateTime>(date);
    if (!nullToAbsent || flow != null) {
      map['flow'] = Variable<int>($DailyLogsTable.$converterflown.toSql(flow));
    }
    map['symptoms'] = Variable<String>(symptoms);
    if (!nullToAbsent || mood != null) {
      map['mood'] = Variable<String>(mood);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || bbt != null) {
      map['bbt'] = Variable<double>(bbt);
    }
    if (!nullToAbsent || opk != null) {
      map['opk'] = Variable<String>(opk);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DailyLogsCompanion toCompanion(bool nullToAbsent) {
    return DailyLogsCompanion(
      id: Value(id),
      date: Value(date),
      flow: flow == null && nullToAbsent ? const Value.absent() : Value(flow),
      symptoms: Value(symptoms),
      mood: mood == null && nullToAbsent ? const Value.absent() : Value(mood),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      bbt: bbt == null && nullToAbsent ? const Value.absent() : Value(bbt),
      opk: opk == null && nullToAbsent ? const Value.absent() : Value(opk),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DailyLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyLog(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      flow: $DailyLogsTable.$converterflown.fromJson(
        serializer.fromJson<int?>(json['flow']),
      ),
      symptoms: serializer.fromJson<String>(json['symptoms']),
      mood: serializer.fromJson<String?>(json['mood']),
      notes: serializer.fromJson<String?>(json['notes']),
      bbt: serializer.fromJson<double?>(json['bbt']),
      opk: serializer.fromJson<String?>(json['opk']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'flow': serializer.toJson<int?>(
        $DailyLogsTable.$converterflown.toJson(flow),
      ),
      'symptoms': serializer.toJson<String>(symptoms),
      'mood': serializer.toJson<String?>(mood),
      'notes': serializer.toJson<String?>(notes),
      'bbt': serializer.toJson<double?>(bbt),
      'opk': serializer.toJson<String?>(opk),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DailyLog copyWith({
    int? id,
    DateTime? date,
    Value<FlowIntensity?> flow = const Value.absent(),
    String? symptoms,
    Value<String?> mood = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<double?> bbt = const Value.absent(),
    Value<String?> opk = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => DailyLog(
    id: id ?? this.id,
    date: date ?? this.date,
    flow: flow.present ? flow.value : this.flow,
    symptoms: symptoms ?? this.symptoms,
    mood: mood.present ? mood.value : this.mood,
    notes: notes.present ? notes.value : this.notes,
    bbt: bbt.present ? bbt.value : this.bbt,
    opk: opk.present ? opk.value : this.opk,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DailyLog copyWithCompanion(DailyLogsCompanion data) {
    return DailyLog(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      flow: data.flow.present ? data.flow.value : this.flow,
      symptoms: data.symptoms.present ? data.symptoms.value : this.symptoms,
      mood: data.mood.present ? data.mood.value : this.mood,
      notes: data.notes.present ? data.notes.value : this.notes,
      bbt: data.bbt.present ? data.bbt.value : this.bbt,
      opk: data.opk.present ? data.opk.value : this.opk,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyLog(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('flow: $flow, ')
          ..write('symptoms: $symptoms, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes, ')
          ..write('bbt: $bbt, ')
          ..write('opk: $opk, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    date,
    flow,
    symptoms,
    mood,
    notes,
    bbt,
    opk,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyLog &&
          other.id == this.id &&
          other.date == this.date &&
          other.flow == this.flow &&
          other.symptoms == this.symptoms &&
          other.mood == this.mood &&
          other.notes == this.notes &&
          other.bbt == this.bbt &&
          other.opk == this.opk &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DailyLogsCompanion extends UpdateCompanion<DailyLog> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<FlowIntensity?> flow;
  final Value<String> symptoms;
  final Value<String?> mood;
  final Value<String?> notes;
  final Value<double?> bbt;
  final Value<String?> opk;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const DailyLogsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.flow = const Value.absent(),
    this.symptoms = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.bbt = const Value.absent(),
    this.opk = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  DailyLogsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime date,
    this.flow = const Value.absent(),
    this.symptoms = const Value.absent(),
    this.mood = const Value.absent(),
    this.notes = const Value.absent(),
    this.bbt = const Value.absent(),
    this.opk = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  }) : date = Value(date);
  static Insertable<DailyLog> custom({
    Expression<int>? id,
    Expression<DateTime>? date,
    Expression<int>? flow,
    Expression<String>? symptoms,
    Expression<String>? mood,
    Expression<String>? notes,
    Expression<double>? bbt,
    Expression<String>? opk,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (flow != null) 'flow': flow,
      if (symptoms != null) 'symptoms': symptoms,
      if (mood != null) 'mood': mood,
      if (notes != null) 'notes': notes,
      if (bbt != null) 'bbt': bbt,
      if (opk != null) 'opk': opk,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  DailyLogsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? date,
    Value<FlowIntensity?>? flow,
    Value<String>? symptoms,
    Value<String?>? mood,
    Value<String?>? notes,
    Value<double?>? bbt,
    Value<String?>? opk,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return DailyLogsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      flow: flow ?? this.flow,
      symptoms: symptoms ?? this.symptoms,
      mood: mood ?? this.mood,
      notes: notes ?? this.notes,
      bbt: bbt ?? this.bbt,
      opk: opk ?? this.opk,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (flow.present) {
      map['flow'] = Variable<int>(
        $DailyLogsTable.$converterflown.toSql(flow.value),
      );
    }
    if (symptoms.present) {
      map['symptoms'] = Variable<String>(symptoms.value);
    }
    if (mood.present) {
      map['mood'] = Variable<String>(mood.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (bbt.present) {
      map['bbt'] = Variable<double>(bbt.value);
    }
    if (opk.present) {
      map['opk'] = Variable<String>(opk.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyLogsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('flow: $flow, ')
          ..write('symptoms: $symptoms, ')
          ..write('mood: $mood, ')
          ..write('notes: $notes, ')
          ..write('bbt: $bbt, ')
          ..write('opk: $opk, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $RemindersTable extends Reminders
    with TableInfo<$RemindersTable, Reminder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  @override
  late final GeneratedColumnWithTypeConverter<ReminderType, int> type =
      GeneratedColumn<int>(
        'type',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<ReminderType>($RemindersTable.$convertertype);
  static const VerificationMeta _hourMeta = const VerificationMeta('hour');
  @override
  late final GeneratedColumn<int> hour = GeneratedColumn<int>(
    'hour',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _minuteMeta = const VerificationMeta('minute');
  @override
  late final GeneratedColumn<int> minute = GeneratedColumn<int>(
    'minute',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _recurrenceMeta = const VerificationMeta(
    'recurrence',
  );
  @override
  late final GeneratedColumn<String> recurrence = GeneratedColumn<String>(
    'recurrence',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    hour,
    minute,
    enabled,
    recurrence,
    title,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reminders';
  @override
  VerificationContext validateIntegrity(
    Insertable<Reminder> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('hour')) {
      context.handle(
        _hourMeta,
        hour.isAcceptableOrUnknown(data['hour']!, _hourMeta),
      );
    } else if (isInserting) {
      context.missing(_hourMeta);
    }
    if (data.containsKey('minute')) {
      context.handle(
        _minuteMeta,
        minute.isAcceptableOrUnknown(data['minute']!, _minuteMeta),
      );
    } else if (isInserting) {
      context.missing(_minuteMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('recurrence')) {
      context.handle(
        _recurrenceMeta,
        recurrence.isAcceptableOrUnknown(data['recurrence']!, _recurrenceMeta),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Reminder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Reminder(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      type: $RemindersTable.$convertertype.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}type'],
        )!,
      ),
      hour: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hour'],
      )!,
      minute: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minute'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      recurrence: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recurrence'],
      ),
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
    );
  }

  @override
  $RemindersTable createAlias(String alias) {
    return $RemindersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ReminderType, int, int> $convertertype =
      const EnumIndexConverter<ReminderType>(ReminderType.values);
}

class Reminder extends DataClass implements Insertable<Reminder> {
  final int id;
  final ReminderType type;
  final int hour;
  final int minute;
  final bool enabled;
  final String? recurrence;
  final String? title;
  final String? payload;
  const Reminder({
    required this.id,
    required this.type,
    required this.hour,
    required this.minute,
    required this.enabled,
    this.recurrence,
    this.title,
    this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['type'] = Variable<int>($RemindersTable.$convertertype.toSql(type));
    }
    map['hour'] = Variable<int>(hour);
    map['minute'] = Variable<int>(minute);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || recurrence != null) {
      map['recurrence'] = Variable<String>(recurrence);
    }
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    if (!nullToAbsent || payload != null) {
      map['payload'] = Variable<String>(payload);
    }
    return map;
  }

  RemindersCompanion toCompanion(bool nullToAbsent) {
    return RemindersCompanion(
      id: Value(id),
      type: Value(type),
      hour: Value(hour),
      minute: Value(minute),
      enabled: Value(enabled),
      recurrence: recurrence == null && nullToAbsent
          ? const Value.absent()
          : Value(recurrence),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      payload: payload == null && nullToAbsent
          ? const Value.absent()
          : Value(payload),
    );
  }

  factory Reminder.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Reminder(
      id: serializer.fromJson<int>(json['id']),
      type: $RemindersTable.$convertertype.fromJson(
        serializer.fromJson<int>(json['type']),
      ),
      hour: serializer.fromJson<int>(json['hour']),
      minute: serializer.fromJson<int>(json['minute']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      recurrence: serializer.fromJson<String?>(json['recurrence']),
      title: serializer.fromJson<String?>(json['title']),
      payload: serializer.fromJson<String?>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'type': serializer.toJson<int>(
        $RemindersTable.$convertertype.toJson(type),
      ),
      'hour': serializer.toJson<int>(hour),
      'minute': serializer.toJson<int>(minute),
      'enabled': serializer.toJson<bool>(enabled),
      'recurrence': serializer.toJson<String?>(recurrence),
      'title': serializer.toJson<String?>(title),
      'payload': serializer.toJson<String?>(payload),
    };
  }

  Reminder copyWith({
    int? id,
    ReminderType? type,
    int? hour,
    int? minute,
    bool? enabled,
    Value<String?> recurrence = const Value.absent(),
    Value<String?> title = const Value.absent(),
    Value<String?> payload = const Value.absent(),
  }) => Reminder(
    id: id ?? this.id,
    type: type ?? this.type,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    enabled: enabled ?? this.enabled,
    recurrence: recurrence.present ? recurrence.value : this.recurrence,
    title: title.present ? title.value : this.title,
    payload: payload.present ? payload.value : this.payload,
  );
  Reminder copyWithCompanion(RemindersCompanion data) {
    return Reminder(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      hour: data.hour.present ? data.hour.value : this.hour,
      minute: data.minute.present ? data.minute.value : this.minute,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      recurrence: data.recurrence.present
          ? data.recurrence.value
          : this.recurrence,
      title: data.title.present ? data.title.value : this.title,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Reminder(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('enabled: $enabled, ')
          ..write('recurrence: $recurrence, ')
          ..write('title: $title, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, type, hour, minute, enabled, recurrence, title, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Reminder &&
          other.id == this.id &&
          other.type == this.type &&
          other.hour == this.hour &&
          other.minute == this.minute &&
          other.enabled == this.enabled &&
          other.recurrence == this.recurrence &&
          other.title == this.title &&
          other.payload == this.payload);
}

class RemindersCompanion extends UpdateCompanion<Reminder> {
  final Value<int> id;
  final Value<ReminderType> type;
  final Value<int> hour;
  final Value<int> minute;
  final Value<bool> enabled;
  final Value<String?> recurrence;
  final Value<String?> title;
  final Value<String?> payload;
  const RemindersCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.hour = const Value.absent(),
    this.minute = const Value.absent(),
    this.enabled = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.title = const Value.absent(),
    this.payload = const Value.absent(),
  });
  RemindersCompanion.insert({
    this.id = const Value.absent(),
    required ReminderType type,
    required int hour,
    required int minute,
    this.enabled = const Value.absent(),
    this.recurrence = const Value.absent(),
    this.title = const Value.absent(),
    this.payload = const Value.absent(),
  }) : type = Value(type),
       hour = Value(hour),
       minute = Value(minute);
  static Insertable<Reminder> custom({
    Expression<int>? id,
    Expression<int>? type,
    Expression<int>? hour,
    Expression<int>? minute,
    Expression<bool>? enabled,
    Expression<String>? recurrence,
    Expression<String>? title,
    Expression<String>? payload,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (hour != null) 'hour': hour,
      if (minute != null) 'minute': minute,
      if (enabled != null) 'enabled': enabled,
      if (recurrence != null) 'recurrence': recurrence,
      if (title != null) 'title': title,
      if (payload != null) 'payload': payload,
    });
  }

  RemindersCompanion copyWith({
    Value<int>? id,
    Value<ReminderType>? type,
    Value<int>? hour,
    Value<int>? minute,
    Value<bool>? enabled,
    Value<String?>? recurrence,
    Value<String?>? title,
    Value<String?>? payload,
  }) {
    return RemindersCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      recurrence: recurrence ?? this.recurrence,
      title: title ?? this.title,
      payload: payload ?? this.payload,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<int>(
        $RemindersTable.$convertertype.toSql(type.value),
      );
    }
    if (hour.present) {
      map['hour'] = Variable<int>(hour.value);
    }
    if (minute.present) {
      map['minute'] = Variable<int>(minute.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (recurrence.present) {
      map['recurrence'] = Variable<String>(recurrence.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemindersCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('hour: $hour, ')
          ..write('minute: $minute, ')
          ..write('enabled: $enabled, ')
          ..write('recurrence: $recurrence, ')
          ..write('title: $title, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }
}

class $MedicationsTable extends Medications
    with TableInfo<$MedicationsTable, Medication> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MedicationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduleMeta = const VerificationMeta(
    'schedule',
  );
  @override
  late final GeneratedColumn<String> schedule = GeneratedColumn<String>(
    'schedule',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, type, schedule, enabled];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'medications';
  @override
  VerificationContext validateIntegrity(
    Insertable<Medication> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    }
    if (data.containsKey('schedule')) {
      context.handle(
        _scheduleMeta,
        schedule.isAcceptableOrUnknown(data['schedule']!, _scheduleMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Medication map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Medication(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      ),
      schedule: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
    );
  }

  @override
  $MedicationsTable createAlias(String alias) {
    return $MedicationsTable(attachedDatabase, alias);
  }
}

class Medication extends DataClass implements Insertable<Medication> {
  final int id;
  final String name;
  final String? type;
  final String? schedule;
  final bool enabled;
  const Medication({
    required this.id,
    required this.name,
    this.type,
    this.schedule,
    required this.enabled,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || type != null) {
      map['type'] = Variable<String>(type);
    }
    if (!nullToAbsent || schedule != null) {
      map['schedule'] = Variable<String>(schedule);
    }
    map['enabled'] = Variable<bool>(enabled);
    return map;
  }

  MedicationsCompanion toCompanion(bool nullToAbsent) {
    return MedicationsCompanion(
      id: Value(id),
      name: Value(name),
      type: type == null && nullToAbsent ? const Value.absent() : Value(type),
      schedule: schedule == null && nullToAbsent
          ? const Value.absent()
          : Value(schedule),
      enabled: Value(enabled),
    );
  }

  factory Medication.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Medication(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String?>(json['type']),
      schedule: serializer.fromJson<String?>(json['schedule']),
      enabled: serializer.fromJson<bool>(json['enabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String?>(type),
      'schedule': serializer.toJson<String?>(schedule),
      'enabled': serializer.toJson<bool>(enabled),
    };
  }

  Medication copyWith({
    int? id,
    String? name,
    Value<String?> type = const Value.absent(),
    Value<String?> schedule = const Value.absent(),
    bool? enabled,
  }) => Medication(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type.present ? type.value : this.type,
    schedule: schedule.present ? schedule.value : this.schedule,
    enabled: enabled ?? this.enabled,
  );
  Medication copyWithCompanion(MedicationsCompanion data) {
    return Medication(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      schedule: data.schedule.present ? data.schedule.value : this.schedule,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Medication(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('schedule: $schedule, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, type, schedule, enabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Medication &&
          other.id == this.id &&
          other.name == this.name &&
          other.type == this.type &&
          other.schedule == this.schedule &&
          other.enabled == this.enabled);
}

class MedicationsCompanion extends UpdateCompanion<Medication> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> type;
  final Value<String?> schedule;
  final Value<bool> enabled;
  const MedicationsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.schedule = const Value.absent(),
    this.enabled = const Value.absent(),
  });
  MedicationsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.type = const Value.absent(),
    this.schedule = const Value.absent(),
    this.enabled = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Medication> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? type,
    Expression<String>? schedule,
    Expression<bool>? enabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (schedule != null) 'schedule': schedule,
      if (enabled != null) 'enabled': enabled,
    });
  }

  MedicationsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String?>? type,
    Value<String?>? schedule,
    Value<bool>? enabled,
  }) {
    return MedicationsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      schedule: schedule ?? this.schedule,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (schedule.present) {
      map['schedule'] = Variable<String>(schedule.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MedicationsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('schedule: $schedule, ')
          ..write('enabled: $enabled')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  late final GeneratedColumnWithTypeConverter<TrackingMode, int> mode =
      GeneratedColumn<int>(
        'mode',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: Constant(TrackingMode.track.index),
      ).withConverter<TrackingMode>($AppSettingsTable.$convertermode);
  static const VerificationMeta _defaultCycleLengthMeta =
      const VerificationMeta('defaultCycleLength');
  @override
  late final GeneratedColumn<int> defaultCycleLength = GeneratedColumn<int>(
    'default_cycle_length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(28),
  );
  static const VerificationMeta _defaultPeriodLengthMeta =
      const VerificationMeta('defaultPeriodLength');
  @override
  late final GeneratedColumn<int> defaultPeriodLength = GeneratedColumn<int>(
    'default_period_length',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(5),
  );
  static const VerificationMeta _themeModeMeta = const VerificationMeta(
    'themeMode',
  );
  @override
  late final GeneratedColumn<String> themeMode = GeneratedColumn<String>(
    'theme_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('system'),
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('en'),
  );
  static const VerificationMeta _genderNeutralLanguageMeta =
      const VerificationMeta('genderNeutralLanguage');
  @override
  late final GeneratedColumn<bool> genderNeutralLanguage =
      GeneratedColumn<bool>(
        'gender_neutral_language',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("gender_neutral_language" IN (0, 1))',
        ),
        defaultValue: const Constant(false),
      );
  static const VerificationMeta _appLockEnabledMeta = const VerificationMeta(
    'appLockEnabled',
  );
  @override
  late final GeneratedColumn<bool> appLockEnabled = GeneratedColumn<bool>(
    'app_lock_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("app_lock_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _premiumMeta = const VerificationMeta(
    'premium',
  );
  @override
  late final GeneratedColumn<bool> premium = GeneratedColumn<bool>(
    'premium',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("premium" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _onboardingCompleteMeta =
      const VerificationMeta('onboardingComplete');
  @override
  late final GeneratedColumn<bool> onboardingComplete = GeneratedColumn<bool>(
    'onboarding_complete',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("onboarding_complete" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastBackupMeta = const VerificationMeta(
    'lastBackup',
  );
  @override
  late final GeneratedColumn<DateTime> lastBackup = GeneratedColumn<DateTime>(
    'last_backup',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pregnancyStartDateMeta =
      const VerificationMeta('pregnancyStartDate');
  @override
  late final GeneratedColumn<DateTime> pregnancyStartDate =
      GeneratedColumn<DateTime>(
        'pregnancy_start_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _trackingCategoriesMeta =
      const VerificationMeta('trackingCategories');
  @override
  late final GeneratedColumn<String> trackingCategories =
      GeneratedColumn<String>(
        'tracking_categories',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _weightUnitMeta = const VerificationMeta(
    'weightUnit',
  );
  @override
  late final GeneratedColumn<String> weightUnit = GeneratedColumn<String>(
    'weight_unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSyncedAt = GeneratedColumn<DateTime>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _settingsUpdatedAtMeta = const VerificationMeta(
    'settingsUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> settingsUpdatedAt =
      GeneratedColumn<DateTime>(
        'settings_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _analysisConsentUidMeta =
      const VerificationMeta('analysisConsentUid');
  @override
  late final GeneratedColumn<String> analysisConsentUid =
      GeneratedColumn<String>(
        'analysis_consent_uid',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _analysisCountDayMeta = const VerificationMeta(
    'analysisCountDay',
  );
  @override
  late final GeneratedColumn<String> analysisCountDay = GeneratedColumn<String>(
    'analysis_count_day',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _analysisCountTodayMeta =
      const VerificationMeta('analysisCountToday');
  @override
  late final GeneratedColumn<int> analysisCountToday = GeneratedColumn<int>(
    'analysis_count_today',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mode,
    defaultCycleLength,
    defaultPeriodLength,
    themeMode,
    language,
    genderNeutralLanguage,
    appLockEnabled,
    premium,
    onboardingComplete,
    lastBackup,
    pregnancyStartDate,
    trackingCategories,
    weightUnit,
    lastSyncedAt,
    settingsUpdatedAt,
    analysisConsentUid,
    analysisCountDay,
    analysisCountToday,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('default_cycle_length')) {
      context.handle(
        _defaultCycleLengthMeta,
        defaultCycleLength.isAcceptableOrUnknown(
          data['default_cycle_length']!,
          _defaultCycleLengthMeta,
        ),
      );
    }
    if (data.containsKey('default_period_length')) {
      context.handle(
        _defaultPeriodLengthMeta,
        defaultPeriodLength.isAcceptableOrUnknown(
          data['default_period_length']!,
          _defaultPeriodLengthMeta,
        ),
      );
    }
    if (data.containsKey('theme_mode')) {
      context.handle(
        _themeModeMeta,
        themeMode.isAcceptableOrUnknown(data['theme_mode']!, _themeModeMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('gender_neutral_language')) {
      context.handle(
        _genderNeutralLanguageMeta,
        genderNeutralLanguage.isAcceptableOrUnknown(
          data['gender_neutral_language']!,
          _genderNeutralLanguageMeta,
        ),
      );
    }
    if (data.containsKey('app_lock_enabled')) {
      context.handle(
        _appLockEnabledMeta,
        appLockEnabled.isAcceptableOrUnknown(
          data['app_lock_enabled']!,
          _appLockEnabledMeta,
        ),
      );
    }
    if (data.containsKey('premium')) {
      context.handle(
        _premiumMeta,
        premium.isAcceptableOrUnknown(data['premium']!, _premiumMeta),
      );
    }
    if (data.containsKey('onboarding_complete')) {
      context.handle(
        _onboardingCompleteMeta,
        onboardingComplete.isAcceptableOrUnknown(
          data['onboarding_complete']!,
          _onboardingCompleteMeta,
        ),
      );
    }
    if (data.containsKey('last_backup')) {
      context.handle(
        _lastBackupMeta,
        lastBackup.isAcceptableOrUnknown(data['last_backup']!, _lastBackupMeta),
      );
    }
    if (data.containsKey('pregnancy_start_date')) {
      context.handle(
        _pregnancyStartDateMeta,
        pregnancyStartDate.isAcceptableOrUnknown(
          data['pregnancy_start_date']!,
          _pregnancyStartDateMeta,
        ),
      );
    }
    if (data.containsKey('tracking_categories')) {
      context.handle(
        _trackingCategoriesMeta,
        trackingCategories.isAcceptableOrUnknown(
          data['tracking_categories']!,
          _trackingCategoriesMeta,
        ),
      );
    }
    if (data.containsKey('weight_unit')) {
      context.handle(
        _weightUnitMeta,
        weightUnit.isAcceptableOrUnknown(data['weight_unit']!, _weightUnitMeta),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('settings_updated_at')) {
      context.handle(
        _settingsUpdatedAtMeta,
        settingsUpdatedAt.isAcceptableOrUnknown(
          data['settings_updated_at']!,
          _settingsUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('analysis_consent_uid')) {
      context.handle(
        _analysisConsentUidMeta,
        analysisConsentUid.isAcceptableOrUnknown(
          data['analysis_consent_uid']!,
          _analysisConsentUidMeta,
        ),
      );
    }
    if (data.containsKey('analysis_count_day')) {
      context.handle(
        _analysisCountDayMeta,
        analysisCountDay.isAcceptableOrUnknown(
          data['analysis_count_day']!,
          _analysisCountDayMeta,
        ),
      );
    }
    if (data.containsKey('analysis_count_today')) {
      context.handle(
        _analysisCountTodayMeta,
        analysisCountToday.isAcceptableOrUnknown(
          data['analysis_count_today']!,
          _analysisCountTodayMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      mode: $AppSettingsTable.$convertermode.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}mode'],
        )!,
      ),
      defaultCycleLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_cycle_length'],
      )!,
      defaultPeriodLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}default_period_length'],
      )!,
      themeMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}theme_mode'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      genderNeutralLanguage: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}gender_neutral_language'],
      )!,
      appLockEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}app_lock_enabled'],
      )!,
      premium: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}premium'],
      )!,
      onboardingComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}onboarding_complete'],
      )!,
      lastBackup: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_backup'],
      ),
      pregnancyStartDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pregnancy_start_date'],
      ),
      trackingCategories: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tracking_categories'],
      ),
      weightUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}weight_unit'],
      ),
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_synced_at'],
      ),
      settingsUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}settings_updated_at'],
      ),
      analysisConsentUid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}analysis_consent_uid'],
      ),
      analysisCountDay: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}analysis_count_day'],
      ),
      analysisCountToday: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}analysis_count_today'],
      ),
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TrackingMode, int, int> $convertermode =
      const EnumIndexConverter<TrackingMode>(TrackingMode.values);
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final int id;
  final TrackingMode mode;
  final int defaultCycleLength;
  final int defaultPeriodLength;
  final String themeMode;
  final String language;
  final bool genderNeutralLanguage;
  final bool appLockEnabled;
  final bool premium;
  final bool onboardingComplete;
  final DateTime? lastBackup;
  final DateTime? pregnancyStartDate;
  final String? trackingCategories;
  final String? weightUnit;
  final DateTime? lastSyncedAt;
  final DateTime? settingsUpdatedAt;
  final String? analysisConsentUid;
  final String? analysisCountDay;
  final int? analysisCountToday;
  const AppSetting({
    required this.id,
    required this.mode,
    required this.defaultCycleLength,
    required this.defaultPeriodLength,
    required this.themeMode,
    required this.language,
    required this.genderNeutralLanguage,
    required this.appLockEnabled,
    required this.premium,
    required this.onboardingComplete,
    this.lastBackup,
    this.pregnancyStartDate,
    this.trackingCategories,
    this.weightUnit,
    this.lastSyncedAt,
    this.settingsUpdatedAt,
    this.analysisConsentUid,
    this.analysisCountDay,
    this.analysisCountToday,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    {
      map['mode'] = Variable<int>($AppSettingsTable.$convertermode.toSql(mode));
    }
    map['default_cycle_length'] = Variable<int>(defaultCycleLength);
    map['default_period_length'] = Variable<int>(defaultPeriodLength);
    map['theme_mode'] = Variable<String>(themeMode);
    map['language'] = Variable<String>(language);
    map['gender_neutral_language'] = Variable<bool>(genderNeutralLanguage);
    map['app_lock_enabled'] = Variable<bool>(appLockEnabled);
    map['premium'] = Variable<bool>(premium);
    map['onboarding_complete'] = Variable<bool>(onboardingComplete);
    if (!nullToAbsent || lastBackup != null) {
      map['last_backup'] = Variable<DateTime>(lastBackup);
    }
    if (!nullToAbsent || pregnancyStartDate != null) {
      map['pregnancy_start_date'] = Variable<DateTime>(pregnancyStartDate);
    }
    if (!nullToAbsent || trackingCategories != null) {
      map['tracking_categories'] = Variable<String>(trackingCategories);
    }
    if (!nullToAbsent || weightUnit != null) {
      map['weight_unit'] = Variable<String>(weightUnit);
    }
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt);
    }
    if (!nullToAbsent || settingsUpdatedAt != null) {
      map['settings_updated_at'] = Variable<DateTime>(settingsUpdatedAt);
    }
    if (!nullToAbsent || analysisConsentUid != null) {
      map['analysis_consent_uid'] = Variable<String>(analysisConsentUid);
    }
    if (!nullToAbsent || analysisCountDay != null) {
      map['analysis_count_day'] = Variable<String>(analysisCountDay);
    }
    if (!nullToAbsent || analysisCountToday != null) {
      map['analysis_count_today'] = Variable<int>(analysisCountToday);
    }
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      mode: Value(mode),
      defaultCycleLength: Value(defaultCycleLength),
      defaultPeriodLength: Value(defaultPeriodLength),
      themeMode: Value(themeMode),
      language: Value(language),
      genderNeutralLanguage: Value(genderNeutralLanguage),
      appLockEnabled: Value(appLockEnabled),
      premium: Value(premium),
      onboardingComplete: Value(onboardingComplete),
      lastBackup: lastBackup == null && nullToAbsent
          ? const Value.absent()
          : Value(lastBackup),
      pregnancyStartDate: pregnancyStartDate == null && nullToAbsent
          ? const Value.absent()
          : Value(pregnancyStartDate),
      trackingCategories: trackingCategories == null && nullToAbsent
          ? const Value.absent()
          : Value(trackingCategories),
      weightUnit: weightUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(weightUnit),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      settingsUpdatedAt: settingsUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(settingsUpdatedAt),
      analysisConsentUid: analysisConsentUid == null && nullToAbsent
          ? const Value.absent()
          : Value(analysisConsentUid),
      analysisCountDay: analysisCountDay == null && nullToAbsent
          ? const Value.absent()
          : Value(analysisCountDay),
      analysisCountToday: analysisCountToday == null && nullToAbsent
          ? const Value.absent()
          : Value(analysisCountToday),
    );
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      id: serializer.fromJson<int>(json['id']),
      mode: $AppSettingsTable.$convertermode.fromJson(
        serializer.fromJson<int>(json['mode']),
      ),
      defaultCycleLength: serializer.fromJson<int>(json['defaultCycleLength']),
      defaultPeriodLength: serializer.fromJson<int>(
        json['defaultPeriodLength'],
      ),
      themeMode: serializer.fromJson<String>(json['themeMode']),
      language: serializer.fromJson<String>(json['language']),
      genderNeutralLanguage: serializer.fromJson<bool>(
        json['genderNeutralLanguage'],
      ),
      appLockEnabled: serializer.fromJson<bool>(json['appLockEnabled']),
      premium: serializer.fromJson<bool>(json['premium']),
      onboardingComplete: serializer.fromJson<bool>(json['onboardingComplete']),
      lastBackup: serializer.fromJson<DateTime?>(json['lastBackup']),
      pregnancyStartDate: serializer.fromJson<DateTime?>(
        json['pregnancyStartDate'],
      ),
      trackingCategories: serializer.fromJson<String?>(
        json['trackingCategories'],
      ),
      weightUnit: serializer.fromJson<String?>(json['weightUnit']),
      lastSyncedAt: serializer.fromJson<DateTime?>(json['lastSyncedAt']),
      settingsUpdatedAt: serializer.fromJson<DateTime?>(
        json['settingsUpdatedAt'],
      ),
      analysisConsentUid: serializer.fromJson<String?>(
        json['analysisConsentUid'],
      ),
      analysisCountDay: serializer.fromJson<String?>(json['analysisCountDay']),
      analysisCountToday: serializer.fromJson<int?>(json['analysisCountToday']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'mode': serializer.toJson<int>(
        $AppSettingsTable.$convertermode.toJson(mode),
      ),
      'defaultCycleLength': serializer.toJson<int>(defaultCycleLength),
      'defaultPeriodLength': serializer.toJson<int>(defaultPeriodLength),
      'themeMode': serializer.toJson<String>(themeMode),
      'language': serializer.toJson<String>(language),
      'genderNeutralLanguage': serializer.toJson<bool>(genderNeutralLanguage),
      'appLockEnabled': serializer.toJson<bool>(appLockEnabled),
      'premium': serializer.toJson<bool>(premium),
      'onboardingComplete': serializer.toJson<bool>(onboardingComplete),
      'lastBackup': serializer.toJson<DateTime?>(lastBackup),
      'pregnancyStartDate': serializer.toJson<DateTime?>(pregnancyStartDate),
      'trackingCategories': serializer.toJson<String?>(trackingCategories),
      'weightUnit': serializer.toJson<String?>(weightUnit),
      'lastSyncedAt': serializer.toJson<DateTime?>(lastSyncedAt),
      'settingsUpdatedAt': serializer.toJson<DateTime?>(settingsUpdatedAt),
      'analysisConsentUid': serializer.toJson<String?>(analysisConsentUid),
      'analysisCountDay': serializer.toJson<String?>(analysisCountDay),
      'analysisCountToday': serializer.toJson<int?>(analysisCountToday),
    };
  }

  AppSetting copyWith({
    int? id,
    TrackingMode? mode,
    int? defaultCycleLength,
    int? defaultPeriodLength,
    String? themeMode,
    String? language,
    bool? genderNeutralLanguage,
    bool? appLockEnabled,
    bool? premium,
    bool? onboardingComplete,
    Value<DateTime?> lastBackup = const Value.absent(),
    Value<DateTime?> pregnancyStartDate = const Value.absent(),
    Value<String?> trackingCategories = const Value.absent(),
    Value<String?> weightUnit = const Value.absent(),
    Value<DateTime?> lastSyncedAt = const Value.absent(),
    Value<DateTime?> settingsUpdatedAt = const Value.absent(),
    Value<String?> analysisConsentUid = const Value.absent(),
    Value<String?> analysisCountDay = const Value.absent(),
    Value<int?> analysisCountToday = const Value.absent(),
  }) => AppSetting(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    defaultCycleLength: defaultCycleLength ?? this.defaultCycleLength,
    defaultPeriodLength: defaultPeriodLength ?? this.defaultPeriodLength,
    themeMode: themeMode ?? this.themeMode,
    language: language ?? this.language,
    genderNeutralLanguage: genderNeutralLanguage ?? this.genderNeutralLanguage,
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    premium: premium ?? this.premium,
    onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    lastBackup: lastBackup.present ? lastBackup.value : this.lastBackup,
    pregnancyStartDate: pregnancyStartDate.present
        ? pregnancyStartDate.value
        : this.pregnancyStartDate,
    trackingCategories: trackingCategories.present
        ? trackingCategories.value
        : this.trackingCategories,
    weightUnit: weightUnit.present ? weightUnit.value : this.weightUnit,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    settingsUpdatedAt: settingsUpdatedAt.present
        ? settingsUpdatedAt.value
        : this.settingsUpdatedAt,
    analysisConsentUid: analysisConsentUid.present
        ? analysisConsentUid.value
        : this.analysisConsentUid,
    analysisCountDay: analysisCountDay.present
        ? analysisCountDay.value
        : this.analysisCountDay,
    analysisCountToday: analysisCountToday.present
        ? analysisCountToday.value
        : this.analysisCountToday,
  );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      defaultCycleLength: data.defaultCycleLength.present
          ? data.defaultCycleLength.value
          : this.defaultCycleLength,
      defaultPeriodLength: data.defaultPeriodLength.present
          ? data.defaultPeriodLength.value
          : this.defaultPeriodLength,
      themeMode: data.themeMode.present ? data.themeMode.value : this.themeMode,
      language: data.language.present ? data.language.value : this.language,
      genderNeutralLanguage: data.genderNeutralLanguage.present
          ? data.genderNeutralLanguage.value
          : this.genderNeutralLanguage,
      appLockEnabled: data.appLockEnabled.present
          ? data.appLockEnabled.value
          : this.appLockEnabled,
      premium: data.premium.present ? data.premium.value : this.premium,
      onboardingComplete: data.onboardingComplete.present
          ? data.onboardingComplete.value
          : this.onboardingComplete,
      lastBackup: data.lastBackup.present
          ? data.lastBackup.value
          : this.lastBackup,
      pregnancyStartDate: data.pregnancyStartDate.present
          ? data.pregnancyStartDate.value
          : this.pregnancyStartDate,
      trackingCategories: data.trackingCategories.present
          ? data.trackingCategories.value
          : this.trackingCategories,
      weightUnit: data.weightUnit.present
          ? data.weightUnit.value
          : this.weightUnit,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      settingsUpdatedAt: data.settingsUpdatedAt.present
          ? data.settingsUpdatedAt.value
          : this.settingsUpdatedAt,
      analysisConsentUid: data.analysisConsentUid.present
          ? data.analysisConsentUid.value
          : this.analysisConsentUid,
      analysisCountDay: data.analysisCountDay.present
          ? data.analysisCountDay.value
          : this.analysisCountDay,
      analysisCountToday: data.analysisCountToday.present
          ? data.analysisCountToday.value
          : this.analysisCountToday,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('defaultCycleLength: $defaultCycleLength, ')
          ..write('defaultPeriodLength: $defaultPeriodLength, ')
          ..write('themeMode: $themeMode, ')
          ..write('language: $language, ')
          ..write('genderNeutralLanguage: $genderNeutralLanguage, ')
          ..write('appLockEnabled: $appLockEnabled, ')
          ..write('premium: $premium, ')
          ..write('onboardingComplete: $onboardingComplete, ')
          ..write('lastBackup: $lastBackup, ')
          ..write('pregnancyStartDate: $pregnancyStartDate, ')
          ..write('trackingCategories: $trackingCategories, ')
          ..write('weightUnit: $weightUnit, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('settingsUpdatedAt: $settingsUpdatedAt, ')
          ..write('analysisConsentUid: $analysisConsentUid, ')
          ..write('analysisCountDay: $analysisCountDay, ')
          ..write('analysisCountToday: $analysisCountToday')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    mode,
    defaultCycleLength,
    defaultPeriodLength,
    themeMode,
    language,
    genderNeutralLanguage,
    appLockEnabled,
    premium,
    onboardingComplete,
    lastBackup,
    pregnancyStartDate,
    trackingCategories,
    weightUnit,
    lastSyncedAt,
    settingsUpdatedAt,
    analysisConsentUid,
    analysisCountDay,
    analysisCountToday,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.defaultCycleLength == this.defaultCycleLength &&
          other.defaultPeriodLength == this.defaultPeriodLength &&
          other.themeMode == this.themeMode &&
          other.language == this.language &&
          other.genderNeutralLanguage == this.genderNeutralLanguage &&
          other.appLockEnabled == this.appLockEnabled &&
          other.premium == this.premium &&
          other.onboardingComplete == this.onboardingComplete &&
          other.lastBackup == this.lastBackup &&
          other.pregnancyStartDate == this.pregnancyStartDate &&
          other.trackingCategories == this.trackingCategories &&
          other.weightUnit == this.weightUnit &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.settingsUpdatedAt == this.settingsUpdatedAt &&
          other.analysisConsentUid == this.analysisConsentUid &&
          other.analysisCountDay == this.analysisCountDay &&
          other.analysisCountToday == this.analysisCountToday);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<int> id;
  final Value<TrackingMode> mode;
  final Value<int> defaultCycleLength;
  final Value<int> defaultPeriodLength;
  final Value<String> themeMode;
  final Value<String> language;
  final Value<bool> genderNeutralLanguage;
  final Value<bool> appLockEnabled;
  final Value<bool> premium;
  final Value<bool> onboardingComplete;
  final Value<DateTime?> lastBackup;
  final Value<DateTime?> pregnancyStartDate;
  final Value<String?> trackingCategories;
  final Value<String?> weightUnit;
  final Value<DateTime?> lastSyncedAt;
  final Value<DateTime?> settingsUpdatedAt;
  final Value<String?> analysisConsentUid;
  final Value<String?> analysisCountDay;
  final Value<int?> analysisCountToday;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.defaultCycleLength = const Value.absent(),
    this.defaultPeriodLength = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.language = const Value.absent(),
    this.genderNeutralLanguage = const Value.absent(),
    this.appLockEnabled = const Value.absent(),
    this.premium = const Value.absent(),
    this.onboardingComplete = const Value.absent(),
    this.lastBackup = const Value.absent(),
    this.pregnancyStartDate = const Value.absent(),
    this.trackingCategories = const Value.absent(),
    this.weightUnit = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.settingsUpdatedAt = const Value.absent(),
    this.analysisConsentUid = const Value.absent(),
    this.analysisCountDay = const Value.absent(),
    this.analysisCountToday = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.defaultCycleLength = const Value.absent(),
    this.defaultPeriodLength = const Value.absent(),
    this.themeMode = const Value.absent(),
    this.language = const Value.absent(),
    this.genderNeutralLanguage = const Value.absent(),
    this.appLockEnabled = const Value.absent(),
    this.premium = const Value.absent(),
    this.onboardingComplete = const Value.absent(),
    this.lastBackup = const Value.absent(),
    this.pregnancyStartDate = const Value.absent(),
    this.trackingCategories = const Value.absent(),
    this.weightUnit = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.settingsUpdatedAt = const Value.absent(),
    this.analysisConsentUid = const Value.absent(),
    this.analysisCountDay = const Value.absent(),
    this.analysisCountToday = const Value.absent(),
  });
  static Insertable<AppSetting> custom({
    Expression<int>? id,
    Expression<int>? mode,
    Expression<int>? defaultCycleLength,
    Expression<int>? defaultPeriodLength,
    Expression<String>? themeMode,
    Expression<String>? language,
    Expression<bool>? genderNeutralLanguage,
    Expression<bool>? appLockEnabled,
    Expression<bool>? premium,
    Expression<bool>? onboardingComplete,
    Expression<DateTime>? lastBackup,
    Expression<DateTime>? pregnancyStartDate,
    Expression<String>? trackingCategories,
    Expression<String>? weightUnit,
    Expression<DateTime>? lastSyncedAt,
    Expression<DateTime>? settingsUpdatedAt,
    Expression<String>? analysisConsentUid,
    Expression<String>? analysisCountDay,
    Expression<int>? analysisCountToday,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (defaultCycleLength != null)
        'default_cycle_length': defaultCycleLength,
      if (defaultPeriodLength != null)
        'default_period_length': defaultPeriodLength,
      if (themeMode != null) 'theme_mode': themeMode,
      if (language != null) 'language': language,
      if (genderNeutralLanguage != null)
        'gender_neutral_language': genderNeutralLanguage,
      if (appLockEnabled != null) 'app_lock_enabled': appLockEnabled,
      if (premium != null) 'premium': premium,
      if (onboardingComplete != null) 'onboarding_complete': onboardingComplete,
      if (lastBackup != null) 'last_backup': lastBackup,
      if (pregnancyStartDate != null)
        'pregnancy_start_date': pregnancyStartDate,
      if (trackingCategories != null) 'tracking_categories': trackingCategories,
      if (weightUnit != null) 'weight_unit': weightUnit,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (settingsUpdatedAt != null) 'settings_updated_at': settingsUpdatedAt,
      if (analysisConsentUid != null)
        'analysis_consent_uid': analysisConsentUid,
      if (analysisCountDay != null) 'analysis_count_day': analysisCountDay,
      if (analysisCountToday != null)
        'analysis_count_today': analysisCountToday,
    });
  }

  AppSettingsCompanion copyWith({
    Value<int>? id,
    Value<TrackingMode>? mode,
    Value<int>? defaultCycleLength,
    Value<int>? defaultPeriodLength,
    Value<String>? themeMode,
    Value<String>? language,
    Value<bool>? genderNeutralLanguage,
    Value<bool>? appLockEnabled,
    Value<bool>? premium,
    Value<bool>? onboardingComplete,
    Value<DateTime?>? lastBackup,
    Value<DateTime?>? pregnancyStartDate,
    Value<String?>? trackingCategories,
    Value<String?>? weightUnit,
    Value<DateTime?>? lastSyncedAt,
    Value<DateTime?>? settingsUpdatedAt,
    Value<String?>? analysisConsentUid,
    Value<String?>? analysisCountDay,
    Value<int?>? analysisCountToday,
  }) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      defaultCycleLength: defaultCycleLength ?? this.defaultCycleLength,
      defaultPeriodLength: defaultPeriodLength ?? this.defaultPeriodLength,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      genderNeutralLanguage:
          genderNeutralLanguage ?? this.genderNeutralLanguage,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      premium: premium ?? this.premium,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      lastBackup: lastBackup ?? this.lastBackup,
      pregnancyStartDate: pregnancyStartDate ?? this.pregnancyStartDate,
      trackingCategories: trackingCategories ?? this.trackingCategories,
      weightUnit: weightUnit ?? this.weightUnit,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      settingsUpdatedAt: settingsUpdatedAt ?? this.settingsUpdatedAt,
      analysisConsentUid: analysisConsentUid ?? this.analysisConsentUid,
      analysisCountDay: analysisCountDay ?? this.analysisCountDay,
      analysisCountToday: analysisCountToday ?? this.analysisCountToday,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<int>(
        $AppSettingsTable.$convertermode.toSql(mode.value),
      );
    }
    if (defaultCycleLength.present) {
      map['default_cycle_length'] = Variable<int>(defaultCycleLength.value);
    }
    if (defaultPeriodLength.present) {
      map['default_period_length'] = Variable<int>(defaultPeriodLength.value);
    }
    if (themeMode.present) {
      map['theme_mode'] = Variable<String>(themeMode.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (genderNeutralLanguage.present) {
      map['gender_neutral_language'] = Variable<bool>(
        genderNeutralLanguage.value,
      );
    }
    if (appLockEnabled.present) {
      map['app_lock_enabled'] = Variable<bool>(appLockEnabled.value);
    }
    if (premium.present) {
      map['premium'] = Variable<bool>(premium.value);
    }
    if (onboardingComplete.present) {
      map['onboarding_complete'] = Variable<bool>(onboardingComplete.value);
    }
    if (lastBackup.present) {
      map['last_backup'] = Variable<DateTime>(lastBackup.value);
    }
    if (pregnancyStartDate.present) {
      map['pregnancy_start_date'] = Variable<DateTime>(
        pregnancyStartDate.value,
      );
    }
    if (trackingCategories.present) {
      map['tracking_categories'] = Variable<String>(trackingCategories.value);
    }
    if (weightUnit.present) {
      map['weight_unit'] = Variable<String>(weightUnit.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<DateTime>(lastSyncedAt.value);
    }
    if (settingsUpdatedAt.present) {
      map['settings_updated_at'] = Variable<DateTime>(settingsUpdatedAt.value);
    }
    if (analysisConsentUid.present) {
      map['analysis_consent_uid'] = Variable<String>(analysisConsentUid.value);
    }
    if (analysisCountDay.present) {
      map['analysis_count_day'] = Variable<String>(analysisCountDay.value);
    }
    if (analysisCountToday.present) {
      map['analysis_count_today'] = Variable<int>(analysisCountToday.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('defaultCycleLength: $defaultCycleLength, ')
          ..write('defaultPeriodLength: $defaultPeriodLength, ')
          ..write('themeMode: $themeMode, ')
          ..write('language: $language, ')
          ..write('genderNeutralLanguage: $genderNeutralLanguage, ')
          ..write('appLockEnabled: $appLockEnabled, ')
          ..write('premium: $premium, ')
          ..write('onboardingComplete: $onboardingComplete, ')
          ..write('lastBackup: $lastBackup, ')
          ..write('pregnancyStartDate: $pregnancyStartDate, ')
          ..write('trackingCategories: $trackingCategories, ')
          ..write('weightUnit: $weightUnit, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('settingsUpdatedAt: $settingsUpdatedAt, ')
          ..write('analysisConsentUid: $analysisConsentUid, ')
          ..write('analysisCountDay: $analysisCountDay, ')
          ..write('analysisCountToday: $analysisCountToday')
          ..write(')'))
        .toString();
  }
}

class $SyncTombstonesTable extends SyncTombstones
    with TableInfo<$SyncTombstonesTable, SyncTombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncTombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [id, date, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncTombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {date},
  ];
  @override
  SyncTombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncTombstone(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $SyncTombstonesTable createAlias(String alias) {
    return $SyncTombstonesTable(attachedDatabase, alias);
  }
}

class SyncTombstone extends DataClass implements Insertable<SyncTombstone> {
  final int id;
  final DateTime date;
  final DateTime deletedAt;
  const SyncTombstone({
    required this.id,
    required this.date,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<DateTime>(date);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    return map;
  }

  SyncTombstonesCompanion toCompanion(bool nullToAbsent) {
    return SyncTombstonesCompanion(
      id: Value(id),
      date: Value(date),
      deletedAt: Value(deletedAt),
    );
  }

  factory SyncTombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncTombstone(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
    };
  }

  SyncTombstone copyWith({int? id, DateTime? date, DateTime? deletedAt}) =>
      SyncTombstone(
        id: id ?? this.id,
        date: date ?? this.date,
        deletedAt: deletedAt ?? this.deletedAt,
      );
  SyncTombstone copyWithCompanion(SyncTombstonesCompanion data) {
    return SyncTombstone(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstone(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, date, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncTombstone &&
          other.id == this.id &&
          other.date == this.date &&
          other.deletedAt == this.deletedAt);
}

class SyncTombstonesCompanion extends UpdateCompanion<SyncTombstone> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<DateTime> deletedAt;
  const SyncTombstonesCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.deletedAt = const Value.absent(),
  });
  SyncTombstonesCompanion.insert({
    this.id = const Value.absent(),
    required DateTime date,
    this.deletedAt = const Value.absent(),
  }) : date = Value(date);
  static Insertable<SyncTombstone> custom({
    Expression<int>? id,
    Expression<DateTime>? date,
    Expression<DateTime>? deletedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (deletedAt != null) 'deleted_at': deletedAt,
    });
  }

  SyncTombstonesCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? date,
    Value<DateTime>? deletedAt,
  }) {
    return SyncTombstonesCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncTombstonesCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }
}

class $MediaItemsTable extends MediaItems
    with TableInfo<$MediaItemsTable, MediaItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uidMeta = const VerificationMeta('uid');
  @override
  late final GeneratedColumn<String> uid = GeneratedColumn<String>(
    'uid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _storagePathMeta = const VerificationMeta(
    'storagePath',
  );
  @override
  late final GeneratedColumn<String> storagePath = GeneratedColumn<String>(
    'storage_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thumbPathMeta = const VerificationMeta(
    'thumbPath',
  );
  @override
  late final GeneratedColumn<String> thumbPath = GeneratedColumn<String>(
    'thumb_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
    'width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
    'height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _capturedAtMeta = const VerificationMeta(
    'capturedAt',
  );
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
    'captured_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _thumbnailMeta = const VerificationMeta(
    'thumbnail',
  );
  @override
  late final GeneratedColumn<Uint8List> thumbnail = GeneratedColumn<Uint8List>(
    'thumbnail',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uid,
    kind,
    storagePath,
    thumbPath,
    bytes,
    width,
    height,
    durationMs,
    caption,
    capturedAt,
    createdAt,
    updatedAt,
    thumbnail,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('uid')) {
      context.handle(
        _uidMeta,
        uid.isAcceptableOrUnknown(data['uid']!, _uidMeta),
      );
    } else if (isInserting) {
      context.missing(_uidMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('storage_path')) {
      context.handle(
        _storagePathMeta,
        storagePath.isAcceptableOrUnknown(
          data['storage_path']!,
          _storagePathMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_storagePathMeta);
    }
    if (data.containsKey('thumb_path')) {
      context.handle(
        _thumbPathMeta,
        thumbPath.isAcceptableOrUnknown(data['thumb_path']!, _thumbPathMeta),
      );
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    }
    if (data.containsKey('height')) {
      context.handle(
        _heightMeta,
        height.isAcceptableOrUnknown(data['height']!, _heightMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    }
    if (data.containsKey('captured_at')) {
      context.handle(
        _capturedAtMeta,
        capturedAt.isAcceptableOrUnknown(data['captured_at']!, _capturedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('thumbnail')) {
      context.handle(
        _thumbnailMeta,
        thumbnail.isAcceptableOrUnknown(data['thumbnail']!, _thumbnailMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      uid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uid'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      storagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}storage_path'],
      )!,
      thumbPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}thumb_path'],
      ),
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}width'],
      ),
      height: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height'],
      ),
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      ),
      capturedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}captured_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      thumbnail: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}thumbnail'],
      ),
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }
}

class MediaItem extends DataClass implements Insertable<MediaItem> {
  final String id;
  final String uid;
  final String kind;
  final String storagePath;
  final String? thumbPath;
  final int bytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? caption;
  final DateTime capturedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Uint8List? thumbnail;
  const MediaItem({
    required this.id,
    required this.uid,
    required this.kind,
    required this.storagePath,
    this.thumbPath,
    required this.bytes,
    this.width,
    this.height,
    this.durationMs,
    this.caption,
    required this.capturedAt,
    required this.createdAt,
    required this.updatedAt,
    this.thumbnail,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['uid'] = Variable<String>(uid);
    map['kind'] = Variable<String>(kind);
    map['storage_path'] = Variable<String>(storagePath);
    if (!nullToAbsent || thumbPath != null) {
      map['thumb_path'] = Variable<String>(thumbPath);
    }
    map['bytes'] = Variable<int>(bytes);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    if (!nullToAbsent || caption != null) {
      map['caption'] = Variable<String>(caption);
    }
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || thumbnail != null) {
      map['thumbnail'] = Variable<Uint8List>(thumbnail);
    }
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      id: Value(id),
      uid: Value(uid),
      kind: Value(kind),
      storagePath: Value(storagePath),
      thumbPath: thumbPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbPath),
      bytes: Value(bytes),
      width: width == null && nullToAbsent
          ? const Value.absent()
          : Value(width),
      height: height == null && nullToAbsent
          ? const Value.absent()
          : Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      caption: caption == null && nullToAbsent
          ? const Value.absent()
          : Value(caption),
      capturedAt: Value(capturedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      thumbnail: thumbnail == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnail),
    );
  }

  factory MediaItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItem(
      id: serializer.fromJson<String>(json['id']),
      uid: serializer.fromJson<String>(json['uid']),
      kind: serializer.fromJson<String>(json['kind']),
      storagePath: serializer.fromJson<String>(json['storagePath']),
      thumbPath: serializer.fromJson<String?>(json['thumbPath']),
      bytes: serializer.fromJson<int>(json['bytes']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      caption: serializer.fromJson<String?>(json['caption']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      thumbnail: serializer.fromJson<Uint8List?>(json['thumbnail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'uid': serializer.toJson<String>(uid),
      'kind': serializer.toJson<String>(kind),
      'storagePath': serializer.toJson<String>(storagePath),
      'thumbPath': serializer.toJson<String?>(thumbPath),
      'bytes': serializer.toJson<int>(bytes),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'caption': serializer.toJson<String?>(caption),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'thumbnail': serializer.toJson<Uint8List?>(thumbnail),
    };
  }

  MediaItem copyWith({
    String? id,
    String? uid,
    String? kind,
    String? storagePath,
    Value<String?> thumbPath = const Value.absent(),
    int? bytes,
    Value<int?> width = const Value.absent(),
    Value<int?> height = const Value.absent(),
    Value<int?> durationMs = const Value.absent(),
    Value<String?> caption = const Value.absent(),
    DateTime? capturedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<Uint8List?> thumbnail = const Value.absent(),
  }) => MediaItem(
    id: id ?? this.id,
    uid: uid ?? this.uid,
    kind: kind ?? this.kind,
    storagePath: storagePath ?? this.storagePath,
    thumbPath: thumbPath.present ? thumbPath.value : this.thumbPath,
    bytes: bytes ?? this.bytes,
    width: width.present ? width.value : this.width,
    height: height.present ? height.value : this.height,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    caption: caption.present ? caption.value : this.caption,
    capturedAt: capturedAt ?? this.capturedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    thumbnail: thumbnail.present ? thumbnail.value : this.thumbnail,
  );
  MediaItem copyWithCompanion(MediaItemsCompanion data) {
    return MediaItem(
      id: data.id.present ? data.id.value : this.id,
      uid: data.uid.present ? data.uid.value : this.uid,
      kind: data.kind.present ? data.kind.value : this.kind,
      storagePath: data.storagePath.present
          ? data.storagePath.value
          : this.storagePath,
      thumbPath: data.thumbPath.present ? data.thumbPath.value : this.thumbPath,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      caption: data.caption.present ? data.caption.value : this.caption,
      capturedAt: data.capturedAt.present
          ? data.capturedAt.value
          : this.capturedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      thumbnail: data.thumbnail.present ? data.thumbnail.value : this.thumbnail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaItem(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('kind: $kind, ')
          ..write('storagePath: $storagePath, ')
          ..write('thumbPath: $thumbPath, ')
          ..write('bytes: $bytes, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('caption: $caption, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('thumbnail: $thumbnail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uid,
    kind,
    storagePath,
    thumbPath,
    bytes,
    width,
    height,
    durationMs,
    caption,
    capturedAt,
    createdAt,
    updatedAt,
    $driftBlobEquality.hash(thumbnail),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItem &&
          other.id == this.id &&
          other.uid == this.uid &&
          other.kind == this.kind &&
          other.storagePath == this.storagePath &&
          other.thumbPath == this.thumbPath &&
          other.bytes == this.bytes &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.caption == this.caption &&
          other.capturedAt == this.capturedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          $driftBlobEquality.equals(other.thumbnail, this.thumbnail));
}

class MediaItemsCompanion extends UpdateCompanion<MediaItem> {
  final Value<String> id;
  final Value<String> uid;
  final Value<String> kind;
  final Value<String> storagePath;
  final Value<String?> thumbPath;
  final Value<int> bytes;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<String?> caption;
  final Value<DateTime> capturedAt;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<Uint8List?> thumbnail;
  final Value<int> rowid;
  const MediaItemsCompanion({
    this.id = const Value.absent(),
    this.uid = const Value.absent(),
    this.kind = const Value.absent(),
    this.storagePath = const Value.absent(),
    this.thumbPath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.caption = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    required String id,
    required String uid,
    required String kind,
    required String storagePath,
    this.thumbPath = const Value.absent(),
    this.bytes = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.caption = const Value.absent(),
    required DateTime capturedAt,
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.thumbnail = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       uid = Value(uid),
       kind = Value(kind),
       storagePath = Value(storagePath),
       capturedAt = Value(capturedAt);
  static Insertable<MediaItem> custom({
    Expression<String>? id,
    Expression<String>? uid,
    Expression<String>? kind,
    Expression<String>? storagePath,
    Expression<String>? thumbPath,
    Expression<int>? bytes,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<String>? caption,
    Expression<DateTime>? capturedAt,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<Uint8List>? thumbnail,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uid != null) 'uid': uid,
      if (kind != null) 'kind': kind,
      if (storagePath != null) 'storage_path': storagePath,
      if (thumbPath != null) 'thumb_path': thumbPath,
      if (bytes != null) 'bytes': bytes,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (caption != null) 'caption': caption,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (thumbnail != null) 'thumbnail': thumbnail,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? uid,
    Value<String>? kind,
    Value<String>? storagePath,
    Value<String?>? thumbPath,
    Value<int>? bytes,
    Value<int?>? width,
    Value<int?>? height,
    Value<int?>? durationMs,
    Value<String?>? caption,
    Value<DateTime>? capturedAt,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<Uint8List?>? thumbnail,
    Value<int>? rowid,
  }) {
    return MediaItemsCompanion(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      kind: kind ?? this.kind,
      storagePath: storagePath ?? this.storagePath,
      thumbPath: thumbPath ?? this.thumbPath,
      bytes: bytes ?? this.bytes,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      caption: caption ?? this.caption,
      capturedAt: capturedAt ?? this.capturedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      thumbnail: thumbnail ?? this.thumbnail,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (uid.present) {
      map['uid'] = Variable<String>(uid.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (storagePath.present) {
      map['storage_path'] = Variable<String>(storagePath.value);
    }
    if (thumbPath.present) {
      map['thumb_path'] = Variable<String>(thumbPath.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (thumbnail.present) {
      map['thumbnail'] = Variable<Uint8List>(thumbnail.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsCompanion(')
          ..write('id: $id, ')
          ..write('uid: $uid, ')
          ..write('kind: $kind, ')
          ..write('storagePath: $storagePath, ')
          ..write('thumbPath: $thumbPath, ')
          ..write('bytes: $bytes, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('caption: $caption, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('thumbnail: $thumbnail, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PeriodEntriesTable periodEntries = $PeriodEntriesTable(this);
  late final $DailyLogsTable dailyLogs = $DailyLogsTable(this);
  late final $RemindersTable reminders = $RemindersTable(this);
  late final $MedicationsTable medications = $MedicationsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SyncTombstonesTable syncTombstones = $SyncTombstonesTable(this);
  late final $MediaItemsTable mediaItems = $MediaItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    periodEntries,
    dailyLogs,
    reminders,
    medications,
    appSettings,
    syncTombstones,
    mediaItems,
  ];
}

typedef $$PeriodEntriesTableCreateCompanionBuilder =
    PeriodEntriesCompanion Function({
      Value<int> id,
      required DateTime startDate,
      Value<DateTime?> endDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$PeriodEntriesTableUpdateCompanionBuilder =
    PeriodEntriesCompanion Function({
      Value<int> id,
      Value<DateTime> startDate,
      Value<DateTime?> endDate,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$PeriodEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PeriodEntriesTable> {
  $$PeriodEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeriodEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PeriodEntriesTable> {
  $$PeriodEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startDate => $composableBuilder(
    column: $table.startDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endDate => $composableBuilder(
    column: $table.endDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeriodEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeriodEntriesTable> {
  $$PeriodEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startDate =>
      $composableBuilder(column: $table.startDate, builder: (column) => column);

  GeneratedColumn<DateTime> get endDate =>
      $composableBuilder(column: $table.endDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PeriodEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeriodEntriesTable,
          PeriodEntry,
          $$PeriodEntriesTableFilterComposer,
          $$PeriodEntriesTableOrderingComposer,
          $$PeriodEntriesTableAnnotationComposer,
          $$PeriodEntriesTableCreateCompanionBuilder,
          $$PeriodEntriesTableUpdateCompanionBuilder,
          (
            PeriodEntry,
            BaseReferences<_$AppDatabase, $PeriodEntriesTable, PeriodEntry>,
          ),
          PeriodEntry,
          PrefetchHooks Function()
        > {
  $$PeriodEntriesTableTableManager(_$AppDatabase db, $PeriodEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeriodEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeriodEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeriodEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> startDate = const Value.absent(),
                Value<DateTime?> endDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PeriodEntriesCompanion(
                id: id,
                startDate: startDate,
                endDate: endDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime startDate,
                Value<DateTime?> endDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => PeriodEntriesCompanion.insert(
                id: id,
                startDate: startDate,
                endDate: endDate,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeriodEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeriodEntriesTable,
      PeriodEntry,
      $$PeriodEntriesTableFilterComposer,
      $$PeriodEntriesTableOrderingComposer,
      $$PeriodEntriesTableAnnotationComposer,
      $$PeriodEntriesTableCreateCompanionBuilder,
      $$PeriodEntriesTableUpdateCompanionBuilder,
      (
        PeriodEntry,
        BaseReferences<_$AppDatabase, $PeriodEntriesTable, PeriodEntry>,
      ),
      PeriodEntry,
      PrefetchHooks Function()
    >;
typedef $$DailyLogsTableCreateCompanionBuilder =
    DailyLogsCompanion Function({
      Value<int> id,
      required DateTime date,
      Value<FlowIntensity?> flow,
      Value<String> symptoms,
      Value<String?> mood,
      Value<String?> notes,
      Value<double?> bbt,
      Value<String?> opk,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });
typedef $$DailyLogsTableUpdateCompanionBuilder =
    DailyLogsCompanion Function({
      Value<int> id,
      Value<DateTime> date,
      Value<FlowIntensity?> flow,
      Value<String> symptoms,
      Value<String?> mood,
      Value<String?> notes,
      Value<double?> bbt,
      Value<String?> opk,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$DailyLogsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyLogsTable> {
  $$DailyLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<FlowIntensity?, FlowIntensity, int> get flow =>
      $composableBuilder(
        column: $table.flow,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get symptoms => $composableBuilder(
    column: $table.symptoms,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get bbt => $composableBuilder(
    column: $table.bbt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get opk => $composableBuilder(
    column: $table.opk,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyLogsTable> {
  $$DailyLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flow => $composableBuilder(
    column: $table.flow,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get symptoms => $composableBuilder(
    column: $table.symptoms,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mood => $composableBuilder(
    column: $table.mood,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get bbt => $composableBuilder(
    column: $table.bbt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get opk => $composableBuilder(
    column: $table.opk,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyLogsTable> {
  $$DailyLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumnWithTypeConverter<FlowIntensity?, int> get flow =>
      $composableBuilder(column: $table.flow, builder: (column) => column);

  GeneratedColumn<String> get symptoms =>
      $composableBuilder(column: $table.symptoms, builder: (column) => column);

  GeneratedColumn<String> get mood =>
      $composableBuilder(column: $table.mood, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<double> get bbt =>
      $composableBuilder(column: $table.bbt, builder: (column) => column);

  GeneratedColumn<String> get opk =>
      $composableBuilder(column: $table.opk, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DailyLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyLogsTable,
          DailyLog,
          $$DailyLogsTableFilterComposer,
          $$DailyLogsTableOrderingComposer,
          $$DailyLogsTableAnnotationComposer,
          $$DailyLogsTableCreateCompanionBuilder,
          $$DailyLogsTableUpdateCompanionBuilder,
          (DailyLog, BaseReferences<_$AppDatabase, $DailyLogsTable, DailyLog>),
          DailyLog,
          PrefetchHooks Function()
        > {
  $$DailyLogsTableTableManager(_$AppDatabase db, $DailyLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<FlowIntensity?> flow = const Value.absent(),
                Value<String> symptoms = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<double?> bbt = const Value.absent(),
                Value<String?> opk = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DailyLogsCompanion(
                id: id,
                date: date,
                flow: flow,
                symptoms: symptoms,
                mood: mood,
                notes: notes,
                bbt: bbt,
                opk: opk,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime date,
                Value<FlowIntensity?> flow = const Value.absent(),
                Value<String> symptoms = const Value.absent(),
                Value<String?> mood = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<double?> bbt = const Value.absent(),
                Value<String?> opk = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => DailyLogsCompanion.insert(
                id: id,
                date: date,
                flow: flow,
                symptoms: symptoms,
                mood: mood,
                notes: notes,
                bbt: bbt,
                opk: opk,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DailyLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyLogsTable,
      DailyLog,
      $$DailyLogsTableFilterComposer,
      $$DailyLogsTableOrderingComposer,
      $$DailyLogsTableAnnotationComposer,
      $$DailyLogsTableCreateCompanionBuilder,
      $$DailyLogsTableUpdateCompanionBuilder,
      (DailyLog, BaseReferences<_$AppDatabase, $DailyLogsTable, DailyLog>),
      DailyLog,
      PrefetchHooks Function()
    >;
typedef $$RemindersTableCreateCompanionBuilder =
    RemindersCompanion Function({
      Value<int> id,
      required ReminderType type,
      required int hour,
      required int minute,
      Value<bool> enabled,
      Value<String?> recurrence,
      Value<String?> title,
      Value<String?> payload,
    });
typedef $$RemindersTableUpdateCompanionBuilder =
    RemindersCompanion Function({
      Value<int> id,
      Value<ReminderType> type,
      Value<int> hour,
      Value<int> minute,
      Value<bool> enabled,
      Value<String?> recurrence,
      Value<String?> title,
      Value<String?> payload,
    });

class $$RemindersTableFilterComposer
    extends Composer<_$AppDatabase, $RemindersTable> {
  $$RemindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<ReminderType, ReminderType, int> get type =>
      $composableBuilder(
        column: $table.type,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get hour => $composableBuilder(
    column: $table.hour,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minute => $composableBuilder(
    column: $table.minute,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemindersTableOrderingComposer
    extends Composer<_$AppDatabase, $RemindersTable> {
  $$RemindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hour => $composableBuilder(
    column: $table.hour,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minute => $composableBuilder(
    column: $table.minute,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemindersTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemindersTable> {
  $$RemindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ReminderType, int> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get hour =>
      $composableBuilder(column: $table.hour, builder: (column) => column);

  GeneratedColumn<int> get minute =>
      $composableBuilder(column: $table.minute, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get recurrence => $composableBuilder(
    column: $table.recurrence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$RemindersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemindersTable,
          Reminder,
          $$RemindersTableFilterComposer,
          $$RemindersTableOrderingComposer,
          $$RemindersTableAnnotationComposer,
          $$RemindersTableCreateCompanionBuilder,
          $$RemindersTableUpdateCompanionBuilder,
          (Reminder, BaseReferences<_$AppDatabase, $RemindersTable, Reminder>),
          Reminder,
          PrefetchHooks Function()
        > {
  $$RemindersTableTableManager(_$AppDatabase db, $RemindersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemindersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<ReminderType> type = const Value.absent(),
                Value<int> hour = const Value.absent(),
                Value<int> minute = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String?> recurrence = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> payload = const Value.absent(),
              }) => RemindersCompanion(
                id: id,
                type: type,
                hour: hour,
                minute: minute,
                enabled: enabled,
                recurrence: recurrence,
                title: title,
                payload: payload,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required ReminderType type,
                required int hour,
                required int minute,
                Value<bool> enabled = const Value.absent(),
                Value<String?> recurrence = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<String?> payload = const Value.absent(),
              }) => RemindersCompanion.insert(
                id: id,
                type: type,
                hour: hour,
                minute: minute,
                enabled: enabled,
                recurrence: recurrence,
                title: title,
                payload: payload,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemindersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemindersTable,
      Reminder,
      $$RemindersTableFilterComposer,
      $$RemindersTableOrderingComposer,
      $$RemindersTableAnnotationComposer,
      $$RemindersTableCreateCompanionBuilder,
      $$RemindersTableUpdateCompanionBuilder,
      (Reminder, BaseReferences<_$AppDatabase, $RemindersTable, Reminder>),
      Reminder,
      PrefetchHooks Function()
    >;
typedef $$MedicationsTableCreateCompanionBuilder =
    MedicationsCompanion Function({
      Value<int> id,
      required String name,
      Value<String?> type,
      Value<String?> schedule,
      Value<bool> enabled,
    });
typedef $$MedicationsTableUpdateCompanionBuilder =
    MedicationsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String?> type,
      Value<String?> schedule,
      Value<bool> enabled,
    });

class $$MedicationsTableFilterComposer
    extends Composer<_$AppDatabase, $MedicationsTable> {
  $$MedicationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schedule => $composableBuilder(
    column: $table.schedule,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MedicationsTableOrderingComposer
    extends Composer<_$AppDatabase, $MedicationsTable> {
  $$MedicationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schedule => $composableBuilder(
    column: $table.schedule,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MedicationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MedicationsTable> {
  $$MedicationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get schedule =>
      $composableBuilder(column: $table.schedule, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);
}

class $$MedicationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MedicationsTable,
          Medication,
          $$MedicationsTableFilterComposer,
          $$MedicationsTableOrderingComposer,
          $$MedicationsTableAnnotationComposer,
          $$MedicationsTableCreateCompanionBuilder,
          $$MedicationsTableUpdateCompanionBuilder,
          (
            Medication,
            BaseReferences<_$AppDatabase, $MedicationsTable, Medication>,
          ),
          Medication,
          PrefetchHooks Function()
        > {
  $$MedicationsTableTableManager(_$AppDatabase db, $MedicationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MedicationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MedicationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MedicationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> type = const Value.absent(),
                Value<String?> schedule = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => MedicationsCompanion(
                id: id,
                name: name,
                type: type,
                schedule: schedule,
                enabled: enabled,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<String?> type = const Value.absent(),
                Value<String?> schedule = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
              }) => MedicationsCompanion.insert(
                id: id,
                name: name,
                type: type,
                schedule: schedule,
                enabled: enabled,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MedicationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MedicationsTable,
      Medication,
      $$MedicationsTableFilterComposer,
      $$MedicationsTableOrderingComposer,
      $$MedicationsTableAnnotationComposer,
      $$MedicationsTableCreateCompanionBuilder,
      $$MedicationsTableUpdateCompanionBuilder,
      (
        Medication,
        BaseReferences<_$AppDatabase, $MedicationsTable, Medication>,
      ),
      Medication,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<TrackingMode> mode,
      Value<int> defaultCycleLength,
      Value<int> defaultPeriodLength,
      Value<String> themeMode,
      Value<String> language,
      Value<bool> genderNeutralLanguage,
      Value<bool> appLockEnabled,
      Value<bool> premium,
      Value<bool> onboardingComplete,
      Value<DateTime?> lastBackup,
      Value<DateTime?> pregnancyStartDate,
      Value<String?> trackingCategories,
      Value<String?> weightUnit,
      Value<DateTime?> lastSyncedAt,
      Value<DateTime?> settingsUpdatedAt,
      Value<String?> analysisConsentUid,
      Value<String?> analysisCountDay,
      Value<int?> analysisCountToday,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<int> id,
      Value<TrackingMode> mode,
      Value<int> defaultCycleLength,
      Value<int> defaultPeriodLength,
      Value<String> themeMode,
      Value<String> language,
      Value<bool> genderNeutralLanguage,
      Value<bool> appLockEnabled,
      Value<bool> premium,
      Value<bool> onboardingComplete,
      Value<DateTime?> lastBackup,
      Value<DateTime?> pregnancyStartDate,
      Value<String?> trackingCategories,
      Value<String?> weightUnit,
      Value<DateTime?> lastSyncedAt,
      Value<DateTime?> settingsUpdatedAt,
      Value<String?> analysisConsentUid,
      Value<String?> analysisCountDay,
      Value<int?> analysisCountToday,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TrackingMode, TrackingMode, int> get mode =>
      $composableBuilder(
        column: $table.mode,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get defaultCycleLength => $composableBuilder(
    column: $table.defaultCycleLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get defaultPeriodLength => $composableBuilder(
    column: $table.defaultPeriodLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get genderNeutralLanguage => $composableBuilder(
    column: $table.genderNeutralLanguage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get appLockEnabled => $composableBuilder(
    column: $table.appLockEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get premium => $composableBuilder(
    column: $table.premium,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get onboardingComplete => $composableBuilder(
    column: $table.onboardingComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastBackup => $composableBuilder(
    column: $table.lastBackup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pregnancyStartDate => $composableBuilder(
    column: $table.pregnancyStartDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trackingCategories => $composableBuilder(
    column: $table.trackingCategories,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get weightUnit => $composableBuilder(
    column: $table.weightUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get settingsUpdatedAt => $composableBuilder(
    column: $table.settingsUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get analysisConsentUid => $composableBuilder(
    column: $table.analysisConsentUid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get analysisCountDay => $composableBuilder(
    column: $table.analysisCountDay,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get analysisCountToday => $composableBuilder(
    column: $table.analysisCountToday,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultCycleLength => $composableBuilder(
    column: $table.defaultCycleLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get defaultPeriodLength => $composableBuilder(
    column: $table.defaultPeriodLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get themeMode => $composableBuilder(
    column: $table.themeMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get genderNeutralLanguage => $composableBuilder(
    column: $table.genderNeutralLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get appLockEnabled => $composableBuilder(
    column: $table.appLockEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get premium => $composableBuilder(
    column: $table.premium,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get onboardingComplete => $composableBuilder(
    column: $table.onboardingComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastBackup => $composableBuilder(
    column: $table.lastBackup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pregnancyStartDate => $composableBuilder(
    column: $table.pregnancyStartDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trackingCategories => $composableBuilder(
    column: $table.trackingCategories,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get weightUnit => $composableBuilder(
    column: $table.weightUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get settingsUpdatedAt => $composableBuilder(
    column: $table.settingsUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get analysisConsentUid => $composableBuilder(
    column: $table.analysisConsentUid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get analysisCountDay => $composableBuilder(
    column: $table.analysisCountDay,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get analysisCountToday => $composableBuilder(
    column: $table.analysisCountToday,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TrackingMode, int> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get defaultCycleLength => $composableBuilder(
    column: $table.defaultCycleLength,
    builder: (column) => column,
  );

  GeneratedColumn<int> get defaultPeriodLength => $composableBuilder(
    column: $table.defaultPeriodLength,
    builder: (column) => column,
  );

  GeneratedColumn<String> get themeMode =>
      $composableBuilder(column: $table.themeMode, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<bool> get genderNeutralLanguage => $composableBuilder(
    column: $table.genderNeutralLanguage,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get appLockEnabled => $composableBuilder(
    column: $table.appLockEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get premium =>
      $composableBuilder(column: $table.premium, builder: (column) => column);

  GeneratedColumn<bool> get onboardingComplete => $composableBuilder(
    column: $table.onboardingComplete,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastBackup => $composableBuilder(
    column: $table.lastBackup,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pregnancyStartDate => $composableBuilder(
    column: $table.pregnancyStartDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trackingCategories => $composableBuilder(
    column: $table.trackingCategories,
    builder: (column) => column,
  );

  GeneratedColumn<String> get weightUnit => $composableBuilder(
    column: $table.weightUnit,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get settingsUpdatedAt => $composableBuilder(
    column: $table.settingsUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get analysisConsentUid => $composableBuilder(
    column: $table.analysisConsentUid,
    builder: (column) => column,
  );

  GeneratedColumn<String> get analysisCountDay => $composableBuilder(
    column: $table.analysisCountDay,
    builder: (column) => column,
  );

  GeneratedColumn<int> get analysisCountToday => $composableBuilder(
    column: $table.analysisCountToday,
    builder: (column) => column,
  );
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<TrackingMode> mode = const Value.absent(),
                Value<int> defaultCycleLength = const Value.absent(),
                Value<int> defaultPeriodLength = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<bool> genderNeutralLanguage = const Value.absent(),
                Value<bool> appLockEnabled = const Value.absent(),
                Value<bool> premium = const Value.absent(),
                Value<bool> onboardingComplete = const Value.absent(),
                Value<DateTime?> lastBackup = const Value.absent(),
                Value<DateTime?> pregnancyStartDate = const Value.absent(),
                Value<String?> trackingCategories = const Value.absent(),
                Value<String?> weightUnit = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<DateTime?> settingsUpdatedAt = const Value.absent(),
                Value<String?> analysisConsentUid = const Value.absent(),
                Value<String?> analysisCountDay = const Value.absent(),
                Value<int?> analysisCountToday = const Value.absent(),
              }) => AppSettingsCompanion(
                id: id,
                mode: mode,
                defaultCycleLength: defaultCycleLength,
                defaultPeriodLength: defaultPeriodLength,
                themeMode: themeMode,
                language: language,
                genderNeutralLanguage: genderNeutralLanguage,
                appLockEnabled: appLockEnabled,
                premium: premium,
                onboardingComplete: onboardingComplete,
                lastBackup: lastBackup,
                pregnancyStartDate: pregnancyStartDate,
                trackingCategories: trackingCategories,
                weightUnit: weightUnit,
                lastSyncedAt: lastSyncedAt,
                settingsUpdatedAt: settingsUpdatedAt,
                analysisConsentUid: analysisConsentUid,
                analysisCountDay: analysisCountDay,
                analysisCountToday: analysisCountToday,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<TrackingMode> mode = const Value.absent(),
                Value<int> defaultCycleLength = const Value.absent(),
                Value<int> defaultPeriodLength = const Value.absent(),
                Value<String> themeMode = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<bool> genderNeutralLanguage = const Value.absent(),
                Value<bool> appLockEnabled = const Value.absent(),
                Value<bool> premium = const Value.absent(),
                Value<bool> onboardingComplete = const Value.absent(),
                Value<DateTime?> lastBackup = const Value.absent(),
                Value<DateTime?> pregnancyStartDate = const Value.absent(),
                Value<String?> trackingCategories = const Value.absent(),
                Value<String?> weightUnit = const Value.absent(),
                Value<DateTime?> lastSyncedAt = const Value.absent(),
                Value<DateTime?> settingsUpdatedAt = const Value.absent(),
                Value<String?> analysisConsentUid = const Value.absent(),
                Value<String?> analysisCountDay = const Value.absent(),
                Value<int?> analysisCountToday = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                id: id,
                mode: mode,
                defaultCycleLength: defaultCycleLength,
                defaultPeriodLength: defaultPeriodLength,
                themeMode: themeMode,
                language: language,
                genderNeutralLanguage: genderNeutralLanguage,
                appLockEnabled: appLockEnabled,
                premium: premium,
                onboardingComplete: onboardingComplete,
                lastBackup: lastBackup,
                pregnancyStartDate: pregnancyStartDate,
                trackingCategories: trackingCategories,
                weightUnit: weightUnit,
                lastSyncedAt: lastSyncedAt,
                settingsUpdatedAt: settingsUpdatedAt,
                analysisConsentUid: analysisConsentUid,
                analysisCountDay: analysisCountDay,
                analysisCountToday: analysisCountToday,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$SyncTombstonesTableCreateCompanionBuilder =
    SyncTombstonesCompanion Function({
      Value<int> id,
      required DateTime date,
      Value<DateTime> deletedAt,
    });
typedef $$SyncTombstonesTableUpdateCompanionBuilder =
    SyncTombstonesCompanion Function({
      Value<int> id,
      Value<DateTime> date,
      Value<DateTime> deletedAt,
    });

class $$SyncTombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncTombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncTombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncTombstonesTable> {
  $$SyncTombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$SyncTombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncTombstonesTable,
          SyncTombstone,
          $$SyncTombstonesTableFilterComposer,
          $$SyncTombstonesTableOrderingComposer,
          $$SyncTombstonesTableAnnotationComposer,
          $$SyncTombstonesTableCreateCompanionBuilder,
          $$SyncTombstonesTableUpdateCompanionBuilder,
          (
            SyncTombstone,
            BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
          ),
          SyncTombstone,
          PrefetchHooks Function()
        > {
  $$SyncTombstonesTableTableManager(
    _$AppDatabase db,
    $SyncTombstonesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncTombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncTombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncTombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
              }) => SyncTombstonesCompanion(
                id: id,
                date: date,
                deletedAt: deletedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime date,
                Value<DateTime> deletedAt = const Value.absent(),
              }) => SyncTombstonesCompanion.insert(
                id: id,
                date: date,
                deletedAt: deletedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncTombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncTombstonesTable,
      SyncTombstone,
      $$SyncTombstonesTableFilterComposer,
      $$SyncTombstonesTableOrderingComposer,
      $$SyncTombstonesTableAnnotationComposer,
      $$SyncTombstonesTableCreateCompanionBuilder,
      $$SyncTombstonesTableUpdateCompanionBuilder,
      (
        SyncTombstone,
        BaseReferences<_$AppDatabase, $SyncTombstonesTable, SyncTombstone>,
      ),
      SyncTombstone,
      PrefetchHooks Function()
    >;
typedef $$MediaItemsTableCreateCompanionBuilder =
    MediaItemsCompanion Function({
      required String id,
      required String uid,
      required String kind,
      required String storagePath,
      Value<String?> thumbPath,
      Value<int> bytes,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String?> caption,
      required DateTime capturedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<Uint8List?> thumbnail,
      Value<int> rowid,
    });
typedef $$MediaItemsTableUpdateCompanionBuilder =
    MediaItemsCompanion Function({
      Value<String> id,
      Value<String> uid,
      Value<String> kind,
      Value<String> storagePath,
      Value<String?> thumbPath,
      Value<int> bytes,
      Value<int?> width,
      Value<int?> height,
      Value<int?> durationMs,
      Value<String?> caption,
      Value<DateTime> capturedAt,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<Uint8List?> thumbnail,
      Value<int> rowid,
    });

class $$MediaItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableFilterComposer({
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

  ColumnFilters<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get thumbPath => $composableBuilder(
    column: $table.thumbPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableOrderingComposer({
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

  ColumnOrderings<String> get uid => $composableBuilder(
    column: $table.uid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get thumbPath => $composableBuilder(
    column: $table.thumbPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get height => $composableBuilder(
    column: $table.height,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get thumbnail => $composableBuilder(
    column: $table.thumbnail,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uid =>
      $composableBuilder(column: $table.uid, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get storagePath => $composableBuilder(
    column: $table.storagePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get thumbPath =>
      $composableBuilder(column: $table.thumbPath, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
    column: $table.capturedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<Uint8List> get thumbnail =>
      $composableBuilder(column: $table.thumbnail, builder: (column) => column);
}

class $$MediaItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaItemsTable,
          MediaItem,
          $$MediaItemsTableFilterComposer,
          $$MediaItemsTableOrderingComposer,
          $$MediaItemsTableAnnotationComposer,
          $$MediaItemsTableCreateCompanionBuilder,
          $$MediaItemsTableUpdateCompanionBuilder,
          (
            MediaItem,
            BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItem>,
          ),
          MediaItem,
          PrefetchHooks Function()
        > {
  $$MediaItemsTableTableManager(_$AppDatabase db, $MediaItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> uid = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> storagePath = const Value.absent(),
                Value<String?> thumbPath = const Value.absent(),
                Value<int> bytes = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<DateTime> capturedAt = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<Uint8List?> thumbnail = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaItemsCompanion(
                id: id,
                uid: uid,
                kind: kind,
                storagePath: storagePath,
                thumbPath: thumbPath,
                bytes: bytes,
                width: width,
                height: height,
                durationMs: durationMs,
                caption: caption,
                capturedAt: capturedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                thumbnail: thumbnail,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String uid,
                required String kind,
                required String storagePath,
                Value<String?> thumbPath = const Value.absent(),
                Value<int> bytes = const Value.absent(),
                Value<int?> width = const Value.absent(),
                Value<int?> height = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                required DateTime capturedAt,
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<Uint8List?> thumbnail = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaItemsCompanion.insert(
                id: id,
                uid: uid,
                kind: kind,
                storagePath: storagePath,
                thumbPath: thumbPath,
                bytes: bytes,
                width: width,
                height: height,
                durationMs: durationMs,
                caption: caption,
                capturedAt: capturedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                thumbnail: thumbnail,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaItemsTable,
      MediaItem,
      $$MediaItemsTableFilterComposer,
      $$MediaItemsTableOrderingComposer,
      $$MediaItemsTableAnnotationComposer,
      $$MediaItemsTableCreateCompanionBuilder,
      $$MediaItemsTableUpdateCompanionBuilder,
      (MediaItem, BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItem>),
      MediaItem,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PeriodEntriesTableTableManager get periodEntries =>
      $$PeriodEntriesTableTableManager(_db, _db.periodEntries);
  $$DailyLogsTableTableManager get dailyLogs =>
      $$DailyLogsTableTableManager(_db, _db.dailyLogs);
  $$RemindersTableTableManager get reminders =>
      $$RemindersTableTableManager(_db, _db.reminders);
  $$MedicationsTableTableManager get medications =>
      $$MedicationsTableTableManager(_db, _db.medications);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SyncTombstonesTableTableManager get syncTombstones =>
      $$SyncTombstonesTableTableManager(_db, _db.syncTombstones);
  $$MediaItemsTableTableManager get mediaItems =>
      $$MediaItemsTableTableManager(_db, _db.mediaItems);
}
