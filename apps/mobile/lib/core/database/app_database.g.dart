// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $KeyValueEntriesTable extends KeyValueEntries
    with TableInfo<$KeyValueEntriesTable, KeyValueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyValueEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'key_value_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<KeyValueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
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
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KeyValueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyValueEntry(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $KeyValueEntriesTable createAlias(String alias) {
    return $KeyValueEntriesTable(attachedDatabase, alias);
  }
}

class KeyValueEntry extends DataClass implements Insertable<KeyValueEntry> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const KeyValueEntry({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  KeyValueEntriesCompanion toCompanion(bool nullToAbsent) {
    return KeyValueEntriesCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory KeyValueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeyValueEntry(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  KeyValueEntry copyWith({String? key, String? value, DateTime? updatedAt}) =>
      KeyValueEntry(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  KeyValueEntry copyWithCompanion(KeyValueEntriesCompanion data) {
    return KeyValueEntry(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeyValueEntry(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KeyValueEntry &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class KeyValueEntriesCompanion extends UpdateCompanion<KeyValueEntry> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const KeyValueEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyValueEntriesCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<KeyValueEntry> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyValueEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return KeyValueEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyValueEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedServicesTable extends CachedServices
    with TableInfo<$CachedServicesTable, CachedService> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedServicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _healthMeta = const VerificationMeta('health');
  @override
  late final GeneratedColumn<String> health = GeneratedColumn<String>(
    'health',
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
  static const VerificationMeta _changeSeqMeta = const VerificationMeta(
    'changeSeq',
  );
  @override
  late final GeneratedColumn<int> changeSeq = GeneratedColumn<int>(
    'change_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    name,
    health,
    json,
    changeSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_services';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedService> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('health')) {
      context.handle(
        _healthMeta,
        health.isAcceptableOrUnknown(data['health']!, _healthMeta),
      );
    } else if (isInserting) {
      context.missing(_healthMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('change_seq')) {
      context.handle(
        _changeSeqMeta,
        changeSeq.isAcceptableOrUnknown(data['change_seq']!, _changeSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_changeSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedService map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedService(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      health: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}health'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      changeSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}change_seq'],
      )!,
    );
  }

  @override
  $CachedServicesTable createAlias(String alias) {
    return $CachedServicesTable(attachedDatabase, alias);
  }
}

class CachedService extends DataClass implements Insertable<CachedService> {
  final String id;
  final String orgId;
  final String name;
  final String health;
  final String json;
  final int changeSeq;
  const CachedService({
    required this.id,
    required this.orgId,
    required this.name,
    required this.health,
    required this.json,
    required this.changeSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['name'] = Variable<String>(name);
    map['health'] = Variable<String>(health);
    map['json'] = Variable<String>(json);
    map['change_seq'] = Variable<int>(changeSeq);
    return map;
  }

  CachedServicesCompanion toCompanion(bool nullToAbsent) {
    return CachedServicesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      name: Value(name),
      health: Value(health),
      json: Value(json),
      changeSeq: Value(changeSeq),
    );
  }

  factory CachedService.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedService(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      name: serializer.fromJson<String>(json['name']),
      health: serializer.fromJson<String>(json['health']),
      json: serializer.fromJson<String>(json['json']),
      changeSeq: serializer.fromJson<int>(json['changeSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'name': serializer.toJson<String>(name),
      'health': serializer.toJson<String>(health),
      'json': serializer.toJson<String>(json),
      'changeSeq': serializer.toJson<int>(changeSeq),
    };
  }

  CachedService copyWith({
    String? id,
    String? orgId,
    String? name,
    String? health,
    String? json,
    int? changeSeq,
  }) => CachedService(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    name: name ?? this.name,
    health: health ?? this.health,
    json: json ?? this.json,
    changeSeq: changeSeq ?? this.changeSeq,
  );
  CachedService copyWithCompanion(CachedServicesCompanion data) {
    return CachedService(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      name: data.name.present ? data.name.value : this.name,
      health: data.health.present ? data.health.value : this.health,
      json: data.json.present ? data.json.value : this.json,
      changeSeq: data.changeSeq.present ? data.changeSeq.value : this.changeSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedService(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('name: $name, ')
          ..write('health: $health, ')
          ..write('json: $json, ')
          ..write('changeSeq: $changeSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, orgId, name, health, json, changeSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedService &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.name == this.name &&
          other.health == this.health &&
          other.json == this.json &&
          other.changeSeq == this.changeSeq);
}

class CachedServicesCompanion extends UpdateCompanion<CachedService> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> name;
  final Value<String> health;
  final Value<String> json;
  final Value<int> changeSeq;
  final Value<int> rowid;
  const CachedServicesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.name = const Value.absent(),
    this.health = const Value.absent(),
    this.json = const Value.absent(),
    this.changeSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedServicesCompanion.insert({
    required String id,
    required String orgId,
    required String name,
    required String health,
    required String json,
    required int changeSeq,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       name = Value(name),
       health = Value(health),
       json = Value(json),
       changeSeq = Value(changeSeq);
  static Insertable<CachedService> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? name,
    Expression<String>? health,
    Expression<String>? json,
    Expression<int>? changeSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (name != null) 'name': name,
      if (health != null) 'health': health,
      if (json != null) 'json': json,
      if (changeSeq != null) 'change_seq': changeSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedServicesCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? name,
    Value<String>? health,
    Value<String>? json,
    Value<int>? changeSeq,
    Value<int>? rowid,
  }) {
    return CachedServicesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      name: name ?? this.name,
      health: health ?? this.health,
      json: json ?? this.json,
      changeSeq: changeSeq ?? this.changeSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (health.present) {
      map['health'] = Variable<String>(health.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (changeSeq.present) {
      map['change_seq'] = Variable<int>(changeSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedServicesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('name: $name, ')
          ..write('health: $health, ')
          ..write('json: $json, ')
          ..write('changeSeq: $changeSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedIncidentsTable extends CachedIncidents
    with TableInfo<$CachedIncidentsTable, CachedIncident> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedIncidentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _severityMeta = const VerificationMeta(
    'severity',
  );
  @override
  late final GeneratedColumn<String> severity = GeneratedColumn<String>(
    'severity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serviceIdMeta = const VerificationMeta(
    'serviceId',
  );
  @override
  late final GeneratedColumn<String> serviceId = GeneratedColumn<String>(
    'service_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _assigneeIdMeta = const VerificationMeta(
    'assigneeId',
  );
  @override
  late final GeneratedColumn<String> assigneeId = GeneratedColumn<String>(
    'assignee_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changeSeqMeta = const VerificationMeta(
    'changeSeq',
  );
  @override
  late final GeneratedColumn<int> changeSeq = GeneratedColumn<int>(
    'change_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pendingActionMeta = const VerificationMeta(
    'pendingAction',
  );
  @override
  late final GeneratedColumn<String> pendingAction = GeneratedColumn<String>(
    'pending_action',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    key,
    status,
    severity,
    startedAt,
    serviceId,
    assigneeId,
    json,
    version,
    changeSeq,
    pendingAction,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_incidents';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedIncident> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('severity')) {
      context.handle(
        _severityMeta,
        severity.isAcceptableOrUnknown(data['severity']!, _severityMeta),
      );
    } else if (isInserting) {
      context.missing(_severityMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('service_id')) {
      context.handle(
        _serviceIdMeta,
        serviceId.isAcceptableOrUnknown(data['service_id']!, _serviceIdMeta),
      );
    }
    if (data.containsKey('assignee_id')) {
      context.handle(
        _assigneeIdMeta,
        assigneeId.isAcceptableOrUnknown(data['assignee_id']!, _assigneeIdMeta),
      );
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('change_seq')) {
      context.handle(
        _changeSeqMeta,
        changeSeq.isAcceptableOrUnknown(data['change_seq']!, _changeSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_changeSeqMeta);
    }
    if (data.containsKey('pending_action')) {
      context.handle(
        _pendingActionMeta,
        pendingAction.isAcceptableOrUnknown(
          data['pending_action']!,
          _pendingActionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedIncident map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedIncident(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      severity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}severity'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      serviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_id'],
      ),
      assigneeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}assignee_id'],
      ),
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      changeSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}change_seq'],
      )!,
      pendingAction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_action'],
      ),
    );
  }

  @override
  $CachedIncidentsTable createAlias(String alias) {
    return $CachedIncidentsTable(attachedDatabase, alias);
  }
}

class CachedIncident extends DataClass implements Insertable<CachedIncident> {
  final String id;
  final String orgId;
  final String key;
  final String status;
  final String severity;
  final int startedAt;
  final String? serviceId;
  final String? assigneeId;
  final String json;
  final int version;
  final int changeSeq;

  /// Optimistic local action waiting in the outbox (`acknowledge`, `resolve`, …).
  final String? pendingAction;
  const CachedIncident({
    required this.id,
    required this.orgId,
    required this.key,
    required this.status,
    required this.severity,
    required this.startedAt,
    this.serviceId,
    this.assigneeId,
    required this.json,
    required this.version,
    required this.changeSeq,
    this.pendingAction,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['key'] = Variable<String>(key);
    map['status'] = Variable<String>(status);
    map['severity'] = Variable<String>(severity);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || serviceId != null) {
      map['service_id'] = Variable<String>(serviceId);
    }
    if (!nullToAbsent || assigneeId != null) {
      map['assignee_id'] = Variable<String>(assigneeId);
    }
    map['json'] = Variable<String>(json);
    map['version'] = Variable<int>(version);
    map['change_seq'] = Variable<int>(changeSeq);
    if (!nullToAbsent || pendingAction != null) {
      map['pending_action'] = Variable<String>(pendingAction);
    }
    return map;
  }

  CachedIncidentsCompanion toCompanion(bool nullToAbsent) {
    return CachedIncidentsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      key: Value(key),
      status: Value(status),
      severity: Value(severity),
      startedAt: Value(startedAt),
      serviceId: serviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(serviceId),
      assigneeId: assigneeId == null && nullToAbsent
          ? const Value.absent()
          : Value(assigneeId),
      json: Value(json),
      version: Value(version),
      changeSeq: Value(changeSeq),
      pendingAction: pendingAction == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingAction),
    );
  }

  factory CachedIncident.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedIncident(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      key: serializer.fromJson<String>(json['key']),
      status: serializer.fromJson<String>(json['status']),
      severity: serializer.fromJson<String>(json['severity']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      serviceId: serializer.fromJson<String?>(json['serviceId']),
      assigneeId: serializer.fromJson<String?>(json['assigneeId']),
      json: serializer.fromJson<String>(json['json']),
      version: serializer.fromJson<int>(json['version']),
      changeSeq: serializer.fromJson<int>(json['changeSeq']),
      pendingAction: serializer.fromJson<String?>(json['pendingAction']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'key': serializer.toJson<String>(key),
      'status': serializer.toJson<String>(status),
      'severity': serializer.toJson<String>(severity),
      'startedAt': serializer.toJson<int>(startedAt),
      'serviceId': serializer.toJson<String?>(serviceId),
      'assigneeId': serializer.toJson<String?>(assigneeId),
      'json': serializer.toJson<String>(json),
      'version': serializer.toJson<int>(version),
      'changeSeq': serializer.toJson<int>(changeSeq),
      'pendingAction': serializer.toJson<String?>(pendingAction),
    };
  }

  CachedIncident copyWith({
    String? id,
    String? orgId,
    String? key,
    String? status,
    String? severity,
    int? startedAt,
    Value<String?> serviceId = const Value.absent(),
    Value<String?> assigneeId = const Value.absent(),
    String? json,
    int? version,
    int? changeSeq,
    Value<String?> pendingAction = const Value.absent(),
  }) => CachedIncident(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    key: key ?? this.key,
    status: status ?? this.status,
    severity: severity ?? this.severity,
    startedAt: startedAt ?? this.startedAt,
    serviceId: serviceId.present ? serviceId.value : this.serviceId,
    assigneeId: assigneeId.present ? assigneeId.value : this.assigneeId,
    json: json ?? this.json,
    version: version ?? this.version,
    changeSeq: changeSeq ?? this.changeSeq,
    pendingAction: pendingAction.present
        ? pendingAction.value
        : this.pendingAction,
  );
  CachedIncident copyWithCompanion(CachedIncidentsCompanion data) {
    return CachedIncident(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      key: data.key.present ? data.key.value : this.key,
      status: data.status.present ? data.status.value : this.status,
      severity: data.severity.present ? data.severity.value : this.severity,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      serviceId: data.serviceId.present ? data.serviceId.value : this.serviceId,
      assigneeId: data.assigneeId.present
          ? data.assigneeId.value
          : this.assigneeId,
      json: data.json.present ? data.json.value : this.json,
      version: data.version.present ? data.version.value : this.version,
      changeSeq: data.changeSeq.present ? data.changeSeq.value : this.changeSeq,
      pendingAction: data.pendingAction.present
          ? data.pendingAction.value
          : this.pendingAction,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedIncident(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('key: $key, ')
          ..write('status: $status, ')
          ..write('severity: $severity, ')
          ..write('startedAt: $startedAt, ')
          ..write('serviceId: $serviceId, ')
          ..write('assigneeId: $assigneeId, ')
          ..write('json: $json, ')
          ..write('version: $version, ')
          ..write('changeSeq: $changeSeq, ')
          ..write('pendingAction: $pendingAction')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    key,
    status,
    severity,
    startedAt,
    serviceId,
    assigneeId,
    json,
    version,
    changeSeq,
    pendingAction,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedIncident &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.key == this.key &&
          other.status == this.status &&
          other.severity == this.severity &&
          other.startedAt == this.startedAt &&
          other.serviceId == this.serviceId &&
          other.assigneeId == this.assigneeId &&
          other.json == this.json &&
          other.version == this.version &&
          other.changeSeq == this.changeSeq &&
          other.pendingAction == this.pendingAction);
}

class CachedIncidentsCompanion extends UpdateCompanion<CachedIncident> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> key;
  final Value<String> status;
  final Value<String> severity;
  final Value<int> startedAt;
  final Value<String?> serviceId;
  final Value<String?> assigneeId;
  final Value<String> json;
  final Value<int> version;
  final Value<int> changeSeq;
  final Value<String?> pendingAction;
  final Value<int> rowid;
  const CachedIncidentsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.key = const Value.absent(),
    this.status = const Value.absent(),
    this.severity = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.serviceId = const Value.absent(),
    this.assigneeId = const Value.absent(),
    this.json = const Value.absent(),
    this.version = const Value.absent(),
    this.changeSeq = const Value.absent(),
    this.pendingAction = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedIncidentsCompanion.insert({
    required String id,
    required String orgId,
    required String key,
    required String status,
    required String severity,
    required int startedAt,
    this.serviceId = const Value.absent(),
    this.assigneeId = const Value.absent(),
    required String json,
    required int version,
    required int changeSeq,
    this.pendingAction = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       key = Value(key),
       status = Value(status),
       severity = Value(severity),
       startedAt = Value(startedAt),
       json = Value(json),
       version = Value(version),
       changeSeq = Value(changeSeq);
  static Insertable<CachedIncident> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? key,
    Expression<String>? status,
    Expression<String>? severity,
    Expression<int>? startedAt,
    Expression<String>? serviceId,
    Expression<String>? assigneeId,
    Expression<String>? json,
    Expression<int>? version,
    Expression<int>? changeSeq,
    Expression<String>? pendingAction,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (key != null) 'key': key,
      if (status != null) 'status': status,
      if (severity != null) 'severity': severity,
      if (startedAt != null) 'started_at': startedAt,
      if (serviceId != null) 'service_id': serviceId,
      if (assigneeId != null) 'assignee_id': assigneeId,
      if (json != null) 'json': json,
      if (version != null) 'version': version,
      if (changeSeq != null) 'change_seq': changeSeq,
      if (pendingAction != null) 'pending_action': pendingAction,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedIncidentsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? key,
    Value<String>? status,
    Value<String>? severity,
    Value<int>? startedAt,
    Value<String?>? serviceId,
    Value<String?>? assigneeId,
    Value<String>? json,
    Value<int>? version,
    Value<int>? changeSeq,
    Value<String?>? pendingAction,
    Value<int>? rowid,
  }) {
    return CachedIncidentsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      key: key ?? this.key,
      status: status ?? this.status,
      severity: severity ?? this.severity,
      startedAt: startedAt ?? this.startedAt,
      serviceId: serviceId ?? this.serviceId,
      assigneeId: assigneeId ?? this.assigneeId,
      json: json ?? this.json,
      version: version ?? this.version,
      changeSeq: changeSeq ?? this.changeSeq,
      pendingAction: pendingAction ?? this.pendingAction,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (severity.present) {
      map['severity'] = Variable<String>(severity.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (serviceId.present) {
      map['service_id'] = Variable<String>(serviceId.value);
    }
    if (assigneeId.present) {
      map['assignee_id'] = Variable<String>(assigneeId.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (changeSeq.present) {
      map['change_seq'] = Variable<int>(changeSeq.value);
    }
    if (pendingAction.present) {
      map['pending_action'] = Variable<String>(pendingAction.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedIncidentsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('key: $key, ')
          ..write('status: $status, ')
          ..write('severity: $severity, ')
          ..write('startedAt: $startedAt, ')
          ..write('serviceId: $serviceId, ')
          ..write('assigneeId: $assigneeId, ')
          ..write('json: $json, ')
          ..write('version: $version, ')
          ..write('changeSeq: $changeSeq, ')
          ..write('pendingAction: $pendingAction, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDeploymentsTable extends CachedDeployments
    with TableInfo<$CachedDeploymentsTable, CachedDeployment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDeploymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serviceIdMeta = const VerificationMeta(
    'serviceId',
  );
  @override
  late final GeneratedColumn<String> serviceId = GeneratedColumn<String>(
    'service_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _changeSeqMeta = const VerificationMeta(
    'changeSeq',
  );
  @override
  late final GeneratedColumn<int> changeSeq = GeneratedColumn<int>(
    'change_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    serviceId,
    startedAt,
    json,
    changeSeq,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_deployments';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDeployment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('service_id')) {
      context.handle(
        _serviceIdMeta,
        serviceId.isAcceptableOrUnknown(data['service_id']!, _serviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_serviceIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('change_seq')) {
      context.handle(
        _changeSeqMeta,
        changeSeq.isAcceptableOrUnknown(data['change_seq']!, _changeSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_changeSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CachedDeployment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDeployment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      serviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      changeSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}change_seq'],
      )!,
    );
  }

  @override
  $CachedDeploymentsTable createAlias(String alias) {
    return $CachedDeploymentsTable(attachedDatabase, alias);
  }
}

class CachedDeployment extends DataClass
    implements Insertable<CachedDeployment> {
  final String id;
  final String orgId;
  final String serviceId;
  final int startedAt;
  final String json;
  final int changeSeq;
  const CachedDeployment({
    required this.id,
    required this.orgId,
    required this.serviceId,
    required this.startedAt,
    required this.json,
    required this.changeSeq,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_id'] = Variable<String>(orgId);
    map['service_id'] = Variable<String>(serviceId);
    map['started_at'] = Variable<int>(startedAt);
    map['json'] = Variable<String>(json);
    map['change_seq'] = Variable<int>(changeSeq);
    return map;
  }

  CachedDeploymentsCompanion toCompanion(bool nullToAbsent) {
    return CachedDeploymentsCompanion(
      id: Value(id),
      orgId: Value(orgId),
      serviceId: Value(serviceId),
      startedAt: Value(startedAt),
      json: Value(json),
      changeSeq: Value(changeSeq),
    );
  }

  factory CachedDeployment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDeployment(
      id: serializer.fromJson<String>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      serviceId: serializer.fromJson<String>(json['serviceId']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      json: serializer.fromJson<String>(json['json']),
      changeSeq: serializer.fromJson<int>(json['changeSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgId': serializer.toJson<String>(orgId),
      'serviceId': serializer.toJson<String>(serviceId),
      'startedAt': serializer.toJson<int>(startedAt),
      'json': serializer.toJson<String>(json),
      'changeSeq': serializer.toJson<int>(changeSeq),
    };
  }

  CachedDeployment copyWith({
    String? id,
    String? orgId,
    String? serviceId,
    int? startedAt,
    String? json,
    int? changeSeq,
  }) => CachedDeployment(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    serviceId: serviceId ?? this.serviceId,
    startedAt: startedAt ?? this.startedAt,
    json: json ?? this.json,
    changeSeq: changeSeq ?? this.changeSeq,
  );
  CachedDeployment copyWithCompanion(CachedDeploymentsCompanion data) {
    return CachedDeployment(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      serviceId: data.serviceId.present ? data.serviceId.value : this.serviceId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      json: data.json.present ? data.json.value : this.json,
      changeSeq: data.changeSeq.present ? data.changeSeq.value : this.changeSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDeployment(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('serviceId: $serviceId, ')
          ..write('startedAt: $startedAt, ')
          ..write('json: $json, ')
          ..write('changeSeq: $changeSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, orgId, serviceId, startedAt, json, changeSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDeployment &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.serviceId == this.serviceId &&
          other.startedAt == this.startedAt &&
          other.json == this.json &&
          other.changeSeq == this.changeSeq);
}

class CachedDeploymentsCompanion extends UpdateCompanion<CachedDeployment> {
  final Value<String> id;
  final Value<String> orgId;
  final Value<String> serviceId;
  final Value<int> startedAt;
  final Value<String> json;
  final Value<int> changeSeq;
  final Value<int> rowid;
  const CachedDeploymentsCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.serviceId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.json = const Value.absent(),
    this.changeSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDeploymentsCompanion.insert({
    required String id,
    required String orgId,
    required String serviceId,
    required int startedAt,
    required String json,
    required int changeSeq,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgId = Value(orgId),
       serviceId = Value(serviceId),
       startedAt = Value(startedAt),
       json = Value(json),
       changeSeq = Value(changeSeq);
  static Insertable<CachedDeployment> custom({
    Expression<String>? id,
    Expression<String>? orgId,
    Expression<String>? serviceId,
    Expression<int>? startedAt,
    Expression<String>? json,
    Expression<int>? changeSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (serviceId != null) 'service_id': serviceId,
      if (startedAt != null) 'started_at': startedAt,
      if (json != null) 'json': json,
      if (changeSeq != null) 'change_seq': changeSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDeploymentsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgId,
    Value<String>? serviceId,
    Value<int>? startedAt,
    Value<String>? json,
    Value<int>? changeSeq,
    Value<int>? rowid,
  }) {
    return CachedDeploymentsCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      serviceId: serviceId ?? this.serviceId,
      startedAt: startedAt ?? this.startedAt,
      json: json ?? this.json,
      changeSeq: changeSeq ?? this.changeSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (serviceId.present) {
      map['service_id'] = Variable<String>(serviceId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (changeSeq.present) {
      map['change_seq'] = Variable<int>(changeSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDeploymentsCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('serviceId: $serviceId, ')
          ..write('startedAt: $startedAt, ')
          ..write('json: $json, ')
          ..write('changeSeq: $changeSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncCursorsTable extends SyncCursors
    with TableInfo<$SyncCursorsTable, SyncCursor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collectionMeta = const VerificationMeta(
    'collection',
  );
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
    'collection',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [orgId, collection, cursor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncCursor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('collection')) {
      context.handle(
        _collectionMeta,
        collection.isAcceptableOrUnknown(data['collection']!, _collectionMeta),
      );
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('cursor')) {
      context.handle(
        _cursorMeta,
        cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta),
      );
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {orgId, collection};
  @override
  SyncCursor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncCursor(
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      collection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection'],
      )!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor'],
      )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursor extends DataClass implements Insertable<SyncCursor> {
  final String orgId;
  final String collection;
  final int cursor;
  const SyncCursor({
    required this.orgId,
    required this.collection,
    required this.cursor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['org_id'] = Variable<String>(orgId);
    map['collection'] = Variable<String>(collection);
    map['cursor'] = Variable<int>(cursor);
    return map;
  }

  SyncCursorsCompanion toCompanion(bool nullToAbsent) {
    return SyncCursorsCompanion(
      orgId: Value(orgId),
      collection: Value(collection),
      cursor: Value(cursor),
    );
  }

  factory SyncCursor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncCursor(
      orgId: serializer.fromJson<String>(json['orgId']),
      collection: serializer.fromJson<String>(json['collection']),
      cursor: serializer.fromJson<int>(json['cursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'orgId': serializer.toJson<String>(orgId),
      'collection': serializer.toJson<String>(collection),
      'cursor': serializer.toJson<int>(cursor),
    };
  }

  SyncCursor copyWith({String? orgId, String? collection, int? cursor}) =>
      SyncCursor(
        orgId: orgId ?? this.orgId,
        collection: collection ?? this.collection,
        cursor: cursor ?? this.cursor,
      );
  SyncCursor copyWithCompanion(SyncCursorsCompanion data) {
    return SyncCursor(
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      collection: data.collection.present
          ? data.collection.value
          : this.collection,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursor(')
          ..write('orgId: $orgId, ')
          ..write('collection: $collection, ')
          ..write('cursor: $cursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(orgId, collection, cursor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncCursor &&
          other.orgId == this.orgId &&
          other.collection == this.collection &&
          other.cursor == this.cursor);
}

class SyncCursorsCompanion extends UpdateCompanion<SyncCursor> {
  final Value<String> orgId;
  final Value<String> collection;
  final Value<int> cursor;
  final Value<int> rowid;
  const SyncCursorsCompanion({
    this.orgId = const Value.absent(),
    this.collection = const Value.absent(),
    this.cursor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String orgId,
    required String collection,
    required int cursor,
    this.rowid = const Value.absent(),
  }) : orgId = Value(orgId),
       collection = Value(collection),
       cursor = Value(cursor);
  static Insertable<SyncCursor> custom({
    Expression<String>? orgId,
    Expression<String>? collection,
    Expression<int>? cursor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (orgId != null) 'org_id': orgId,
      if (collection != null) 'collection': collection,
      if (cursor != null) 'cursor': cursor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncCursorsCompanion copyWith({
    Value<String>? orgId,
    Value<String>? collection,
    Value<int>? cursor,
    Value<int>? rowid,
  }) {
    return SyncCursorsCompanion(
      orgId: orgId ?? this.orgId,
      collection: collection ?? this.collection,
      cursor: cursor ?? this.cursor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('orgId: $orgId, ')
          ..write('collection: $collection, ')
          ..write('cursor: $cursor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxEntriesTable extends OutboxEntries
    with TableInfo<$OutboxEntriesTable, OutboxEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _orgIdMeta = const VerificationMeta('orgId');
  @override
  late final GeneratedColumn<String> orgId = GeneratedColumn<String>(
    'org_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _incidentIdMeta = const VerificationMeta(
    'incidentId',
  );
  @override
  late final GeneratedColumn<String> incidentId = GeneratedColumn<String>(
    'incident_id',
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
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
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
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotencyKeyMeta = const VerificationMeta(
    'idempotencyKey',
  );
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientIdMeta = const VerificationMeta(
    'clientId',
  );
  @override
  late final GeneratedColumn<String> clientId = GeneratedColumn<String>(
    'client_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgId,
    incidentId,
    kind,
    action,
    path,
    body,
    idempotencyKey,
    clientId,
    baseVersion,
    attempts,
    nextAttemptAt,
    state,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('org_id')) {
      context.handle(
        _orgIdMeta,
        orgId.isAcceptableOrUnknown(data['org_id']!, _orgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_orgIdMeta);
    }
    if (data.containsKey('incident_id')) {
      context.handle(
        _incidentIdMeta,
        incidentId.isAcceptableOrUnknown(data['incident_id']!, _incidentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_incidentIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotencyKeyMeta,
        idempotencyKey.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotencyKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('client_id')) {
      context.handle(
        _clientIdMeta,
        clientId.isAcceptableOrUnknown(data['client_id']!, _clientIdMeta),
      );
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      orgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_id'],
      )!,
      incidentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}incident_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      idempotencyKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      )!,
      clientId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_id'],
      ),
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      ),
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxEntriesTable createAlias(String alias) {
    return $OutboxEntriesTable(attachedDatabase, alias);
  }
}

class OutboxEntry extends DataClass implements Insertable<OutboxEntry> {
  final int id;
  final String orgId;
  final String incidentId;
  final String kind;
  final String action;
  final String path;
  final String body;
  final String idempotencyKey;
  final String? clientId;
  final int? baseVersion;
  final int attempts;
  final int nextAttemptAt;
  final String state;
  final String? lastError;
  final int createdAt;
  const OutboxEntry({
    required this.id,
    required this.orgId,
    required this.incidentId,
    required this.kind,
    required this.action,
    required this.path,
    required this.body,
    required this.idempotencyKey,
    this.clientId,
    this.baseVersion,
    required this.attempts,
    required this.nextAttemptAt,
    required this.state,
    this.lastError,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['org_id'] = Variable<String>(orgId);
    map['incident_id'] = Variable<String>(incidentId);
    map['kind'] = Variable<String>(kind);
    map['action'] = Variable<String>(action);
    map['path'] = Variable<String>(path);
    map['body'] = Variable<String>(body);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    if (!nullToAbsent || clientId != null) {
      map['client_id'] = Variable<String>(clientId);
    }
    if (!nullToAbsent || baseVersion != null) {
      map['base_version'] = Variable<int>(baseVersion);
    }
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  OutboxEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboxEntriesCompanion(
      id: Value(id),
      orgId: Value(orgId),
      incidentId: Value(incidentId),
      kind: Value(kind),
      action: Value(action),
      path: Value(path),
      body: Value(body),
      idempotencyKey: Value(idempotencyKey),
      clientId: clientId == null && nullToAbsent
          ? const Value.absent()
          : Value(clientId),
      baseVersion: baseVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseVersion),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      state: Value(state),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxEntry(
      id: serializer.fromJson<int>(json['id']),
      orgId: serializer.fromJson<String>(json['orgId']),
      incidentId: serializer.fromJson<String>(json['incidentId']),
      kind: serializer.fromJson<String>(json['kind']),
      action: serializer.fromJson<String>(json['action']),
      path: serializer.fromJson<String>(json['path']),
      body: serializer.fromJson<String>(json['body']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      clientId: serializer.fromJson<String?>(json['clientId']),
      baseVersion: serializer.fromJson<int?>(json['baseVersion']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int>(json['nextAttemptAt']),
      state: serializer.fromJson<String>(json['state']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'orgId': serializer.toJson<String>(orgId),
      'incidentId': serializer.toJson<String>(incidentId),
      'kind': serializer.toJson<String>(kind),
      'action': serializer.toJson<String>(action),
      'path': serializer.toJson<String>(path),
      'body': serializer.toJson<String>(body),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'clientId': serializer.toJson<String?>(clientId),
      'baseVersion': serializer.toJson<int?>(baseVersion),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<int>(nextAttemptAt),
      'state': serializer.toJson<String>(state),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  OutboxEntry copyWith({
    int? id,
    String? orgId,
    String? incidentId,
    String? kind,
    String? action,
    String? path,
    String? body,
    String? idempotencyKey,
    Value<String?> clientId = const Value.absent(),
    Value<int?> baseVersion = const Value.absent(),
    int? attempts,
    int? nextAttemptAt,
    String? state,
    Value<String?> lastError = const Value.absent(),
    int? createdAt,
  }) => OutboxEntry(
    id: id ?? this.id,
    orgId: orgId ?? this.orgId,
    incidentId: incidentId ?? this.incidentId,
    kind: kind ?? this.kind,
    action: action ?? this.action,
    path: path ?? this.path,
    body: body ?? this.body,
    idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    clientId: clientId.present ? clientId.value : this.clientId,
    baseVersion: baseVersion.present ? baseVersion.value : this.baseVersion,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    state: state ?? this.state,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxEntry copyWithCompanion(OutboxEntriesCompanion data) {
    return OutboxEntry(
      id: data.id.present ? data.id.value : this.id,
      orgId: data.orgId.present ? data.orgId.value : this.orgId,
      incidentId: data.incidentId.present
          ? data.incidentId.value
          : this.incidentId,
      kind: data.kind.present ? data.kind.value : this.kind,
      action: data.action.present ? data.action.value : this.action,
      path: data.path.present ? data.path.value : this.path,
      body: data.body.present ? data.body.value : this.body,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      clientId: data.clientId.present ? data.clientId.value : this.clientId,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      state: data.state.present ? data.state.value : this.state,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntry(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('incidentId: $incidentId, ')
          ..write('kind: $kind, ')
          ..write('action: $action, ')
          ..write('path: $path, ')
          ..write('body: $body, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('clientId: $clientId, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgId,
    incidentId,
    kind,
    action,
    path,
    body,
    idempotencyKey,
    clientId,
    baseVersion,
    attempts,
    nextAttemptAt,
    state,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxEntry &&
          other.id == this.id &&
          other.orgId == this.orgId &&
          other.incidentId == this.incidentId &&
          other.kind == this.kind &&
          other.action == this.action &&
          other.path == this.path &&
          other.body == this.body &&
          other.idempotencyKey == this.idempotencyKey &&
          other.clientId == this.clientId &&
          other.baseVersion == this.baseVersion &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.state == this.state &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class OutboxEntriesCompanion extends UpdateCompanion<OutboxEntry> {
  final Value<int> id;
  final Value<String> orgId;
  final Value<String> incidentId;
  final Value<String> kind;
  final Value<String> action;
  final Value<String> path;
  final Value<String> body;
  final Value<String> idempotencyKey;
  final Value<String?> clientId;
  final Value<int?> baseVersion;
  final Value<int> attempts;
  final Value<int> nextAttemptAt;
  final Value<String> state;
  final Value<String?> lastError;
  final Value<int> createdAt;
  const OutboxEntriesCompanion({
    this.id = const Value.absent(),
    this.orgId = const Value.absent(),
    this.incidentId = const Value.absent(),
    this.kind = const Value.absent(),
    this.action = const Value.absent(),
    this.path = const Value.absent(),
    this.body = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.clientId = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  OutboxEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String orgId,
    required String incidentId,
    required String kind,
    required String action,
    required String path,
    required String body,
    required String idempotencyKey,
    this.clientId = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.state = const Value.absent(),
    this.lastError = const Value.absent(),
    required int createdAt,
  }) : orgId = Value(orgId),
       incidentId = Value(incidentId),
       kind = Value(kind),
       action = Value(action),
       path = Value(path),
       body = Value(body),
       idempotencyKey = Value(idempotencyKey),
       createdAt = Value(createdAt);
  static Insertable<OutboxEntry> custom({
    Expression<int>? id,
    Expression<String>? orgId,
    Expression<String>? incidentId,
    Expression<String>? kind,
    Expression<String>? action,
    Expression<String>? path,
    Expression<String>? body,
    Expression<String>? idempotencyKey,
    Expression<String>? clientId,
    Expression<int>? baseVersion,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<String>? state,
    Expression<String>? lastError,
    Expression<int>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgId != null) 'org_id': orgId,
      if (incidentId != null) 'incident_id': incidentId,
      if (kind != null) 'kind': kind,
      if (action != null) 'action': action,
      if (path != null) 'path': path,
      if (body != null) 'body': body,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (clientId != null) 'client_id': clientId,
      if (baseVersion != null) 'base_version': baseVersion,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (state != null) 'state': state,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  OutboxEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? orgId,
    Value<String>? incidentId,
    Value<String>? kind,
    Value<String>? action,
    Value<String>? path,
    Value<String>? body,
    Value<String>? idempotencyKey,
    Value<String?>? clientId,
    Value<int?>? baseVersion,
    Value<int>? attempts,
    Value<int>? nextAttemptAt,
    Value<String>? state,
    Value<String?>? lastError,
    Value<int>? createdAt,
  }) {
    return OutboxEntriesCompanion(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      incidentId: incidentId ?? this.incidentId,
      kind: kind ?? this.kind,
      action: action ?? this.action,
      path: path ?? this.path,
      body: body ?? this.body,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      clientId: clientId ?? this.clientId,
      baseVersion: baseVersion ?? this.baseVersion,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      state: state ?? this.state,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (orgId.present) {
      map['org_id'] = Variable<String>(orgId.value);
    }
    if (incidentId.present) {
      map['incident_id'] = Variable<String>(incidentId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (clientId.present) {
      map['client_id'] = Variable<String>(clientId.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxEntriesCompanion(')
          ..write('id: $id, ')
          ..write('orgId: $orgId, ')
          ..write('incidentId: $incidentId, ')
          ..write('kind: $kind, ')
          ..write('action: $action, ')
          ..write('path: $path, ')
          ..write('body: $body, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('clientId: $clientId, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('state: $state, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $KeyValueEntriesTable keyValueEntries = $KeyValueEntriesTable(
    this,
  );
  late final $CachedServicesTable cachedServices = $CachedServicesTable(this);
  late final $CachedIncidentsTable cachedIncidents = $CachedIncidentsTable(
    this,
  );
  late final $CachedDeploymentsTable cachedDeployments =
      $CachedDeploymentsTable(this);
  late final $SyncCursorsTable syncCursors = $SyncCursorsTable(this);
  late final $OutboxEntriesTable outboxEntries = $OutboxEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    keyValueEntries,
    cachedServices,
    cachedIncidents,
    cachedDeployments,
    syncCursors,
    outboxEntries,
  ];
}

typedef $$KeyValueEntriesTableCreateCompanionBuilder =
    KeyValueEntriesCompanion Function({
      required String key,
      required String value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$KeyValueEntriesTableUpdateCompanionBuilder =
    KeyValueEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$KeyValueEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $KeyValueEntriesTable> {
  $$KeyValueEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KeyValueEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $KeyValueEntriesTable> {
  $$KeyValueEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KeyValueEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $KeyValueEntriesTable> {
  $$KeyValueEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$KeyValueEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KeyValueEntriesTable,
          KeyValueEntry,
          $$KeyValueEntriesTableFilterComposer,
          $$KeyValueEntriesTableOrderingComposer,
          $$KeyValueEntriesTableAnnotationComposer,
          $$KeyValueEntriesTableCreateCompanionBuilder,
          $$KeyValueEntriesTableUpdateCompanionBuilder,
          (
            KeyValueEntry,
            BaseReferences<_$AppDatabase, $KeyValueEntriesTable, KeyValueEntry>,
          ),
          KeyValueEntry,
          PrefetchHooks Function()
        > {
  $$KeyValueEntriesTableTableManager(
    _$AppDatabase db,
    $KeyValueEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KeyValueEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KeyValueEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KeyValueEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeyValueEntriesCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KeyValueEntriesCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeyValueEntriesTable, KeyValueEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $KeyValueEntriesTable,
                    KeyValueEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyValueEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KeyValueEntriesTable,
      KeyValueEntry,
      $$KeyValueEntriesTableFilterComposer,
      $$KeyValueEntriesTableOrderingComposer,
      $$KeyValueEntriesTableAnnotationComposer,
      $$KeyValueEntriesTableCreateCompanionBuilder,
      $$KeyValueEntriesTableUpdateCompanionBuilder,
      (
        KeyValueEntry,
        BaseReferences<_$AppDatabase, $KeyValueEntriesTable, KeyValueEntry>,
      ),
      KeyValueEntry,
      PrefetchHooks Function()
    >;
typedef $$CachedServicesTableCreateCompanionBuilder =
    CachedServicesCompanion Function({
      required String id,
      required String orgId,
      required String name,
      required String health,
      required String json,
      required int changeSeq,
      Value<int> rowid,
    });
typedef $$CachedServicesTableUpdateCompanionBuilder =
    CachedServicesCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> name,
      Value<String> health,
      Value<String> json,
      Value<int> changeSeq,
      Value<int> rowid,
    });

class $$CachedServicesTableFilterComposer
    extends Composer<_$AppDatabase, $CachedServicesTable> {
  $$CachedServicesTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changeSeq => $composableBuilder(
    column: $table.changeSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedServicesTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedServicesTable> {
  $$CachedServicesTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get health => $composableBuilder(
    column: $table.health,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changeSeq => $composableBuilder(
    column: $table.changeSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedServicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedServicesTable> {
  $$CachedServicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get health =>
      $composableBuilder(column: $table.health, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get changeSeq =>
      $composableBuilder(column: $table.changeSeq, builder: (column) => column);
}

class $$CachedServicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedServicesTable,
          CachedService,
          $$CachedServicesTableFilterComposer,
          $$CachedServicesTableOrderingComposer,
          $$CachedServicesTableAnnotationComposer,
          $$CachedServicesTableCreateCompanionBuilder,
          $$CachedServicesTableUpdateCompanionBuilder,
          (
            CachedService,
            BaseReferences<_$AppDatabase, $CachedServicesTable, CachedService>,
          ),
          CachedService,
          PrefetchHooks Function()
        > {
  $$CachedServicesTableTableManager(
    _$AppDatabase db,
    $CachedServicesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedServicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedServicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedServicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> health = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> changeSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedServicesCompanion(
                id: id,
                orgId: orgId,
                name: name,
                health: health,
                json: json,
                changeSeq: changeSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String name,
                required String health,
                required String json,
                required int changeSeq,
                Value<int> rowid = const Value.absent(),
              }) => CachedServicesCompanion.insert(
                id: id,
                orgId: orgId,
                name: name,
                health: health,
                json: json,
                changeSeq: changeSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedServicesTable, CachedService>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedServicesTable,
                    CachedService
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedServicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedServicesTable,
      CachedService,
      $$CachedServicesTableFilterComposer,
      $$CachedServicesTableOrderingComposer,
      $$CachedServicesTableAnnotationComposer,
      $$CachedServicesTableCreateCompanionBuilder,
      $$CachedServicesTableUpdateCompanionBuilder,
      (
        CachedService,
        BaseReferences<_$AppDatabase, $CachedServicesTable, CachedService>,
      ),
      CachedService,
      PrefetchHooks Function()
    >;
typedef $$CachedIncidentsTableCreateCompanionBuilder =
    CachedIncidentsCompanion Function({
      required String id,
      required String orgId,
      required String key,
      required String status,
      required String severity,
      required int startedAt,
      Value<String?> serviceId,
      Value<String?> assigneeId,
      required String json,
      required int version,
      required int changeSeq,
      Value<String?> pendingAction,
      Value<int> rowid,
    });
typedef $$CachedIncidentsTableUpdateCompanionBuilder =
    CachedIncidentsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> key,
      Value<String> status,
      Value<String> severity,
      Value<int> startedAt,
      Value<String?> serviceId,
      Value<String?> assigneeId,
      Value<String> json,
      Value<int> version,
      Value<int> changeSeq,
      Value<String?> pendingAction,
      Value<int> rowid,
    });

class $$CachedIncidentsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedIncidentsTable> {
  $$CachedIncidentsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get assigneeId => $composableBuilder(
    column: $table.assigneeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changeSeq => $composableBuilder(
    column: $table.changeSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingAction => $composableBuilder(
    column: $table.pendingAction,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedIncidentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedIncidentsTable> {
  $$CachedIncidentsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get severity => $composableBuilder(
    column: $table.severity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get assigneeId => $composableBuilder(
    column: $table.assigneeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changeSeq => $composableBuilder(
    column: $table.changeSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingAction => $composableBuilder(
    column: $table.pendingAction,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedIncidentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedIncidentsTable> {
  $$CachedIncidentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get severity =>
      $composableBuilder(column: $table.severity, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get serviceId =>
      $composableBuilder(column: $table.serviceId, builder: (column) => column);

  GeneratedColumn<String> get assigneeId => $composableBuilder(
    column: $table.assigneeId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<int> get changeSeq =>
      $composableBuilder(column: $table.changeSeq, builder: (column) => column);

  GeneratedColumn<String> get pendingAction => $composableBuilder(
    column: $table.pendingAction,
    builder: (column) => column,
  );
}

class $$CachedIncidentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedIncidentsTable,
          CachedIncident,
          $$CachedIncidentsTableFilterComposer,
          $$CachedIncidentsTableOrderingComposer,
          $$CachedIncidentsTableAnnotationComposer,
          $$CachedIncidentsTableCreateCompanionBuilder,
          $$CachedIncidentsTableUpdateCompanionBuilder,
          (
            CachedIncident,
            BaseReferences<
              _$AppDatabase,
              $CachedIncidentsTable,
              CachedIncident
            >,
          ),
          CachedIncident,
          PrefetchHooks Function()
        > {
  $$CachedIncidentsTableTableManager(
    _$AppDatabase db,
    $CachedIncidentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedIncidentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedIncidentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedIncidentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> severity = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<String?> serviceId = const Value.absent(),
                Value<String?> assigneeId = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> changeSeq = const Value.absent(),
                Value<String?> pendingAction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedIncidentsCompanion(
                id: id,
                orgId: orgId,
                key: key,
                status: status,
                severity: severity,
                startedAt: startedAt,
                serviceId: serviceId,
                assigneeId: assigneeId,
                json: json,
                version: version,
                changeSeq: changeSeq,
                pendingAction: pendingAction,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String key,
                required String status,
                required String severity,
                required int startedAt,
                Value<String?> serviceId = const Value.absent(),
                Value<String?> assigneeId = const Value.absent(),
                required String json,
                required int version,
                required int changeSeq,
                Value<String?> pendingAction = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedIncidentsCompanion.insert(
                id: id,
                orgId: orgId,
                key: key,
                status: status,
                severity: severity,
                startedAt: startedAt,
                serviceId: serviceId,
                assigneeId: assigneeId,
                json: json,
                version: version,
                changeSeq: changeSeq,
                pendingAction: pendingAction,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedIncidentsTable, CachedIncident>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedIncidentsTable,
                    CachedIncident
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedIncidentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedIncidentsTable,
      CachedIncident,
      $$CachedIncidentsTableFilterComposer,
      $$CachedIncidentsTableOrderingComposer,
      $$CachedIncidentsTableAnnotationComposer,
      $$CachedIncidentsTableCreateCompanionBuilder,
      $$CachedIncidentsTableUpdateCompanionBuilder,
      (
        CachedIncident,
        BaseReferences<_$AppDatabase, $CachedIncidentsTable, CachedIncident>,
      ),
      CachedIncident,
      PrefetchHooks Function()
    >;
typedef $$CachedDeploymentsTableCreateCompanionBuilder =
    CachedDeploymentsCompanion Function({
      required String id,
      required String orgId,
      required String serviceId,
      required int startedAt,
      required String json,
      required int changeSeq,
      Value<int> rowid,
    });
typedef $$CachedDeploymentsTableUpdateCompanionBuilder =
    CachedDeploymentsCompanion Function({
      Value<String> id,
      Value<String> orgId,
      Value<String> serviceId,
      Value<int> startedAt,
      Value<String> json,
      Value<int> changeSeq,
      Value<int> rowid,
    });

class $$CachedDeploymentsTableFilterComposer
    extends Composer<_$AppDatabase, $CachedDeploymentsTable> {
  $$CachedDeploymentsTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get changeSeq => $composableBuilder(
    column: $table.changeSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDeploymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedDeploymentsTable> {
  $$CachedDeploymentsTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceId => $composableBuilder(
    column: $table.serviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get changeSeq => $composableBuilder(
    column: $table.changeSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDeploymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedDeploymentsTable> {
  $$CachedDeploymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get serviceId =>
      $composableBuilder(column: $table.serviceId, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<int> get changeSeq =>
      $composableBuilder(column: $table.changeSeq, builder: (column) => column);
}

class $$CachedDeploymentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedDeploymentsTable,
          CachedDeployment,
          $$CachedDeploymentsTableFilterComposer,
          $$CachedDeploymentsTableOrderingComposer,
          $$CachedDeploymentsTableAnnotationComposer,
          $$CachedDeploymentsTableCreateCompanionBuilder,
          $$CachedDeploymentsTableUpdateCompanionBuilder,
          (
            CachedDeployment,
            BaseReferences<
              _$AppDatabase,
              $CachedDeploymentsTable,
              CachedDeployment
            >,
          ),
          CachedDeployment,
          PrefetchHooks Function()
        > {
  $$CachedDeploymentsTableTableManager(
    _$AppDatabase db,
    $CachedDeploymentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDeploymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDeploymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDeploymentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> serviceId = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<int> changeSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDeploymentsCompanion(
                id: id,
                orgId: orgId,
                serviceId: serviceId,
                startedAt: startedAt,
                json: json,
                changeSeq: changeSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgId,
                required String serviceId,
                required int startedAt,
                required String json,
                required int changeSeq,
                Value<int> rowid = const Value.absent(),
              }) => CachedDeploymentsCompanion.insert(
                id: id,
                orgId: orgId,
                serviceId: serviceId,
                startedAt: startedAt,
                json: json,
                changeSeq: changeSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedDeploymentsTable, CachedDeployment>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CachedDeploymentsTable,
                    CachedDeployment
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDeploymentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedDeploymentsTable,
      CachedDeployment,
      $$CachedDeploymentsTableFilterComposer,
      $$CachedDeploymentsTableOrderingComposer,
      $$CachedDeploymentsTableAnnotationComposer,
      $$CachedDeploymentsTableCreateCompanionBuilder,
      $$CachedDeploymentsTableUpdateCompanionBuilder,
      (
        CachedDeployment,
        BaseReferences<
          _$AppDatabase,
          $CachedDeploymentsTable,
          CachedDeployment
        >,
      ),
      CachedDeployment,
      PrefetchHooks Function()
    >;
typedef $$SyncCursorsTableCreateCompanionBuilder =
    SyncCursorsCompanion Function({
      required String orgId,
      required String collection,
      required int cursor,
      Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    SyncCursorsCompanion Function({
      Value<String> orgId,
      Value<String> collection,
      Value<int> cursor,
      Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cursor => $composableBuilder(
    column: $table.cursor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncCursorsTable,
          SyncCursor,
          $$SyncCursorsTableFilterComposer,
          $$SyncCursorsTableOrderingComposer,
          $$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            SyncCursor,
            BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
          ),
          SyncCursor,
          PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(_$AppDatabase db, $SyncCursorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncCursorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> orgId = const Value.absent(),
                Value<String> collection = const Value.absent(),
                Value<int> cursor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion(
                orgId: orgId,
                collection: collection,
                cursor: cursor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String orgId,
                required String collection,
                required int cursor,
                Value<int> rowid = const Value.absent(),
              }) => SyncCursorsCompanion.insert(
                orgId: orgId,
                collection: collection,
                cursor: cursor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncCursorsTable, SyncCursor>(table),
                  BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>(
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

typedef $$SyncCursorsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncCursorsTable,
      SyncCursor,
      $$SyncCursorsTableFilterComposer,
      $$SyncCursorsTableOrderingComposer,
      $$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        SyncCursor,
        BaseReferences<_$AppDatabase, $SyncCursorsTable, SyncCursor>,
      ),
      SyncCursor,
      PrefetchHooks Function()
    >;
typedef $$OutboxEntriesTableCreateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<int> id,
      required String orgId,
      required String incidentId,
      required String kind,
      required String action,
      required String path,
      required String body,
      required String idempotencyKey,
      Value<String?> clientId,
      Value<int?> baseVersion,
      Value<int> attempts,
      Value<int> nextAttemptAt,
      Value<String> state,
      Value<String?> lastError,
      required int createdAt,
    });
typedef $$OutboxEntriesTableUpdateCompanionBuilder =
    OutboxEntriesCompanion Function({
      Value<int> id,
      Value<String> orgId,
      Value<String> incidentId,
      Value<String> kind,
      Value<String> action,
      Value<String> path,
      Value<String> body,
      Value<String> idempotencyKey,
      Value<String?> clientId,
      Value<int?> baseVersion,
      Value<int> attempts,
      Value<int> nextAttemptAt,
      Value<String> state,
      Value<String?> lastError,
      Value<int> createdAt,
    });

class $$OutboxEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableFilterComposer({
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

  ColumnFilters<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get incidentId => $composableBuilder(
    column: $table.incidentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get orgId => $composableBuilder(
    column: $table.orgId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get incidentId => $composableBuilder(
    column: $table.incidentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientId => $composableBuilder(
    column: $table.clientId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxEntriesTable> {
  $$OutboxEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgId =>
      $composableBuilder(column: $table.orgId, builder: (column) => column);

  GeneratedColumn<String> get incidentId => $composableBuilder(
    column: $table.incidentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
    column: $table.idempotencyKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientId =>
      $composableBuilder(column: $table.clientId, builder: (column) => column);

  GeneratedColumn<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxEntriesTable,
          OutboxEntry,
          $$OutboxEntriesTableFilterComposer,
          $$OutboxEntriesTableOrderingComposer,
          $$OutboxEntriesTableAnnotationComposer,
          $$OutboxEntriesTableCreateCompanionBuilder,
          $$OutboxEntriesTableUpdateCompanionBuilder,
          (
            OutboxEntry,
            BaseReferences<_$AppDatabase, $OutboxEntriesTable, OutboxEntry>,
          ),
          OutboxEntry,
          PrefetchHooks Function()
        > {
  $$OutboxEntriesTableTableManager(_$AppDatabase db, $OutboxEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> orgId = const Value.absent(),
                Value<String> incidentId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String> idempotencyKey = const Value.absent(),
                Value<String?> clientId = const Value.absent(),
                Value<int?> baseVersion = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
              }) => OutboxEntriesCompanion(
                id: id,
                orgId: orgId,
                incidentId: incidentId,
                kind: kind,
                action: action,
                path: path,
                body: body,
                idempotencyKey: idempotencyKey,
                clientId: clientId,
                baseVersion: baseVersion,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                state: state,
                lastError: lastError,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String orgId,
                required String incidentId,
                required String kind,
                required String action,
                required String path,
                required String body,
                required String idempotencyKey,
                Value<String?> clientId = const Value.absent(),
                Value<int?> baseVersion = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required int createdAt,
              }) => OutboxEntriesCompanion.insert(
                id: id,
                orgId: orgId,
                incidentId: incidentId,
                kind: kind,
                action: action,
                path: path,
                body: body,
                idempotencyKey: idempotencyKey,
                clientId: clientId,
                baseVersion: baseVersion,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                state: state,
                lastError: lastError,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxEntriesTable, OutboxEntry>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $OutboxEntriesTable,
                    OutboxEntry
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxEntriesTable,
      OutboxEntry,
      $$OutboxEntriesTableFilterComposer,
      $$OutboxEntriesTableOrderingComposer,
      $$OutboxEntriesTableAnnotationComposer,
      $$OutboxEntriesTableCreateCompanionBuilder,
      $$OutboxEntriesTableUpdateCompanionBuilder,
      (
        OutboxEntry,
        BaseReferences<_$AppDatabase, $OutboxEntriesTable, OutboxEntry>,
      ),
      OutboxEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$KeyValueEntriesTableTableManager get keyValueEntries =>
      $$KeyValueEntriesTableTableManager(_db, _db.keyValueEntries);
  $$CachedServicesTableTableManager get cachedServices =>
      $$CachedServicesTableTableManager(_db, _db.cachedServices);
  $$CachedIncidentsTableTableManager get cachedIncidents =>
      $$CachedIncidentsTableTableManager(_db, _db.cachedIncidents);
  $$CachedDeploymentsTableTableManager get cachedDeployments =>
      $$CachedDeploymentsTableTableManager(_db, _db.cachedDeployments);
  $$SyncCursorsTableTableManager get syncCursors =>
      $$SyncCursorsTableTableManager(_db, _db.syncCursors);
  $$OutboxEntriesTableTableManager get outboxEntries =>
      $$OutboxEntriesTableTableManager(_db, _db.outboxEntries);
}
