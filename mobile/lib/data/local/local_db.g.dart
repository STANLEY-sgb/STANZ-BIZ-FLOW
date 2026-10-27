// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $CachedProductsTable extends CachedProducts with TableInfo<$CachedProductsTable, CachedProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _businessIdMeta = const VerificationMeta('businessId');
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameLowerMeta = const VerificationMeta('nameLower');
  @override
  late final GeneratedColumn<String> nameLower = GeneratedColumn<String>(
    'name_lower',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skuMeta = const VerificationMeta('sku');
  @override
  late final GeneratedColumn<String> sku = GeneratedColumn<String>(
    'sku',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _barcodeMeta = const VerificationMeta('barcode');
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
    'barcode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
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
  static const VerificationMeta _syncedAtMeta = const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
    'synced_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [businessId, id, nameLower, sku, barcode, isActive, json, syncedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_products';
  @override
  VerificationContext validateIntegrity(Insertable<CachedProduct> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('business_id')) {
      context.handle(_businessIdMeta, businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta));
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name_lower')) {
      context.handle(_nameLowerMeta, nameLower.isAcceptableOrUnknown(data['name_lower']!, _nameLowerMeta));
    } else if (isInserting) {
      context.missing(_nameLowerMeta);
    }
    if (data.containsKey('sku')) {
      context.handle(_skuMeta, sku.isAcceptableOrUnknown(data['sku']!, _skuMeta));
    }
    if (data.containsKey('barcode')) {
      context.handle(_barcodeMeta, barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta, isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    } else if (isInserting) {
      context.missing(_isActiveMeta);
    }
    if (data.containsKey('json')) {
      context.handle(_jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta, syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {businessId, id};
  @override
  CachedProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedProduct(
      businessId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}business_id'])!,
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      nameLower: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name_lower'])!,
      sku: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}sku']),
      barcode: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}barcode']),
      isActive: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      json: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}json'])!,
      syncedAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at'])!,
    );
  }

  @override
  $CachedProductsTable createAlias(String alias) {
    return $CachedProductsTable(attachedDatabase, alias);
  }
}

class CachedProduct extends DataClass implements Insertable<CachedProduct> {
  final String businessId;
  final String id;
  final String nameLower;
  final String? sku;
  final String? barcode;
  final bool isActive;

  /// Full API JSON so the model can be rebuilt without a second schema.
  final String json;
  final DateTime syncedAt;
  const CachedProduct({
    required this.businessId,
    required this.id,
    required this.nameLower,
    this.sku,
    this.barcode,
    required this.isActive,
    required this.json,
    required this.syncedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['business_id'] = Variable<String>(businessId);
    map['id'] = Variable<String>(id);
    map['name_lower'] = Variable<String>(nameLower);
    if (!nullToAbsent || sku != null) {
      map['sku'] = Variable<String>(sku);
    }
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['json'] = Variable<String>(json);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    return map;
  }

  CachedProductsCompanion toCompanion(bool nullToAbsent) {
    return CachedProductsCompanion(
      businessId: Value(businessId),
      id: Value(id),
      nameLower: Value(nameLower),
      sku: sku == null && nullToAbsent ? const Value.absent() : Value(sku),
      barcode: barcode == null && nullToAbsent ? const Value.absent() : Value(barcode),
      isActive: Value(isActive),
      json: Value(json),
      syncedAt: Value(syncedAt),
    );
  }

  factory CachedProduct.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedProduct(
      businessId: serializer.fromJson<String>(json['businessId']),
      id: serializer.fromJson<String>(json['id']),
      nameLower: serializer.fromJson<String>(json['nameLower']),
      sku: serializer.fromJson<String?>(json['sku']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      json: serializer.fromJson<String>(json['json']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'businessId': serializer.toJson<String>(businessId),
      'id': serializer.toJson<String>(id),
      'nameLower': serializer.toJson<String>(nameLower),
      'sku': serializer.toJson<String?>(sku),
      'barcode': serializer.toJson<String?>(barcode),
      'isActive': serializer.toJson<bool>(isActive),
      'json': serializer.toJson<String>(json),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
    };
  }

  CachedProduct copyWith({
    String? businessId,
    String? id,
    String? nameLower,
    Value<String?> sku = const Value.absent(),
    Value<String?> barcode = const Value.absent(),
    bool? isActive,
    String? json,
    DateTime? syncedAt,
  }) => CachedProduct(
    businessId: businessId ?? this.businessId,
    id: id ?? this.id,
    nameLower: nameLower ?? this.nameLower,
    sku: sku.present ? sku.value : this.sku,
    barcode: barcode.present ? barcode.value : this.barcode,
    isActive: isActive ?? this.isActive,
    json: json ?? this.json,
    syncedAt: syncedAt ?? this.syncedAt,
  );
  CachedProduct copyWithCompanion(CachedProductsCompanion data) {
    return CachedProduct(
      businessId: data.businessId.present ? data.businessId.value : this.businessId,
      id: data.id.present ? data.id.value : this.id,
      nameLower: data.nameLower.present ? data.nameLower.value : this.nameLower,
      sku: data.sku.present ? data.sku.value : this.sku,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      json: data.json.present ? data.json.value : this.json,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedProduct(')
          ..write('businessId: $businessId, ')
          ..write('id: $id, ')
          ..write('nameLower: $nameLower, ')
          ..write('sku: $sku, ')
          ..write('barcode: $barcode, ')
          ..write('isActive: $isActive, ')
          ..write('json: $json, ')
          ..write('syncedAt: $syncedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(businessId, id, nameLower, sku, barcode, isActive, json, syncedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedProduct &&
          other.businessId == this.businessId &&
          other.id == this.id &&
          other.nameLower == this.nameLower &&
          other.sku == this.sku &&
          other.barcode == this.barcode &&
          other.isActive == this.isActive &&
          other.json == this.json &&
          other.syncedAt == this.syncedAt);
}

class CachedProductsCompanion extends UpdateCompanion<CachedProduct> {
  final Value<String> businessId;
  final Value<String> id;
  final Value<String> nameLower;
  final Value<String?> sku;
  final Value<String?> barcode;
  final Value<bool> isActive;
  final Value<String> json;
  final Value<DateTime> syncedAt;
  final Value<int> rowid;
  const CachedProductsCompanion({
    this.businessId = const Value.absent(),
    this.id = const Value.absent(),
    this.nameLower = const Value.absent(),
    this.sku = const Value.absent(),
    this.barcode = const Value.absent(),
    this.isActive = const Value.absent(),
    this.json = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedProductsCompanion.insert({
    required String businessId,
    required String id,
    required String nameLower,
    this.sku = const Value.absent(),
    this.barcode = const Value.absent(),
    required bool isActive,
    required String json,
    required DateTime syncedAt,
    this.rowid = const Value.absent(),
  }) : businessId = Value(businessId),
       id = Value(id),
       nameLower = Value(nameLower),
       isActive = Value(isActive),
       json = Value(json),
       syncedAt = Value(syncedAt);
  static Insertable<CachedProduct> custom({
    Expression<String>? businessId,
    Expression<String>? id,
    Expression<String>? nameLower,
    Expression<String>? sku,
    Expression<String>? barcode,
    Expression<bool>? isActive,
    Expression<String>? json,
    Expression<DateTime>? syncedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (businessId != null) 'business_id': businessId,
      if (id != null) 'id': id,
      if (nameLower != null) 'name_lower': nameLower,
      if (sku != null) 'sku': sku,
      if (barcode != null) 'barcode': barcode,
      if (isActive != null) 'is_active': isActive,
      if (json != null) 'json': json,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedProductsCompanion copyWith({
    Value<String>? businessId,
    Value<String>? id,
    Value<String>? nameLower,
    Value<String?>? sku,
    Value<String?>? barcode,
    Value<bool>? isActive,
    Value<String>? json,
    Value<DateTime>? syncedAt,
    Value<int>? rowid,
  }) {
    return CachedProductsCompanion(
      businessId: businessId ?? this.businessId,
      id: id ?? this.id,
      nameLower: nameLower ?? this.nameLower,
      sku: sku ?? this.sku,
      barcode: barcode ?? this.barcode,
      isActive: isActive ?? this.isActive,
      json: json ?? this.json,
      syncedAt: syncedAt ?? this.syncedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (nameLower.present) {
      map['name_lower'] = Variable<String>(nameLower.value);
    }
    if (sku.present) {
      map['sku'] = Variable<String>(sku.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedProductsCompanion(')
          ..write('businessId: $businessId, ')
          ..write('id: $id, ')
          ..write('nameLower: $nameLower, ')
          ..write('sku: $sku, ')
          ..write('barcode: $barcode, ')
          ..write('isActive: $isActive, ')
          ..write('json: $json, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingSalesTable extends PendingSales with TableInfo<$PendingSalesTable, PendingSale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingSalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientReferenceMeta = const VerificationMeta('clientReference');
  @override
  late final GeneratedColumn<String> clientReference = GeneratedColumn<String>(
    'client_reference',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _businessIdMeta = const VerificationMeta('businessId');
  @override
  late final GeneratedColumn<String> businessId = GeneratedColumn<String>(
    'business_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta('payloadJson');
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _previewTotalMeta = const VerificationMeta('previewTotal');
  @override
  late final GeneratedColumn<String> previewTotal = GeneratedColumn<String>(
    'preview_total',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _summaryMeta = const VerificationMeta('summary');
  @override
  late final GeneratedColumn<String> summary = GeneratedColumn<String>(
    'summary',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
  static const VerificationMeta _attemptsMeta = const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta('nextAttemptAt');
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt = GeneratedColumn<DateTime>(
    'next_attempt_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta('lastErrorCode');
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMessageMeta = const VerificationMeta('lastErrorMessage');
  @override
  late final GeneratedColumn<String> lastErrorMessage = GeneratedColumn<String>(
    'last_error_message',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serverSaleIdMeta = const VerificationMeta('serverSaleId');
  @override
  late final GeneratedColumn<String> serverSaleId = GeneratedColumn<String>(
    'server_sale_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receiptNumberMeta = const VerificationMeta('receiptNumber');
  @override
  late final GeneratedColumn<String> receiptNumber = GeneratedColumn<String>(
    'receipt_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acknowledgedAtMeta = const VerificationMeta('acknowledgedAt');
  @override
  late final GeneratedColumn<DateTime> acknowledgedAt = GeneratedColumn<DateTime>(
    'acknowledged_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientReference,
    businessId,
    userId,
    payloadJson,
    previewTotal,
    summary,
    createdAt,
    state,
    attempts,
    nextAttemptAt,
    lastErrorCode,
    lastErrorMessage,
    serverSaleId,
    receiptNumber,
    acknowledgedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_sales';
  @override
  VerificationContext validateIntegrity(Insertable<PendingSale> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_reference')) {
      context.handle(
        _clientReferenceMeta,
        clientReference.isAcceptableOrUnknown(data['client_reference']!, _clientReferenceMeta),
      );
    } else if (isInserting) {
      context.missing(_clientReferenceMeta);
    }
    if (data.containsKey('business_id')) {
      context.handle(_businessIdMeta, businessId.isAcceptableOrUnknown(data['business_id']!, _businessIdMeta));
    } else if (isInserting) {
      context.missing(_businessIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta, userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(_payloadJsonMeta, payloadJson.isAcceptableOrUnknown(data['payload_json']!, _payloadJsonMeta));
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('preview_total')) {
      context.handle(_previewTotalMeta, previewTotal.isAcceptableOrUnknown(data['preview_total']!, _previewTotalMeta));
    } else if (isInserting) {
      context.missing(_previewTotalMeta);
    }
    if (data.containsKey('summary')) {
      context.handle(_summaryMeta, summary.isAcceptableOrUnknown(data['summary']!, _summaryMeta));
    } else if (isInserting) {
      context.missing(_summaryMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta, createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(_stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta, attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(data['next_attempt_at']!, _nextAttemptAtMeta),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(data['last_error_code']!, _lastErrorCodeMeta),
      );
    }
    if (data.containsKey('last_error_message')) {
      context.handle(
        _lastErrorMessageMeta,
        lastErrorMessage.isAcceptableOrUnknown(data['last_error_message']!, _lastErrorMessageMeta),
      );
    }
    if (data.containsKey('server_sale_id')) {
      context.handle(_serverSaleIdMeta, serverSaleId.isAcceptableOrUnknown(data['server_sale_id']!, _serverSaleIdMeta));
    }
    if (data.containsKey('receipt_number')) {
      context.handle(
        _receiptNumberMeta,
        receiptNumber.isAcceptableOrUnknown(data['receipt_number']!, _receiptNumberMeta),
      );
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
        _acknowledgedAtMeta,
        acknowledgedAt.isAcceptableOrUnknown(data['acknowledged_at']!, _acknowledgedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientReference};
  @override
  PendingSale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingSale(
      clientReference: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_reference'],
      )!,
      businessId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}business_id'])!,
      userId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      payloadJson: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}payload_json'])!,
      previewTotal: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}preview_total'])!,
      summary: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}summary'])!,
      createdAt: attachedDatabase.typeMapping.read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      state: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}state'])!,
      attempts: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}last_error_code']),
      lastErrorMessage: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_message'],
      ),
      serverSaleId: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}server_sale_id']),
      receiptNumber: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}receipt_number']),
      acknowledgedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}acknowledged_at'],
      ),
    );
  }

  @override
  $PendingSalesTable createAlias(String alias) {
    return $PendingSalesTable(attachedDatabase, alias);
  }
}

class PendingSale extends DataClass implements Insertable<PendingSale> {
  final String clientReference;
  final String businessId;

  /// The cashier who recorded it. Only that user's session may send it, so a different
  /// person signing in on a shared phone can never submit sales under their own name.
  final String userId;
  final String payloadJson;

  /// Preview figures for the UI only; the server recalculates on sync.
  final String previewTotal;
  final String summary;
  final DateTime createdAt;

  /// pending | syncing | accepted | duplicate | rejected
  final String state;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;
  final String? serverSaleId;
  final String? receiptNumber;
  final DateTime? acknowledgedAt;
  const PendingSale({
    required this.clientReference,
    required this.businessId,
    required this.userId,
    required this.payloadJson,
    required this.previewTotal,
    required this.summary,
    required this.createdAt,
    required this.state,
    required this.attempts,
    this.nextAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.serverSaleId,
    this.receiptNumber,
    this.acknowledgedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_reference'] = Variable<String>(clientReference);
    map['business_id'] = Variable<String>(businessId);
    map['user_id'] = Variable<String>(userId);
    map['payload_json'] = Variable<String>(payloadJson);
    map['preview_total'] = Variable<String>(previewTotal);
    map['summary'] = Variable<String>(summary);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    if (!nullToAbsent || lastErrorMessage != null) {
      map['last_error_message'] = Variable<String>(lastErrorMessage);
    }
    if (!nullToAbsent || serverSaleId != null) {
      map['server_sale_id'] = Variable<String>(serverSaleId);
    }
    if (!nullToAbsent || receiptNumber != null) {
      map['receipt_number'] = Variable<String>(receiptNumber);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    return map;
  }

  PendingSalesCompanion toCompanion(bool nullToAbsent) {
    return PendingSalesCompanion(
      clientReference: Value(clientReference),
      businessId: Value(businessId),
      userId: Value(userId),
      payloadJson: Value(payloadJson),
      previewTotal: Value(previewTotal),
      summary: Value(summary),
      createdAt: Value(createdAt),
      state: Value(state),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent ? const Value.absent() : Value(nextAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent ? const Value.absent() : Value(lastErrorCode),
      lastErrorMessage: lastErrorMessage == null && nullToAbsent ? const Value.absent() : Value(lastErrorMessage),
      serverSaleId: serverSaleId == null && nullToAbsent ? const Value.absent() : Value(serverSaleId),
      receiptNumber: receiptNumber == null && nullToAbsent ? const Value.absent() : Value(receiptNumber),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent ? const Value.absent() : Value(acknowledgedAt),
    );
  }

  factory PendingSale.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingSale(
      clientReference: serializer.fromJson<String>(json['clientReference']),
      businessId: serializer.fromJson<String>(json['businessId']),
      userId: serializer.fromJson<String>(json['userId']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      previewTotal: serializer.fromJson<String>(json['previewTotal']),
      summary: serializer.fromJson<String>(json['summary']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      lastErrorMessage: serializer.fromJson<String?>(json['lastErrorMessage']),
      serverSaleId: serializer.fromJson<String?>(json['serverSaleId']),
      receiptNumber: serializer.fromJson<String?>(json['receiptNumber']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientReference': serializer.toJson<String>(clientReference),
      'businessId': serializer.toJson<String>(businessId),
      'userId': serializer.toJson<String>(userId),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'previewTotal': serializer.toJson<String>(previewTotal),
      'summary': serializer.toJson<String>(summary),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'lastErrorMessage': serializer.toJson<String?>(lastErrorMessage),
      'serverSaleId': serializer.toJson<String?>(serverSaleId),
      'receiptNumber': serializer.toJson<String?>(receiptNumber),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
    };
  }

  PendingSale copyWith({
    String? clientReference,
    String? businessId,
    String? userId,
    String? payloadJson,
    String? previewTotal,
    String? summary,
    DateTime? createdAt,
    String? state,
    int? attempts,
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    Value<String?> lastErrorMessage = const Value.absent(),
    Value<String?> serverSaleId = const Value.absent(),
    Value<String?> receiptNumber = const Value.absent(),
    Value<DateTime?> acknowledgedAt = const Value.absent(),
  }) => PendingSale(
    clientReference: clientReference ?? this.clientReference,
    businessId: businessId ?? this.businessId,
    userId: userId ?? this.userId,
    payloadJson: payloadJson ?? this.payloadJson,
    previewTotal: previewTotal ?? this.previewTotal,
    summary: summary ?? this.summary,
    createdAt: createdAt ?? this.createdAt,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt.present ? nextAttemptAt.value : this.nextAttemptAt,
    lastErrorCode: lastErrorCode.present ? lastErrorCode.value : this.lastErrorCode,
    lastErrorMessage: lastErrorMessage.present ? lastErrorMessage.value : this.lastErrorMessage,
    serverSaleId: serverSaleId.present ? serverSaleId.value : this.serverSaleId,
    receiptNumber: receiptNumber.present ? receiptNumber.value : this.receiptNumber,
    acknowledgedAt: acknowledgedAt.present ? acknowledgedAt.value : this.acknowledgedAt,
  );
  PendingSale copyWithCompanion(PendingSalesCompanion data) {
    return PendingSale(
      clientReference: data.clientReference.present ? data.clientReference.value : this.clientReference,
      businessId: data.businessId.present ? data.businessId.value : this.businessId,
      userId: data.userId.present ? data.userId.value : this.userId,
      payloadJson: data.payloadJson.present ? data.payloadJson.value : this.payloadJson,
      previewTotal: data.previewTotal.present ? data.previewTotal.value : this.previewTotal,
      summary: data.summary.present ? data.summary.value : this.summary,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present ? data.nextAttemptAt.value : this.nextAttemptAt,
      lastErrorCode: data.lastErrorCode.present ? data.lastErrorCode.value : this.lastErrorCode,
      lastErrorMessage: data.lastErrorMessage.present ? data.lastErrorMessage.value : this.lastErrorMessage,
      serverSaleId: data.serverSaleId.present ? data.serverSaleId.value : this.serverSaleId,
      receiptNumber: data.receiptNumber.present ? data.receiptNumber.value : this.receiptNumber,
      acknowledgedAt: data.acknowledgedAt.present ? data.acknowledgedAt.value : this.acknowledgedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingSale(')
          ..write('clientReference: $clientReference, ')
          ..write('businessId: $businessId, ')
          ..write('userId: $userId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('previewTotal: $previewTotal, ')
          ..write('summary: $summary, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('serverSaleId: $serverSaleId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('acknowledgedAt: $acknowledgedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientReference,
    businessId,
    userId,
    payloadJson,
    previewTotal,
    summary,
    createdAt,
    state,
    attempts,
    nextAttemptAt,
    lastErrorCode,
    lastErrorMessage,
    serverSaleId,
    receiptNumber,
    acknowledgedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingSale &&
          other.clientReference == this.clientReference &&
          other.businessId == this.businessId &&
          other.userId == this.userId &&
          other.payloadJson == this.payloadJson &&
          other.previewTotal == this.previewTotal &&
          other.summary == this.summary &&
          other.createdAt == this.createdAt &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.lastErrorMessage == this.lastErrorMessage &&
          other.serverSaleId == this.serverSaleId &&
          other.receiptNumber == this.receiptNumber &&
          other.acknowledgedAt == this.acknowledgedAt);
}

class PendingSalesCompanion extends UpdateCompanion<PendingSale> {
  final Value<String> clientReference;
  final Value<String> businessId;
  final Value<String> userId;
  final Value<String> payloadJson;
  final Value<String> previewTotal;
  final Value<String> summary;
  final Value<DateTime> createdAt;
  final Value<String> state;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<String?> lastErrorMessage;
  final Value<String?> serverSaleId;
  final Value<String?> receiptNumber;
  final Value<DateTime?> acknowledgedAt;
  final Value<int> rowid;
  const PendingSalesCompanion({
    this.clientReference = const Value.absent(),
    this.businessId = const Value.absent(),
    this.userId = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.previewTotal = const Value.absent(),
    this.summary = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.serverSaleId = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingSalesCompanion.insert({
    required String clientReference,
    required String businessId,
    required String userId,
    required String payloadJson,
    required String previewTotal,
    required String summary,
    required DateTime createdAt,
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.lastErrorMessage = const Value.absent(),
    this.serverSaleId = const Value.absent(),
    this.receiptNumber = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : clientReference = Value(clientReference),
       businessId = Value(businessId),
       userId = Value(userId),
       payloadJson = Value(payloadJson),
       previewTotal = Value(previewTotal),
       summary = Value(summary),
       createdAt = Value(createdAt);
  static Insertable<PendingSale> custom({
    Expression<String>? clientReference,
    Expression<String>? businessId,
    Expression<String>? userId,
    Expression<String>? payloadJson,
    Expression<String>? previewTotal,
    Expression<String>? summary,
    Expression<DateTime>? createdAt,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<String>? lastErrorMessage,
    Expression<String>? serverSaleId,
    Expression<String>? receiptNumber,
    Expression<DateTime>? acknowledgedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientReference != null) 'client_reference': clientReference,
      if (businessId != null) 'business_id': businessId,
      if (userId != null) 'user_id': userId,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (previewTotal != null) 'preview_total': previewTotal,
      if (summary != null) 'summary': summary,
      if (createdAt != null) 'created_at': createdAt,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      if (serverSaleId != null) 'server_sale_id': serverSaleId,
      if (receiptNumber != null) 'receipt_number': receiptNumber,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingSalesCompanion copyWith({
    Value<String>? clientReference,
    Value<String>? businessId,
    Value<String>? userId,
    Value<String>? payloadJson,
    Value<String>? previewTotal,
    Value<String>? summary,
    Value<DateTime>? createdAt,
    Value<String>? state,
    Value<int>? attempts,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastErrorCode,
    Value<String?>? lastErrorMessage,
    Value<String?>? serverSaleId,
    Value<String?>? receiptNumber,
    Value<DateTime?>? acknowledgedAt,
    Value<int>? rowid,
  }) {
    return PendingSalesCompanion(
      clientReference: clientReference ?? this.clientReference,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      payloadJson: payloadJson ?? this.payloadJson,
      previewTotal: previewTotal ?? this.previewTotal,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      serverSaleId: serverSaleId ?? this.serverSaleId,
      receiptNumber: receiptNumber ?? this.receiptNumber,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientReference.present) {
      map['client_reference'] = Variable<String>(clientReference.value);
    }
    if (businessId.present) {
      map['business_id'] = Variable<String>(businessId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (previewTotal.present) {
      map['preview_total'] = Variable<String>(previewTotal.value);
    }
    if (summary.present) {
      map['summary'] = Variable<String>(summary.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (lastErrorMessage.present) {
      map['last_error_message'] = Variable<String>(lastErrorMessage.value);
    }
    if (serverSaleId.present) {
      map['server_sale_id'] = Variable<String>(serverSaleId.value);
    }
    if (receiptNumber.present) {
      map['receipt_number'] = Variable<String>(receiptNumber.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingSalesCompanion(')
          ..write('clientReference: $clientReference, ')
          ..write('businessId: $businessId, ')
          ..write('userId: $userId, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('previewTotal: $previewTotal, ')
          ..write('summary: $summary, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('lastErrorMessage: $lastErrorMessage, ')
          ..write('serverSaleId: $serverSaleId, ')
          ..write('receiptNumber: $receiptNumber, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KeyValuesTable extends KeyValues with TableInfo<$KeyValuesTable, KeyValue> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KeyValuesTable(this.attachedDatabase, [this._alias]);
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
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'key_values';
  @override
  VerificationContext validateIntegrity(Insertable<KeyValue> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(_keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(_valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KeyValue map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KeyValue(
      key: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $KeyValuesTable createAlias(String alias) {
    return $KeyValuesTable(attachedDatabase, alias);
  }
}

class KeyValue extends DataClass implements Insertable<KeyValue> {
  final String key;
  final String value;
  const KeyValue({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KeyValuesCompanion toCompanion(bool nullToAbsent) {
    return KeyValuesCompanion(key: Value(key), value: Value(value));
  }

  factory KeyValue.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KeyValue(key: serializer.fromJson<String>(json['key']), value: serializer.fromJson<String>(json['value']));
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'key': serializer.toJson<String>(key), 'value': serializer.toJson<String>(value)};
  }

  KeyValue copyWith({String? key, String? value}) => KeyValue(key: key ?? this.key, value: value ?? this.value);
  KeyValue copyWithCompanion(KeyValuesCompanion data) {
    return KeyValue(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KeyValue(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is KeyValue && other.key == this.key && other.value == this.value);
}

class KeyValuesCompanion extends UpdateCompanion<KeyValue> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const KeyValuesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KeyValuesCompanion.insert({required String key, required String value, this.rowid = const Value.absent()})
    : key = Value(key),
      value = Value(value);
  static Insertable<KeyValue> custom({Expression<String>? key, Expression<String>? value, Expression<int>? rowid}) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KeyValuesCompanion copyWith({Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return KeyValuesCompanion(key: key ?? this.key, value: value ?? this.value, rowid: rowid ?? this.rowid);
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
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KeyValuesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDb extends GeneratedDatabase {
  _$LocalDb(QueryExecutor e) : super(e);
  $LocalDbManager get managers => $LocalDbManager(this);
  late final $CachedProductsTable cachedProducts = $CachedProductsTable(this);
  late final $PendingSalesTable pendingSales = $PendingSalesTable(this);
  late final $KeyValuesTable keyValues = $KeyValuesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [cachedProducts, pendingSales, keyValues];
}

typedef $$CachedProductsTableCreateCompanionBuilder = CachedProductsCompanion Function({
  required String businessId,
  required String id,
  required String nameLower,
  Value<String?> sku,
  Value<String?> barcode,
  required bool isActive,
  required String json,
  required DateTime syncedAt,
  Value<int> rowid,
});
typedef $$CachedProductsTableUpdateCompanionBuilder = CachedProductsCompanion Function({
  Value<String> businessId,
  Value<String> id,
  Value<String> nameLower,
  Value<String?> sku,
  Value<String?> barcode,
  Value<bool> isActive,
  Value<String> json,
  Value<DateTime> syncedAt,
  Value<int> rowid,
});

class $$CachedProductsTableFilterComposer extends Composer<_$LocalDb, $CachedProductsTable> {
  $$CachedProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get businessId =>
      $composableBuilder(column: $table.businessId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nameLower =>
      $composableBuilder(column: $table.nameLower, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sku => $composableBuilder(column: $table.sku, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(column: $table.json, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => ColumnFilters(column));
}

class $$CachedProductsTableOrderingComposer extends Composer<_$LocalDb, $CachedProductsTable> {
  $$CachedProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get businessId =>
      $composableBuilder(column: $table.businessId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get id => $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nameLower =>
      $composableBuilder(column: $table.nameLower, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sku =>
      $composableBuilder(column: $table.sku, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => ColumnOrderings(column));
}

class $$CachedProductsTableAnnotationComposer extends Composer<_$LocalDb, $CachedProductsTable> {
  $$CachedProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get businessId => $composableBuilder(column: $table.businessId, builder: (column) => column);

  GeneratedColumn<String> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nameLower => $composableBuilder(column: $table.nameLower, builder: (column) => column);

  GeneratedColumn<String> get sku => $composableBuilder(column: $table.sku, builder: (column) => column);

  GeneratedColumn<String> get barcode => $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<bool> get isActive => $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<String> get json => $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt => $composableBuilder(column: $table.syncedAt, builder: (column) => column);
}

class $$CachedProductsTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $CachedProductsTable,
          CachedProduct,
          $$CachedProductsTableFilterComposer,
          $$CachedProductsTableOrderingComposer,
          $$CachedProductsTableAnnotationComposer,
          $$CachedProductsTableCreateCompanionBuilder,
          $$CachedProductsTableUpdateCompanionBuilder,
          (CachedProduct, BaseReferences<_$LocalDb, $CachedProductsTable, CachedProduct>),
          CachedProduct,
          PrefetchHooks Function()
        > {
  $$CachedProductsTableTableManager(_$LocalDb db, $CachedProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$CachedProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$CachedProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$CachedProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> businessId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> nameLower = const Value.absent(),
                Value<String?> sku = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> syncedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedProductsCompanion(
                businessId: businessId,
                id: id,
                nameLower: nameLower,
                sku: sku,
                barcode: barcode,
                isActive: isActive,
                json: json,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String businessId,
                required String id,
                required String nameLower,
                Value<String?> sku = const Value.absent(),
                Value<String?> barcode = const Value.absent(),
                required bool isActive,
                required String json,
                required DateTime syncedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedProductsCompanion.insert(
                businessId: businessId,
                id: id,
                nameLower: nameLower,
                sku: sku,
                barcode: barcode,
                isActive: isActive,
                json: json,
                syncedAt: syncedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CachedProductsTable, CachedProduct>(table),
                  BaseReferences<_$LocalDb, $CachedProductsTable, CachedProduct>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $CachedProductsTable,
      CachedProduct,
      $$CachedProductsTableFilterComposer,
      $$CachedProductsTableOrderingComposer,
      $$CachedProductsTableAnnotationComposer,
      $$CachedProductsTableCreateCompanionBuilder,
      $$CachedProductsTableUpdateCompanionBuilder,
      (CachedProduct, BaseReferences<_$LocalDb, $CachedProductsTable, CachedProduct>),
      CachedProduct,
      PrefetchHooks Function()
    >;
typedef $$PendingSalesTableCreateCompanionBuilder = PendingSalesCompanion Function({
  required String clientReference,
  required String businessId,
  required String userId,
  required String payloadJson,
  required String previewTotal,
  required String summary,
  required DateTime createdAt,
  Value<String> state,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
  Value<String?> lastErrorCode,
  Value<String?> lastErrorMessage,
  Value<String?> serverSaleId,
  Value<String?> receiptNumber,
  Value<DateTime?> acknowledgedAt,
  Value<int> rowid,
});
typedef $$PendingSalesTableUpdateCompanionBuilder = PendingSalesCompanion Function({
  Value<String> clientReference,
  Value<String> businessId,
  Value<String> userId,
  Value<String> payloadJson,
  Value<String> previewTotal,
  Value<String> summary,
  Value<DateTime> createdAt,
  Value<String> state,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
  Value<String?> lastErrorCode,
  Value<String?> lastErrorMessage,
  Value<String?> serverSaleId,
  Value<String?> receiptNumber,
  Value<DateTime?> acknowledgedAt,
  Value<int> rowid,
});

class $$PendingSalesTableFilterComposer extends Composer<_$LocalDb, $PendingSalesTable> {
  $$PendingSalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientReference =>
      $composableBuilder(column: $table.clientReference, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get businessId =>
      $composableBuilder(column: $table.businessId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadJson =>
      $composableBuilder(column: $table.payloadJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get previewTotal =>
      $composableBuilder(column: $table.previewTotal, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextAttemptAt =>
      $composableBuilder(column: $table.nextAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastErrorCode =>
      $composableBuilder(column: $table.lastErrorCode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastErrorMessage =>
      $composableBuilder(column: $table.lastErrorMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverSaleId =>
      $composableBuilder(column: $table.serverSaleId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get receiptNumber =>
      $composableBuilder(column: $table.receiptNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get acknowledgedAt =>
      $composableBuilder(column: $table.acknowledgedAt, builder: (column) => ColumnFilters(column));
}

class $$PendingSalesTableOrderingComposer extends Composer<_$LocalDb, $PendingSalesTable> {
  $$PendingSalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientReference =>
      $composableBuilder(column: $table.clientReference, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get businessId =>
      $composableBuilder(column: $table.businessId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadJson =>
      $composableBuilder(column: $table.payloadJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get previewTotal =>
      $composableBuilder(column: $table.previewTotal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get summary =>
      $composableBuilder(column: $table.summary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextAttemptAt =>
      $composableBuilder(column: $table.nextAttemptAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastErrorCode =>
      $composableBuilder(column: $table.lastErrorCode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastErrorMessage =>
      $composableBuilder(column: $table.lastErrorMessage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverSaleId =>
      $composableBuilder(column: $table.serverSaleId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get receiptNumber =>
      $composableBuilder(column: $table.receiptNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get acknowledgedAt =>
      $composableBuilder(column: $table.acknowledgedAt, builder: (column) => ColumnOrderings(column));
}

class $$PendingSalesTableAnnotationComposer extends Composer<_$LocalDb, $PendingSalesTable> {
  $$PendingSalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientReference =>
      $composableBuilder(column: $table.clientReference, builder: (column) => column);

  GeneratedColumn<String> get businessId => $composableBuilder(column: $table.businessId, builder: (column) => column);

  GeneratedColumn<String> get userId => $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get payloadJson =>
      $composableBuilder(column: $table.payloadJson, builder: (column) => column);

  GeneratedColumn<String> get previewTotal =>
      $composableBuilder(column: $table.previewTotal, builder: (column) => column);

  GeneratedColumn<String> get summary => $composableBuilder(column: $table.summary, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt => $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get state => $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts => $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt =>
      $composableBuilder(column: $table.nextAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get lastErrorCode =>
      $composableBuilder(column: $table.lastErrorCode, builder: (column) => column);

  GeneratedColumn<String> get lastErrorMessage =>
      $composableBuilder(column: $table.lastErrorMessage, builder: (column) => column);

  GeneratedColumn<String> get serverSaleId =>
      $composableBuilder(column: $table.serverSaleId, builder: (column) => column);

  GeneratedColumn<String> get receiptNumber =>
      $composableBuilder(column: $table.receiptNumber, builder: (column) => column);

  GeneratedColumn<DateTime> get acknowledgedAt =>
      $composableBuilder(column: $table.acknowledgedAt, builder: (column) => column);
}

class $$PendingSalesTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $PendingSalesTable,
          PendingSale,
          $$PendingSalesTableFilterComposer,
          $$PendingSalesTableOrderingComposer,
          $$PendingSalesTableAnnotationComposer,
          $$PendingSalesTableCreateCompanionBuilder,
          $$PendingSalesTableUpdateCompanionBuilder,
          (PendingSale, BaseReferences<_$LocalDb, $PendingSalesTable, PendingSale>),
          PendingSale,
          PrefetchHooks Function()
        > {
  $$PendingSalesTableTableManager(_$LocalDb db, $PendingSalesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$PendingSalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$PendingSalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$PendingSalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientReference = const Value.absent(),
                Value<String> businessId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String> previewTotal = const Value.absent(),
                Value<String> summary = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<String?> serverSaleId = const Value.absent(),
                Value<String?> receiptNumber = const Value.absent(),
                Value<DateTime?> acknowledgedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSalesCompanion(
                clientReference: clientReference,
                businessId: businessId,
                userId: userId,
                payloadJson: payloadJson,
                previewTotal: previewTotal,
                summary: summary,
                createdAt: createdAt,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                serverSaleId: serverSaleId,
                receiptNumber: receiptNumber,
                acknowledgedAt: acknowledgedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientReference,
                required String businessId,
                required String userId,
                required String payloadJson,
                required String previewTotal,
                required String summary,
                required DateTime createdAt,
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String?> lastErrorMessage = const Value.absent(),
                Value<String?> serverSaleId = const Value.absent(),
                Value<String?> receiptNumber = const Value.absent(),
                Value<DateTime?> acknowledgedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingSalesCompanion.insert(
                clientReference: clientReference,
                businessId: businessId,
                userId: userId,
                payloadJson: payloadJson,
                previewTotal: previewTotal,
                summary: summary,
                createdAt: createdAt,
                state: state,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                lastErrorMessage: lastErrorMessage,
                serverSaleId: serverSaleId,
                receiptNumber: receiptNumber,
                acknowledgedAt: acknowledgedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingSalesTable, PendingSale>(table),
                  BaseReferences<_$LocalDb, $PendingSalesTable, PendingSale>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingSalesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $PendingSalesTable,
      PendingSale,
      $$PendingSalesTableFilterComposer,
      $$PendingSalesTableOrderingComposer,
      $$PendingSalesTableAnnotationComposer,
      $$PendingSalesTableCreateCompanionBuilder,
      $$PendingSalesTableUpdateCompanionBuilder,
      (PendingSale, BaseReferences<_$LocalDb, $PendingSalesTable, PendingSale>),
      PendingSale,
      PrefetchHooks Function()
    >;
typedef $$KeyValuesTableCreateCompanionBuilder = KeyValuesCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$KeyValuesTableUpdateCompanionBuilder = KeyValuesCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$KeyValuesTableFilterComposer extends Composer<_$LocalDb, $KeyValuesTable> {
  $$KeyValuesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$KeyValuesTableOrderingComposer extends Composer<_$LocalDb, $KeyValuesTable> {
  $$KeyValuesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$KeyValuesTableAnnotationComposer extends Composer<_$LocalDb, $KeyValuesTable> {
  $$KeyValuesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key => $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value => $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$KeyValuesTableTableManager
    extends
        RootTableManager<
          _$LocalDb,
          $KeyValuesTable,
          KeyValue,
          $$KeyValuesTableFilterComposer,
          $$KeyValuesTableOrderingComposer,
          $$KeyValuesTableAnnotationComposer,
          $$KeyValuesTableCreateCompanionBuilder,
          $$KeyValuesTableUpdateCompanionBuilder,
          (KeyValue, BaseReferences<_$LocalDb, $KeyValuesTable, KeyValue>),
          KeyValue,
          PrefetchHooks Function()
        > {
  $$KeyValuesTableTableManager(_$LocalDb db, $KeyValuesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$KeyValuesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$KeyValuesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$KeyValuesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => KeyValuesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => KeyValuesCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KeyValuesTable, KeyValue>(table),
                  BaseReferences<_$LocalDb, $KeyValuesTable, KeyValue>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KeyValuesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDb,
      $KeyValuesTable,
      KeyValue,
      $$KeyValuesTableFilterComposer,
      $$KeyValuesTableOrderingComposer,
      $$KeyValuesTableAnnotationComposer,
      $$KeyValuesTableCreateCompanionBuilder,
      $$KeyValuesTableUpdateCompanionBuilder,
      (KeyValue, BaseReferences<_$LocalDb, $KeyValuesTable, KeyValue>),
      KeyValue,
      PrefetchHooks Function()
    >;

class $LocalDbManager {
  final _$LocalDb _db;
  $LocalDbManager(this._db);
  $$CachedProductsTableTableManager get cachedProducts => $$CachedProductsTableTableManager(_db, _db.cachedProducts);
  $$PendingSalesTableTableManager get pendingSales => $$PendingSalesTableTableManager(_db, _db.pendingSales);
  $$KeyValuesTableTableManager get keyValues => $$KeyValuesTableTableManager(_db, _db.keyValues);
}
