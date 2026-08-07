// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $AccountsTable extends Accounts with TableInfo<$AccountsTable, Account> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AccountsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#3B82F6'),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('wallet'),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    currency,
    description,
    color,
    icon,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'accounts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Account> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['is_archived']!, _archivedMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Account map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Account(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $AccountsTable createAlias(String alias) {
    return $AccountsTable(attachedDatabase, alias);
  }
}

class Account extends DataClass implements Insertable<Account> {
  final String id;
  final String name;
  final String currency;
  final String? description;
  final String color;
  final String icon;
  final bool archived;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const Account({
    required this.id,
    required this.name,
    required this.currency,
    this.description,
    required this.color,
    required this.icon,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['currency'] = Variable<String>(currency);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['color'] = Variable<String>(color);
    map['icon'] = Variable<String>(icon);
    map['is_archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  AccountsCompanion toCompanion(bool nullToAbsent) {
    return AccountsCompanion(
      id: Value(id),
      name: Value(name),
      currency: Value(currency),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      color: Value(color),
      icon: Value(icon),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory Account.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Account(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String>(json['currency']),
      description: serializer.fromJson<String?>(json['description']),
      color: serializer.fromJson<String>(json['color']),
      icon: serializer.fromJson<String>(json['icon']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String>(currency),
      'description': serializer.toJson<String?>(description),
      'color': serializer.toJson<String>(color),
      'icon': serializer.toJson<String>(icon),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  Account copyWith({
    String? id,
    String? name,
    String? currency,
    Value<String?> description = const Value.absent(),
    String? color,
    String? icon,
    bool? archived,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => Account(
    id: id ?? this.id,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    description: description.present ? description.value : this.description,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  Account copyWithCompanion(AccountsCompanion data) {
    return Account(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      description: data.description.present
          ? data.description.value
          : this.description,
      color: data.color.present ? data.color.value : this.color,
      icon: data.icon.present ? data.icon.value : this.icon,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Account(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('description: $description, ')
          ..write('color: $color, ')
          ..write('icon: $icon, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    currency,
    description,
    color,
    icon,
    archived,
    createdAt,
    updatedAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Account &&
          other.id == this.id &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.description == this.description &&
          other.color == this.color &&
          other.icon == this.icon &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class AccountsCompanion extends UpdateCompanion<Account> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> currency;
  final Value<String?> description;
  final Value<String> color;
  final Value<String> icon;
  final Value<bool> archived;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const AccountsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.description = const Value.absent(),
    this.color = const Value.absent(),
    this.icon = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AccountsCompanion.insert({
    required String id,
    required String name,
    required String currency,
    this.description = const Value.absent(),
    this.color = const Value.absent(),
    this.icon = const Value.absent(),
    this.archived = const Value.absent(),
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       currency = Value(currency),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Account> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<String>? description,
    Expression<String>? color,
    Expression<String>? icon,
    Expression<bool>? archived,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (description != null) 'description': description,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
      if (archived != null) 'is_archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AccountsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? currency,
    Value<String?>? description,
    Value<String>? color,
    Value<String>? icon,
    Value<bool>? archived,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return AccountsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (archived.present) {
      map['is_archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AccountsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('description: $description, ')
          ..write('color: $color, ')
          ..write('icon: $icon, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, Category> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#6366F1'),
  );
  static const VerificationMeta _iconMeta = const VerificationMeta('icon');
  @override
  late final GeneratedColumn<String> icon = GeneratedColumn<String>(
    'icon',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('category'),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    color,
    icon,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<Category> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('icon')) {
      context.handle(
        _iconMeta,
        icon.isAcceptableOrUnknown(data['icon']!, _iconMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['is_archived']!, _archivedMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Category map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Category(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      icon: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class Category extends DataClass implements Insertable<Category> {
  final String id;
  final String name;
  final String? description;
  final String color;
  final String icon;
  final bool archived;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const Category({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    required this.icon,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['color'] = Variable<String>(color);
    map['icon'] = Variable<String>(icon);
    map['is_archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      color: Value(color),
      icon: Value(icon),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory Category.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Category(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      color: serializer.fromJson<String>(json['color']),
      icon: serializer.fromJson<String>(json['icon']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'color': serializer.toJson<String>(color),
      'icon': serializer.toJson<String>(icon),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  Category copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    String? color,
    String? icon,
    bool? archived,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  Category copyWithCompanion(CategoriesCompanion data) {
    return Category(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      color: data.color.present ? data.color.value : this.color,
      icon: data.icon.present ? data.icon.value : this.icon,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Category(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('color: $color, ')
          ..write('icon: $icon, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    color,
    icon,
    archived,
    createdAt,
    updatedAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Category &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.color == this.color &&
          other.icon == this.icon &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class CategoriesCompanion extends UpdateCompanion<Category> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> color;
  final Value<String> icon;
  final Value<bool> archived;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.color = const Value.absent(),
    this.icon = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoriesCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.color = const Value.absent(),
    this.icon = const Value.absent(),
    this.archived = const Value.absent(),
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Category> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? color,
    Expression<String>? icon,
    Expression<bool>? archived,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (color != null) 'color': color,
      if (icon != null) 'icon': icon,
      if (archived != null) 'is_archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? color,
    Value<String>? icon,
    Value<bool>? archived,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (icon.present) {
      map['icon'] = Variable<String>(icon.value);
    }
    if (archived.present) {
      map['is_archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('color: $color, ')
          ..write('icon: $icon, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionsTable extends Transactions
    with TableInfo<$TransactionsTable, Transaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<BigInt> date = GeneratedColumn<BigInt>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TransactionTimeStatus, String>
  timeStatus =
      GeneratedColumn<String>(
        'time_status',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('none'),
      ).withConverter<TransactionTimeStatus>(
        $TransactionsTable.$convertertimeStatus,
      );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<BigInt> amount = GeneratedColumn<BigInt>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateConfirmedMeta = const VerificationMeta(
    'dateConfirmed',
  );
  @override
  late final GeneratedColumn<bool> dateConfirmed = GeneratedColumn<bool>(
    'date_confirmed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("date_confirmed" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _toAccountIdMeta = const VerificationMeta(
    'toAccountId',
  );
  @override
  late final GeneratedColumn<String> toAccountId = GeneratedColumn<String>(
    'to_account_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toAmountMeta = const VerificationMeta(
    'toAmount',
  );
  @override
  late final GeneratedColumn<BigInt> toAmount = GeneratedColumn<BigInt>(
    'to_amount',
    aliasedName,
    true,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _toCurrencyMeta = const VerificationMeta(
    'toCurrency',
  );
  @override
  late final GeneratedColumn<String> toCurrency = GeneratedColumn<String>(
    'to_currency',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exchangeRateMeta = const VerificationMeta(
    'exchangeRate',
  );
  @override
  late final GeneratedColumn<double> exchangeRate = GeneratedColumn<double>(
    'exchange_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _balanceAfterMeta = const VerificationMeta(
    'balanceAfter',
  );
  @override
  late final GeneratedColumn<BigInt> balanceAfter = GeneratedColumn<BigInt>(
    'balance_after',
    aliasedName,
    true,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    name,
    description,
    status,
    date,
    timeStatus,
    accountId,
    categoryId,
    amount,
    currency,
    dateConfirmed,
    toAccountId,
    toAmount,
    toCurrency,
    exchangeRate,
    balanceAfter,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transactions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Transaction> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('date_confirmed')) {
      context.handle(
        _dateConfirmedMeta,
        dateConfirmed.isAcceptableOrUnknown(
          data['date_confirmed']!,
          _dateConfirmedMeta,
        ),
      );
    }
    if (data.containsKey('to_account_id')) {
      context.handle(
        _toAccountIdMeta,
        toAccountId.isAcceptableOrUnknown(
          data['to_account_id']!,
          _toAccountIdMeta,
        ),
      );
    }
    if (data.containsKey('to_amount')) {
      context.handle(
        _toAmountMeta,
        toAmount.isAcceptableOrUnknown(data['to_amount']!, _toAmountMeta),
      );
    }
    if (data.containsKey('to_currency')) {
      context.handle(
        _toCurrencyMeta,
        toCurrency.isAcceptableOrUnknown(data['to_currency']!, _toCurrencyMeta),
      );
    }
    if (data.containsKey('exchange_rate')) {
      context.handle(
        _exchangeRateMeta,
        exchangeRate.isAcceptableOrUnknown(
          data['exchange_rate']!,
          _exchangeRateMeta,
        ),
      );
    }
    if (data.containsKey('balance_after')) {
      context.handle(
        _balanceAfterMeta,
        balanceAfter.isAcceptableOrUnknown(
          data['balance_after']!,
          _balanceAfterMeta,
        ),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['is_archived']!, _archivedMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Transaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Transaction(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}date'],
      )!,
      timeStatus: $TransactionsTable.$convertertimeStatus.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}time_status'],
        )!,
      ),
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}amount'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      dateConfirmed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}date_confirmed'],
      )!,
      toAccountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_account_id'],
      ),
      toAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}to_amount'],
      ),
      toCurrency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_currency'],
      ),
      exchangeRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}exchange_rate'],
      ),
      balanceAfter: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}balance_after'],
      ),
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $TransactionsTable createAlias(String alias) {
    return $TransactionsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TransactionTimeStatus, String, String>
  $convertertimeStatus = const EnumNameConverter<TransactionTimeStatus>(
    TransactionTimeStatus.values,
  );
}

class Transaction extends DataClass implements Insertable<Transaction> {
  final String id;
  final String type;
  final String name;
  final String? description;
  final String status;
  final BigInt date;
  final TransactionTimeStatus timeStatus;
  final String accountId;
  final String categoryId;
  final BigInt amount;
  final String currency;
  final bool dateConfirmed;
  final String? toAccountId;
  final BigInt? toAmount;
  final String? toCurrency;
  final double? exchangeRate;
  final BigInt? balanceAfter;
  final bool archived;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const Transaction({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    required this.status,
    required this.date,
    required this.timeStatus,
    required this.accountId,
    required this.categoryId,
    required this.amount,
    required this.currency,
    required this.dateConfirmed,
    this.toAccountId,
    this.toAmount,
    this.toCurrency,
    this.exchangeRate,
    this.balanceAfter,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['date'] = Variable<BigInt>(date);
    {
      map['time_status'] = Variable<String>(
        $TransactionsTable.$convertertimeStatus.toSql(timeStatus),
      );
    }
    map['account_id'] = Variable<String>(accountId);
    map['category_id'] = Variable<String>(categoryId);
    map['amount'] = Variable<BigInt>(amount);
    map['currency'] = Variable<String>(currency);
    map['date_confirmed'] = Variable<bool>(dateConfirmed);
    if (!nullToAbsent || toAccountId != null) {
      map['to_account_id'] = Variable<String>(toAccountId);
    }
    if (!nullToAbsent || toAmount != null) {
      map['to_amount'] = Variable<BigInt>(toAmount);
    }
    if (!nullToAbsent || toCurrency != null) {
      map['to_currency'] = Variable<String>(toCurrency);
    }
    if (!nullToAbsent || exchangeRate != null) {
      map['exchange_rate'] = Variable<double>(exchangeRate);
    }
    if (!nullToAbsent || balanceAfter != null) {
      map['balance_after'] = Variable<BigInt>(balanceAfter);
    }
    map['is_archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  TransactionsCompanion toCompanion(bool nullToAbsent) {
    return TransactionsCompanion(
      id: Value(id),
      type: Value(type),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      date: Value(date),
      timeStatus: Value(timeStatus),
      accountId: Value(accountId),
      categoryId: Value(categoryId),
      amount: Value(amount),
      currency: Value(currency),
      dateConfirmed: Value(dateConfirmed),
      toAccountId: toAccountId == null && nullToAbsent
          ? const Value.absent()
          : Value(toAccountId),
      toAmount: toAmount == null && nullToAbsent
          ? const Value.absent()
          : Value(toAmount),
      toCurrency: toCurrency == null && nullToAbsent
          ? const Value.absent()
          : Value(toCurrency),
      exchangeRate: exchangeRate == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRate),
      balanceAfter: balanceAfter == null && nullToAbsent
          ? const Value.absent()
          : Value(balanceAfter),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory Transaction.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Transaction(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      date: serializer.fromJson<BigInt>(json['date']),
      timeStatus: $TransactionsTable.$convertertimeStatus.fromJson(
        serializer.fromJson<String>(json['timeStatus']),
      ),
      accountId: serializer.fromJson<String>(json['accountId']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amount: serializer.fromJson<BigInt>(json['amount']),
      currency: serializer.fromJson<String>(json['currency']),
      dateConfirmed: serializer.fromJson<bool>(json['dateConfirmed']),
      toAccountId: serializer.fromJson<String?>(json['toAccountId']),
      toAmount: serializer.fromJson<BigInt?>(json['toAmount']),
      toCurrency: serializer.fromJson<String?>(json['toCurrency']),
      exchangeRate: serializer.fromJson<double?>(json['exchangeRate']),
      balanceAfter: serializer.fromJson<BigInt?>(json['balanceAfter']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'date': serializer.toJson<BigInt>(date),
      'timeStatus': serializer.toJson<String>(
        $TransactionsTable.$convertertimeStatus.toJson(timeStatus),
      ),
      'accountId': serializer.toJson<String>(accountId),
      'categoryId': serializer.toJson<String>(categoryId),
      'amount': serializer.toJson<BigInt>(amount),
      'currency': serializer.toJson<String>(currency),
      'dateConfirmed': serializer.toJson<bool>(dateConfirmed),
      'toAccountId': serializer.toJson<String?>(toAccountId),
      'toAmount': serializer.toJson<BigInt?>(toAmount),
      'toCurrency': serializer.toJson<String?>(toCurrency),
      'exchangeRate': serializer.toJson<double?>(exchangeRate),
      'balanceAfter': serializer.toJson<BigInt?>(balanceAfter),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  Transaction copyWith({
    String? id,
    String? type,
    String? name,
    Value<String?> description = const Value.absent(),
    String? status,
    BigInt? date,
    TransactionTimeStatus? timeStatus,
    String? accountId,
    String? categoryId,
    BigInt? amount,
    String? currency,
    bool? dateConfirmed,
    Value<String?> toAccountId = const Value.absent(),
    Value<BigInt?> toAmount = const Value.absent(),
    Value<String?> toCurrency = const Value.absent(),
    Value<double?> exchangeRate = const Value.absent(),
    Value<BigInt?> balanceAfter = const Value.absent(),
    bool? archived,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => Transaction(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    status: status ?? this.status,
    date: date ?? this.date,
    timeStatus: timeStatus ?? this.timeStatus,
    accountId: accountId ?? this.accountId,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    currency: currency ?? this.currency,
    dateConfirmed: dateConfirmed ?? this.dateConfirmed,
    toAccountId: toAccountId.present ? toAccountId.value : this.toAccountId,
    toAmount: toAmount.present ? toAmount.value : this.toAmount,
    toCurrency: toCurrency.present ? toCurrency.value : this.toCurrency,
    exchangeRate: exchangeRate.present ? exchangeRate.value : this.exchangeRate,
    balanceAfter: balanceAfter.present ? balanceAfter.value : this.balanceAfter,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  Transaction copyWithCompanion(TransactionsCompanion data) {
    return Transaction(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      date: data.date.present ? data.date.value : this.date,
      timeStatus: data.timeStatus.present
          ? data.timeStatus.value
          : this.timeStatus,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      amount: data.amount.present ? data.amount.value : this.amount,
      currency: data.currency.present ? data.currency.value : this.currency,
      dateConfirmed: data.dateConfirmed.present
          ? data.dateConfirmed.value
          : this.dateConfirmed,
      toAccountId: data.toAccountId.present
          ? data.toAccountId.value
          : this.toAccountId,
      toAmount: data.toAmount.present ? data.toAmount.value : this.toAmount,
      toCurrency: data.toCurrency.present
          ? data.toCurrency.value
          : this.toCurrency,
      exchangeRate: data.exchangeRate.present
          ? data.exchangeRate.value
          : this.exchangeRate,
      balanceAfter: data.balanceAfter.present
          ? data.balanceAfter.value
          : this.balanceAfter,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Transaction(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('date: $date, ')
          ..write('timeStatus: $timeStatus, ')
          ..write('accountId: $accountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('currency: $currency, ')
          ..write('dateConfirmed: $dateConfirmed, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('toAmount: $toAmount, ')
          ..write('toCurrency: $toCurrency, ')
          ..write('exchangeRate: $exchangeRate, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    name,
    description,
    status,
    date,
    timeStatus,
    accountId,
    categoryId,
    amount,
    currency,
    dateConfirmed,
    toAccountId,
    toAmount,
    toCurrency,
    exchangeRate,
    balanceAfter,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Transaction &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.description == this.description &&
          other.status == this.status &&
          other.date == this.date &&
          other.timeStatus == this.timeStatus &&
          other.accountId == this.accountId &&
          other.categoryId == this.categoryId &&
          other.amount == this.amount &&
          other.currency == this.currency &&
          other.dateConfirmed == this.dateConfirmed &&
          other.toAccountId == this.toAccountId &&
          other.toAmount == this.toAmount &&
          other.toCurrency == this.toCurrency &&
          other.exchangeRate == this.exchangeRate &&
          other.balanceAfter == this.balanceAfter &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class TransactionsCompanion extends UpdateCompanion<Transaction> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> name;
  final Value<String?> description;
  final Value<String> status;
  final Value<BigInt> date;
  final Value<TransactionTimeStatus> timeStatus;
  final Value<String> accountId;
  final Value<String> categoryId;
  final Value<BigInt> amount;
  final Value<String> currency;
  final Value<bool> dateConfirmed;
  final Value<String?> toAccountId;
  final Value<BigInt?> toAmount;
  final Value<String?> toCurrency;
  final Value<double?> exchangeRate;
  final Value<BigInt?> balanceAfter;
  final Value<bool> archived;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const TransactionsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.date = const Value.absent(),
    this.timeStatus = const Value.absent(),
    this.accountId = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amount = const Value.absent(),
    this.currency = const Value.absent(),
    this.dateConfirmed = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.toAmount = const Value.absent(),
    this.toCurrency = const Value.absent(),
    this.exchangeRate = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionsCompanion.insert({
    required String id,
    required String type,
    required String name,
    this.description = const Value.absent(),
    required String status,
    required BigInt date,
    this.timeStatus = const Value.absent(),
    required String accountId,
    required String categoryId,
    required BigInt amount,
    required String currency,
    this.dateConfirmed = const Value.absent(),
    this.toAccountId = const Value.absent(),
    this.toAmount = const Value.absent(),
    this.toCurrency = const Value.absent(),
    this.exchangeRate = const Value.absent(),
    this.balanceAfter = const Value.absent(),
    this.archived = const Value.absent(),
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       name = Value(name),
       status = Value(status),
       date = Value(date),
       accountId = Value(accountId),
       categoryId = Value(categoryId),
       amount = Value(amount),
       currency = Value(currency),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Transaction> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? status,
    Expression<BigInt>? date,
    Expression<String>? timeStatus,
    Expression<String>? accountId,
    Expression<String>? categoryId,
    Expression<BigInt>? amount,
    Expression<String>? currency,
    Expression<bool>? dateConfirmed,
    Expression<String>? toAccountId,
    Expression<BigInt>? toAmount,
    Expression<String>? toCurrency,
    Expression<double>? exchangeRate,
    Expression<BigInt>? balanceAfter,
    Expression<bool>? archived,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (date != null) 'date': date,
      if (timeStatus != null) 'time_status': timeStatus,
      if (accountId != null) 'account_id': accountId,
      if (categoryId != null) 'category_id': categoryId,
      if (amount != null) 'amount': amount,
      if (currency != null) 'currency': currency,
      if (dateConfirmed != null) 'date_confirmed': dateConfirmed,
      if (toAccountId != null) 'to_account_id': toAccountId,
      if (toAmount != null) 'to_amount': toAmount,
      if (toCurrency != null) 'to_currency': toCurrency,
      if (exchangeRate != null) 'exchange_rate': exchangeRate,
      if (balanceAfter != null) 'balance_after': balanceAfter,
      if (archived != null) 'is_archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String>? name,
    Value<String?>? description,
    Value<String>? status,
    Value<BigInt>? date,
    Value<TransactionTimeStatus>? timeStatus,
    Value<String>? accountId,
    Value<String>? categoryId,
    Value<BigInt>? amount,
    Value<String>? currency,
    Value<bool>? dateConfirmed,
    Value<String?>? toAccountId,
    Value<BigInt?>? toAmount,
    Value<String?>? toCurrency,
    Value<double?>? exchangeRate,
    Value<BigInt?>? balanceAfter,
    Value<bool>? archived,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return TransactionsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      description: description ?? this.description,
      status: status ?? this.status,
      date: date ?? this.date,
      timeStatus: timeStatus ?? this.timeStatus,
      accountId: accountId ?? this.accountId,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      dateConfirmed: dateConfirmed ?? this.dateConfirmed,
      toAccountId: toAccountId ?? this.toAccountId,
      toAmount: toAmount ?? this.toAmount,
      toCurrency: toCurrency ?? this.toCurrency,
      exchangeRate: exchangeRate ?? this.exchangeRate,
      balanceAfter: balanceAfter ?? this.balanceAfter,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (date.present) {
      map['date'] = Variable<BigInt>(date.value);
    }
    if (timeStatus.present) {
      map['time_status'] = Variable<String>(
        $TransactionsTable.$convertertimeStatus.toSql(timeStatus.value),
      );
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (amount.present) {
      map['amount'] = Variable<BigInt>(amount.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (dateConfirmed.present) {
      map['date_confirmed'] = Variable<bool>(dateConfirmed.value);
    }
    if (toAccountId.present) {
      map['to_account_id'] = Variable<String>(toAccountId.value);
    }
    if (toAmount.present) {
      map['to_amount'] = Variable<BigInt>(toAmount.value);
    }
    if (toCurrency.present) {
      map['to_currency'] = Variable<String>(toCurrency.value);
    }
    if (exchangeRate.present) {
      map['exchange_rate'] = Variable<double>(exchangeRate.value);
    }
    if (balanceAfter.present) {
      map['balance_after'] = Variable<BigInt>(balanceAfter.value);
    }
    if (archived.present) {
      map['is_archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('date: $date, ')
          ..write('timeStatus: $timeStatus, ')
          ..write('accountId: $accountId, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('currency: $currency, ')
          ..write('dateConfirmed: $dateConfirmed, ')
          ..write('toAccountId: $toAccountId, ')
          ..write('toAmount: $toAmount, ')
          ..write('toCurrency: $toCurrency, ')
          ..write('exchangeRate: $exchangeRate, ')
          ..write('balanceAfter: $balanceAfter, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TagsTable extends Tags with TableInfo<$TagsTable, Tag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentIdMeta = const VerificationMeta(
    'parentId',
  );
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
    'parent_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<String> color = GeneratedColumn<String>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('#69F0AE'),
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    description,
    parentId,
    color,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('parent_id')) {
      context.handle(
        _parentIdMeta,
        parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['is_archived']!, _archivedMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Tag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      parentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_id'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $TagsTable createAlias(String alias) {
    return $TagsTable(attachedDatabase, alias);
  }
}

class Tag extends DataClass implements Insertable<Tag> {
  final String id;
  final String name;
  final String? description;
  final String? parentId;
  final String color;
  final bool archived;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const Tag({
    required this.id,
    required this.name,
    this.description,
    this.parentId,
    required this.color,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['color'] = Variable<String>(color);
    map['is_archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  TagsCompanion toCompanion(bool nullToAbsent) {
    return TagsCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      color: Value(color),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory Tag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tag(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      color: serializer.fromJson<String>(json['color']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'parentId': serializer.toJson<String?>(parentId),
      'color': serializer.toJson<String>(color),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  Tag copyWith({
    String? id,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> parentId = const Value.absent(),
    String? color,
    bool? archived,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => Tag(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    parentId: parentId.present ? parentId.value : this.parentId,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  Tag copyWithCompanion(TagsCompanion data) {
    return Tag(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      color: data.color.present ? data.color.value : this.color,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tag(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('parentId: $parentId, ')
          ..write('color: $color, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    description,
    parentId,
    color,
    archived,
    createdAt,
    updatedAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tag &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.parentId == this.parentId &&
          other.color == this.color &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class TagsCompanion extends UpdateCompanion<Tag> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> parentId;
  final Value<String> color;
  final Value<bool> archived;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const TagsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.parentId = const Value.absent(),
    this.color = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TagsCompanion.insert({
    required String id,
    required String name,
    this.description = const Value.absent(),
    this.parentId = const Value.absent(),
    this.color = const Value.absent(),
    this.archived = const Value.absent(),
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Tag> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? parentId,
    Expression<String>? color,
    Expression<bool>? archived,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (parentId != null) 'parent_id': parentId,
      if (color != null) 'color': color,
      if (archived != null) 'is_archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TagsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? parentId,
    Value<String>? color,
    Value<bool>? archived,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return TagsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      parentId: parentId ?? this.parentId,
      color: color ?? this.color,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (color.present) {
      map['color'] = Variable<String>(color.value);
    }
    if (archived.present) {
      map['is_archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TagsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('parentId: $parentId, ')
          ..write('color: $color, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionTagsTable extends TransactionTags
    with TableInfo<$TransactionTagsTable, TransactionTag> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionTagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta(
    'transactionId',
  );
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
    'transaction_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagIdMeta = const VerificationMeta('tagId');
  @override
  late final GeneratedColumn<String> tagId = GeneratedColumn<String>(
    'tag_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    transactionId,
    tagId,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_tags';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransactionTag> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(
          data['transaction_id']!,
          _transactionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionIdMeta);
    }
    if (data.containsKey('tag_id')) {
      context.handle(
        _tagIdMeta,
        tagId.isAcceptableOrUnknown(data['tag_id']!, _tagIdMeta),
      );
    } else if (isInserting) {
      context.missing(_tagIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {transactionId, tagId},
  ];
  @override
  TransactionTag map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionTag(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      transactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_id'],
      )!,
      tagId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tag_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $TransactionTagsTable createAlias(String alias) {
    return $TransactionTagsTable(attachedDatabase, alias);
  }
}

class TransactionTag extends DataClass implements Insertable<TransactionTag> {
  final String id;
  final String transactionId;
  final String tagId;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const TransactionTag({
    required this.id,
    required this.transactionId,
    required this.tagId,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['transaction_id'] = Variable<String>(transactionId);
    map['tag_id'] = Variable<String>(tagId);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  TransactionTagsCompanion toCompanion(bool nullToAbsent) {
    return TransactionTagsCompanion(
      id: Value(id),
      transactionId: Value(transactionId),
      tagId: Value(tagId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory TransactionTag.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionTag(
      id: serializer.fromJson<String>(json['id']),
      transactionId: serializer.fromJson<String>(json['transactionId']),
      tagId: serializer.fromJson<String>(json['tagId']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'transactionId': serializer.toJson<String>(transactionId),
      'tagId': serializer.toJson<String>(tagId),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  TransactionTag copyWith({
    String? id,
    String? transactionId,
    String? tagId,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => TransactionTag(
    id: id ?? this.id,
    transactionId: transactionId ?? this.transactionId,
    tagId: tagId ?? this.tagId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  TransactionTag copyWithCompanion(TransactionTagsCompanion data) {
    return TransactionTag(
      id: data.id.present ? data.id.value : this.id,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      tagId: data.tagId.present ? data.tagId.value : this.tagId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionTag(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('tagId: $tagId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, transactionId, tagId, createdAt, updatedAt, dirty);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionTag &&
          other.id == this.id &&
          other.transactionId == this.transactionId &&
          other.tagId == this.tagId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class TransactionTagsCompanion extends UpdateCompanion<TransactionTag> {
  final Value<String> id;
  final Value<String> transactionId;
  final Value<String> tagId;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const TransactionTagsCompanion({
    this.id = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.tagId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionTagsCompanion.insert({
    required String id,
    required String transactionId,
    required String tagId,
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       transactionId = Value(transactionId),
       tagId = Value(tagId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<TransactionTag> custom({
    Expression<String>? id,
    Expression<String>? transactionId,
    Expression<String>? tagId,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (transactionId != null) 'transaction_id': transactionId,
      if (tagId != null) 'tag_id': tagId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionTagsCompanion copyWith({
    Value<String>? id,
    Value<String>? transactionId,
    Value<String>? tagId,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return TransactionTagsCompanion(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      tagId: tagId ?? this.tagId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (tagId.present) {
      map['tag_id'] = Variable<String>(tagId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionTagsCompanion(')
          ..write('id: $id, ')
          ..write('transactionId: $transactionId, ')
          ..write('tagId: $tagId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavedFiltersTable extends SavedFilters
    with TableInfo<$SavedFiltersTable, SavedFilter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedFiltersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _configMeta = const VerificationMeta('config');
  @override
  late final GeneratedColumn<String> config = GeneratedColumn<String>(
    'config',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    config,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_filters';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedFilter> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('config')) {
      context.handle(
        _configMeta,
        config.isAcceptableOrUnknown(data['config']!, _configMeta),
      );
    } else if (isInserting) {
      context.missing(_configMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['is_archived']!, _archivedMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedFilter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedFilter(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      config: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $SavedFiltersTable createAlias(String alias) {
    return $SavedFiltersTable(attachedDatabase, alias);
  }
}

class SavedFilter extends DataClass implements Insertable<SavedFilter> {
  final String id;
  final String name;
  final String config;
  final bool archived;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const SavedFilter({
    required this.id,
    required this.name,
    required this.config,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['config'] = Variable<String>(config);
    map['is_archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  SavedFiltersCompanion toCompanion(bool nullToAbsent) {
    return SavedFiltersCompanion(
      id: Value(id),
      name: Value(name),
      config: Value(config),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory SavedFilter.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedFilter(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      config: serializer.fromJson<String>(json['config']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'config': serializer.toJson<String>(config),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  SavedFilter copyWith({
    String? id,
    String? name,
    String? config,
    bool? archived,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => SavedFilter(
    id: id ?? this.id,
    name: name ?? this.name,
    config: config ?? this.config,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  SavedFilter copyWithCompanion(SavedFiltersCompanion data) {
    return SavedFilter(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      config: data.config.present ? data.config.value : this.config,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedFilter(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('config: $config, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, config, archived, createdAt, updatedAt, dirty);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedFilter &&
          other.id == this.id &&
          other.name == this.name &&
          other.config == this.config &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class SavedFiltersCompanion extends UpdateCompanion<SavedFilter> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> config;
  final Value<bool> archived;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const SavedFiltersCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.config = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedFiltersCompanion.insert({
    required String id,
    required String name,
    required String config,
    this.archived = const Value.absent(),
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       config = Value(config),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SavedFilter> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? config,
    Expression<bool>? archived,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (config != null) 'config': config,
      if (archived != null) 'is_archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedFiltersCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? config,
    Value<bool>? archived,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return SavedFiltersCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (config.present) {
      map['config'] = Variable<String>(config.value);
    }
    if (archived.present) {
      map['is_archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedFiltersCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('config: $config, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DashboardWidgetsTable extends DashboardWidgets
    with TableInfo<$DashboardWidgetsTable, DashboardWidget> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DashboardWidgetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _filterIdMeta = const VerificationMeta(
    'filterId',
  );
  @override
  late final GeneratedColumn<String> filterId = GeneratedColumn<String>(
    'filter_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<String> width = GeneratedColumn<String>(
    'width',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _optionsMeta = const VerificationMeta(
    'options',
  );
  @override
  late final GeneratedColumn<String> options = GeneratedColumn<String>(
    'options',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedMeta = const VerificationMeta(
    'archived',
  );
  @override
  late final GeneratedColumn<bool> archived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    filterId,
    position,
    width,
    options,
    archived,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dashboard_widgets';
  @override
  VerificationContext validateIntegrity(
    Insertable<DashboardWidget> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('filter_id')) {
      context.handle(
        _filterIdMeta,
        filterId.isAcceptableOrUnknown(data['filter_id']!, _filterIdMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
        _widthMeta,
        width.isAcceptableOrUnknown(data['width']!, _widthMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('options')) {
      context.handle(
        _optionsMeta,
        options.isAcceptableOrUnknown(data['options']!, _optionsMeta),
      );
    } else if (isInserting) {
      context.missing(_optionsMeta);
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _archivedMeta,
        archived.isAcceptableOrUnknown(data['is_archived']!, _archivedMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DashboardWidget map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DashboardWidget(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      filterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filter_id'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      width: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}width'],
      )!,
      options: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}options'],
      )!,
      archived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $DashboardWidgetsTable createAlias(String alias) {
    return $DashboardWidgetsTable(attachedDatabase, alias);
  }
}

class DashboardWidget extends DataClass implements Insertable<DashboardWidget> {
  final String id;
  final String type;
  final String? filterId;
  final int position;
  final String width;
  final String options;
  final bool archived;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const DashboardWidget({
    required this.id,
    required this.type,
    this.filterId,
    required this.position,
    required this.width,
    required this.options,
    required this.archived,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || filterId != null) {
      map['filter_id'] = Variable<String>(filterId);
    }
    map['position'] = Variable<int>(position);
    map['width'] = Variable<String>(width);
    map['options'] = Variable<String>(options);
    map['is_archived'] = Variable<bool>(archived);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  DashboardWidgetsCompanion toCompanion(bool nullToAbsent) {
    return DashboardWidgetsCompanion(
      id: Value(id),
      type: Value(type),
      filterId: filterId == null && nullToAbsent
          ? const Value.absent()
          : Value(filterId),
      position: Value(position),
      width: Value(width),
      options: Value(options),
      archived: Value(archived),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory DashboardWidget.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DashboardWidget(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      filterId: serializer.fromJson<String?>(json['filterId']),
      position: serializer.fromJson<int>(json['position']),
      width: serializer.fromJson<String>(json['width']),
      options: serializer.fromJson<String>(json['options']),
      archived: serializer.fromJson<bool>(json['archived']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'filterId': serializer.toJson<String?>(filterId),
      'position': serializer.toJson<int>(position),
      'width': serializer.toJson<String>(width),
      'options': serializer.toJson<String>(options),
      'archived': serializer.toJson<bool>(archived),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  DashboardWidget copyWith({
    String? id,
    String? type,
    Value<String?> filterId = const Value.absent(),
    int? position,
    String? width,
    String? options,
    bool? archived,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => DashboardWidget(
    id: id ?? this.id,
    type: type ?? this.type,
    filterId: filterId.present ? filterId.value : this.filterId,
    position: position ?? this.position,
    width: width ?? this.width,
    options: options ?? this.options,
    archived: archived ?? this.archived,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  DashboardWidget copyWithCompanion(DashboardWidgetsCompanion data) {
    return DashboardWidget(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      filterId: data.filterId.present ? data.filterId.value : this.filterId,
      position: data.position.present ? data.position.value : this.position,
      width: data.width.present ? data.width.value : this.width,
      options: data.options.present ? data.options.value : this.options,
      archived: data.archived.present ? data.archived.value : this.archived,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DashboardWidget(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('filterId: $filterId, ')
          ..write('position: $position, ')
          ..write('width: $width, ')
          ..write('options: $options, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    filterId,
    position,
    width,
    options,
    archived,
    createdAt,
    updatedAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DashboardWidget &&
          other.id == this.id &&
          other.type == this.type &&
          other.filterId == this.filterId &&
          other.position == this.position &&
          other.width == this.width &&
          other.options == this.options &&
          other.archived == this.archived &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class DashboardWidgetsCompanion extends UpdateCompanion<DashboardWidget> {
  final Value<String> id;
  final Value<String> type;
  final Value<String?> filterId;
  final Value<int> position;
  final Value<String> width;
  final Value<String> options;
  final Value<bool> archived;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const DashboardWidgetsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.filterId = const Value.absent(),
    this.position = const Value.absent(),
    this.width = const Value.absent(),
    this.options = const Value.absent(),
    this.archived = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DashboardWidgetsCompanion.insert({
    required String id,
    required String type,
    this.filterId = const Value.absent(),
    required int position,
    required String width,
    required String options,
    this.archived = const Value.absent(),
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       position = Value(position),
       width = Value(width),
       options = Value(options),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DashboardWidget> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? filterId,
    Expression<int>? position,
    Expression<String>? width,
    Expression<String>? options,
    Expression<bool>? archived,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (filterId != null) 'filter_id': filterId,
      if (position != null) 'position': position,
      if (width != null) 'width': width,
      if (options != null) 'options': options,
      if (archived != null) 'is_archived': archived,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DashboardWidgetsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String?>? filterId,
    Value<int>? position,
    Value<String>? width,
    Value<String>? options,
    Value<bool>? archived,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return DashboardWidgetsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      filterId: filterId ?? this.filterId,
      position: position ?? this.position,
      width: width ?? this.width,
      options: options ?? this.options,
      archived: archived ?? this.archived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (filterId.present) {
      map['filter_id'] = Variable<String>(filterId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (width.present) {
      map['width'] = Variable<String>(width.value);
    }
    if (options.present) {
      map['options'] = Variable<String>(options.value);
    }
    if (archived.present) {
      map['is_archived'] = Variable<bool>(archived.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DashboardWidgetsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('filterId: $filterId, ')
          ..write('position: $position, ')
          ..write('width: $width, ')
          ..write('options: $options, ')
          ..write('archived: $archived, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('singleton'),
  );
  static const VerificationMeta _lastServerSeqMeta = const VerificationMeta(
    'lastServerSeq',
  );
  @override
  late final GeneratedColumn<BigInt> lastServerSeq = GeneratedColumn<BigInt>(
    'last_server_seq',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: false,
    defaultValue: Constant(BigInt.zero),
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<BigInt> lastSyncedAt = GeneratedColumn<BigInt>(
    'last_synced_at',
    aliasedName,
    true,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dashboardSeededMeta = const VerificationMeta(
    'dashboardSeeded',
  );
  @override
  late final GeneratedColumn<bool> dashboardSeeded = GeneratedColumn<bool>(
    'dashboard_seeded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dashboard_seeded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lastServerSeq,
    lastSyncedAt,
    dashboardSeeded,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_server_seq')) {
      context.handle(
        _lastServerSeqMeta,
        lastServerSeq.isAcceptableOrUnknown(
          data['last_server_seq']!,
          _lastServerSeqMeta,
        ),
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
    if (data.containsKey('dashboard_seeded')) {
      context.handle(
        _dashboardSeededMeta,
        dashboardSeeded.isAcceptableOrUnknown(
          data['dashboard_seeded']!,
          _dashboardSeededMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      lastServerSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}last_server_seq'],
      )!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}last_synced_at'],
      ),
      dashboardSeeded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dashboard_seeded'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final String id;
  final BigInt lastServerSeq;
  final BigInt? lastSyncedAt;
  final bool dashboardSeeded;
  const SyncStateData({
    required this.id,
    required this.lastServerSeq,
    this.lastSyncedAt,
    required this.dashboardSeeded,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['last_server_seq'] = Variable<BigInt>(lastServerSeq);
    if (!nullToAbsent || lastSyncedAt != null) {
      map['last_synced_at'] = Variable<BigInt>(lastSyncedAt);
    }
    map['dashboard_seeded'] = Variable<bool>(dashboardSeeded);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      lastServerSeq: Value(lastServerSeq),
      lastSyncedAt: lastSyncedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncedAt),
      dashboardSeeded: Value(dashboardSeeded),
    );
  }

  factory SyncStateData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      id: serializer.fromJson<String>(json['id']),
      lastServerSeq: serializer.fromJson<BigInt>(json['lastServerSeq']),
      lastSyncedAt: serializer.fromJson<BigInt?>(json['lastSyncedAt']),
      dashboardSeeded: serializer.fromJson<bool>(json['dashboardSeeded']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'lastServerSeq': serializer.toJson<BigInt>(lastServerSeq),
      'lastSyncedAt': serializer.toJson<BigInt?>(lastSyncedAt),
      'dashboardSeeded': serializer.toJson<bool>(dashboardSeeded),
    };
  }

  SyncStateData copyWith({
    String? id,
    BigInt? lastServerSeq,
    Value<BigInt?> lastSyncedAt = const Value.absent(),
    bool? dashboardSeeded,
  }) => SyncStateData(
    id: id ?? this.id,
    lastServerSeq: lastServerSeq ?? this.lastServerSeq,
    lastSyncedAt: lastSyncedAt.present ? lastSyncedAt.value : this.lastSyncedAt,
    dashboardSeeded: dashboardSeeded ?? this.dashboardSeeded,
  );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      id: data.id.present ? data.id.value : this.id,
      lastServerSeq: data.lastServerSeq.present
          ? data.lastServerSeq.value
          : this.lastServerSeq,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      dashboardSeeded: data.dashboardSeeded.present
          ? data.dashboardSeeded.value
          : this.dashboardSeeded,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('id: $id, ')
          ..write('lastServerSeq: $lastServerSeq, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('dashboardSeeded: $dashboardSeeded')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, lastServerSeq, lastSyncedAt, dashboardSeeded);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.id == this.id &&
          other.lastServerSeq == this.lastServerSeq &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.dashboardSeeded == this.dashboardSeeded);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<String> id;
  final Value<BigInt> lastServerSeq;
  final Value<BigInt?> lastSyncedAt;
  final Value<bool> dashboardSeeded;
  final Value<int> rowid;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.lastServerSeq = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.dashboardSeeded = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    this.lastServerSeq = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.dashboardSeeded = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  static Insertable<SyncStateData> custom({
    Expression<String>? id,
    Expression<BigInt>? lastServerSeq,
    Expression<BigInt>? lastSyncedAt,
    Expression<bool>? dashboardSeeded,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastServerSeq != null) 'last_server_seq': lastServerSeq,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (dashboardSeeded != null) 'dashboard_seeded': dashboardSeeded,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStateCompanion copyWith({
    Value<String>? id,
    Value<BigInt>? lastServerSeq,
    Value<BigInt?>? lastSyncedAt,
    Value<bool>? dashboardSeeded,
    Value<int>? rowid,
  }) {
    return SyncStateCompanion(
      id: id ?? this.id,
      lastServerSeq: lastServerSeq ?? this.lastServerSeq,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      dashboardSeeded: dashboardSeeded ?? this.dashboardSeeded,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (lastServerSeq.present) {
      map['last_server_seq'] = Variable<BigInt>(lastServerSeq.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<BigInt>(lastSyncedAt.value);
    }
    if (dashboardSeeded.present) {
      map['dashboard_seeded'] = Variable<bool>(dashboardSeeded.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('lastServerSeq: $lastServerSeq, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('dashboardSeeded: $dashboardSeeded, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TombstonesTable extends Tombstones
    with TableInfo<$TombstonesTable, Tombstone> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TombstonesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entityTableMeta = const VerificationMeta(
    'entityTable',
  );
  @override
  late final GeneratedColumn<String> entityTable = GeneratedColumn<String>(
    'entity_table',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<BigInt> deletedAt = GeneratedColumn<BigInt>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<BigInt> createdAt = GeneratedColumn<BigInt>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dirtyMeta = const VerificationMeta('dirty');
  @override
  late final GeneratedColumn<bool> dirty = GeneratedColumn<bool>(
    'dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    entityTable,
    entityId,
    deletedAt,
    createdAt,
    updatedAt,
    dirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tombstones';
  @override
  VerificationContext validateIntegrity(
    Insertable<Tombstone> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entity_table')) {
      context.handle(
        _entityTableMeta,
        entityTable.isAcceptableOrUnknown(
          data['entity_table']!,
          _entityTableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_entityTableMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('dirty')) {
      context.handle(
        _dirtyMeta,
        dirty.isAcceptableOrUnknown(data['dirty']!, _dirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entityTable, entityId};
  @override
  Tombstone map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Tombstone(
      entityTable: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_table'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}deleted_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      dirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dirty'],
      )!,
    );
  }

  @override
  $TombstonesTable createAlias(String alias) {
    return $TombstonesTable(attachedDatabase, alias);
  }
}

class Tombstone extends DataClass implements Insertable<Tombstone> {
  final String entityTable;
  final String entityId;
  final BigInt deletedAt;
  final BigInt createdAt;
  final BigInt updatedAt;
  final bool dirty;
  const Tombstone({
    required this.entityTable,
    required this.entityId,
    required this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.dirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entity_table'] = Variable<String>(entityTable);
    map['entity_id'] = Variable<String>(entityId);
    map['deleted_at'] = Variable<BigInt>(deletedAt);
    map['created_at'] = Variable<BigInt>(createdAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    map['dirty'] = Variable<bool>(dirty);
    return map;
  }

  TombstonesCompanion toCompanion(bool nullToAbsent) {
    return TombstonesCompanion(
      entityTable: Value(entityTable),
      entityId: Value(entityId),
      deletedAt: Value(deletedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      dirty: Value(dirty),
    );
  }

  factory Tombstone.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Tombstone(
      entityTable: serializer.fromJson<String>(json['entityTable']),
      entityId: serializer.fromJson<String>(json['entityId']),
      deletedAt: serializer.fromJson<BigInt>(json['deletedAt']),
      createdAt: serializer.fromJson<BigInt>(json['createdAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      dirty: serializer.fromJson<bool>(json['dirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entityTable': serializer.toJson<String>(entityTable),
      'entityId': serializer.toJson<String>(entityId),
      'deletedAt': serializer.toJson<BigInt>(deletedAt),
      'createdAt': serializer.toJson<BigInt>(createdAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'dirty': serializer.toJson<bool>(dirty),
    };
  }

  Tombstone copyWith({
    String? entityTable,
    String? entityId,
    BigInt? deletedAt,
    BigInt? createdAt,
    BigInt? updatedAt,
    bool? dirty,
  }) => Tombstone(
    entityTable: entityTable ?? this.entityTable,
    entityId: entityId ?? this.entityId,
    deletedAt: deletedAt ?? this.deletedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    dirty: dirty ?? this.dirty,
  );
  Tombstone copyWithCompanion(TombstonesCompanion data) {
    return Tombstone(
      entityTable: data.entityTable.present
          ? data.entityTable.value
          : this.entityTable,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      dirty: data.dirty.present ? data.dirty.value : this.dirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Tombstone(')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    entityTable,
    entityId,
    deletedAt,
    createdAt,
    updatedAt,
    dirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tombstone &&
          other.entityTable == this.entityTable &&
          other.entityId == this.entityId &&
          other.deletedAt == this.deletedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.dirty == this.dirty);
}

class TombstonesCompanion extends UpdateCompanion<Tombstone> {
  final Value<String> entityTable;
  final Value<String> entityId;
  final Value<BigInt> deletedAt;
  final Value<BigInt> createdAt;
  final Value<BigInt> updatedAt;
  final Value<bool> dirty;
  final Value<int> rowid;
  const TombstonesCompanion({
    this.entityTable = const Value.absent(),
    this.entityId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TombstonesCompanion.insert({
    required String entityTable,
    required String entityId,
    required BigInt deletedAt,
    required BigInt createdAt,
    required BigInt updatedAt,
    this.dirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : entityTable = Value(entityTable),
       entityId = Value(entityId),
       deletedAt = Value(deletedAt),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Tombstone> custom({
    Expression<String>? entityTable,
    Expression<String>? entityId,
    Expression<BigInt>? deletedAt,
    Expression<BigInt>? createdAt,
    Expression<BigInt>? updatedAt,
    Expression<bool>? dirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entityTable != null) 'entity_table': entityTable,
      if (entityId != null) 'entity_id': entityId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (dirty != null) 'dirty': dirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TombstonesCompanion copyWith({
    Value<String>? entityTable,
    Value<String>? entityId,
    Value<BigInt>? deletedAt,
    Value<BigInt>? createdAt,
    Value<BigInt>? updatedAt,
    Value<bool>? dirty,
    Value<int>? rowid,
  }) {
    return TombstonesCompanion(
      entityTable: entityTable ?? this.entityTable,
      entityId: entityId ?? this.entityId,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      dirty: dirty ?? this.dirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entityTable.present) {
      map['entity_table'] = Variable<String>(entityTable.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<BigInt>(deletedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<BigInt>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (dirty.present) {
      map['dirty'] = Variable<bool>(dirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TombstonesCompanion(')
          ..write('entityTable: $entityTable, ')
          ..write('entityId: $entityId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('dirty: $dirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VoiceSessionsTable extends VoiceSessions
    with TableInfo<$VoiceSessionsTable, VoiceSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
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
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<BigInt> startedAt = GeneratedColumn<BigInt>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<BigInt> updatedAt = GeneratedColumn<BigInt>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<BigInt> endedAt = GeneratedColumn<BigInt>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.bigInt,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endedExplicitlyMeta = const VerificationMeta(
    'endedExplicitly',
  );
  @override
  late final GeneratedColumn<bool> endedExplicitly = GeneratedColumn<bool>(
    'ended_explicitly',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("ended_explicitly" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _resumeHandleMeta = const VerificationMeta(
    'resumeHandle',
  );
  @override
  late final GeneratedColumn<String> resumeHandle = GeneratedColumn<String>(
    'resume_handle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resumeHandleUpdatedAtMeta =
      const VerificationMeta('resumeHandleUpdatedAt');
  @override
  late final GeneratedColumn<BigInt> resumeHandleUpdatedAt =
      GeneratedColumn<BigInt>(
        'resume_handle_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.bigInt,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _remoteEnabledMeta = const VerificationMeta(
    'remoteEnabled',
  );
  @override
  late final GeneratedColumn<bool> remoteEnabled = GeneratedColumn<bool>(
    'remote_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remote_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _remoteSyncedMeta = const VerificationMeta(
    'remoteSynced',
  );
  @override
  late final GeneratedColumn<bool> remoteSynced = GeneratedColumn<bool>(
    'remote_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remote_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    model,
    status,
    startedAt,
    updatedAt,
    endedAt,
    endedExplicitly,
    resumeHandle,
    resumeHandleUpdatedAt,
    remoteEnabled,
    remoteSynced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoiceSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('ended_explicitly')) {
      context.handle(
        _endedExplicitlyMeta,
        endedExplicitly.isAcceptableOrUnknown(
          data['ended_explicitly']!,
          _endedExplicitlyMeta,
        ),
      );
    }
    if (data.containsKey('resume_handle')) {
      context.handle(
        _resumeHandleMeta,
        resumeHandle.isAcceptableOrUnknown(
          data['resume_handle']!,
          _resumeHandleMeta,
        ),
      );
    }
    if (data.containsKey('resume_handle_updated_at')) {
      context.handle(
        _resumeHandleUpdatedAtMeta,
        resumeHandleUpdatedAt.isAcceptableOrUnknown(
          data['resume_handle_updated_at']!,
          _resumeHandleUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('remote_enabled')) {
      context.handle(
        _remoteEnabledMeta,
        remoteEnabled.isAcceptableOrUnknown(
          data['remote_enabled']!,
          _remoteEnabledMeta,
        ),
      );
    }
    if (data.containsKey('remote_synced')) {
      context.handle(
        _remoteSyncedMeta,
        remoteSynced.isAcceptableOrUnknown(
          data['remote_synced']!,
          _remoteSyncedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoiceSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}started_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}updated_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}ended_at'],
      ),
      endedExplicitly: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}ended_explicitly'],
      )!,
      resumeHandle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resume_handle'],
      ),
      resumeHandleUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}resume_handle_updated_at'],
      ),
      remoteEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remote_enabled'],
      )!,
      remoteSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remote_synced'],
      )!,
    );
  }

  @override
  $VoiceSessionsTable createAlias(String alias) {
    return $VoiceSessionsTable(attachedDatabase, alias);
  }
}

class VoiceSession extends DataClass implements Insertable<VoiceSession> {
  final String id;
  final String model;
  final String status;
  final BigInt startedAt;
  final BigInt updatedAt;
  final BigInt? endedAt;
  final bool endedExplicitly;
  final String? resumeHandle;
  final BigInt? resumeHandleUpdatedAt;
  final bool remoteEnabled;
  final bool remoteSynced;
  const VoiceSession({
    required this.id,
    required this.model,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    this.endedAt,
    required this.endedExplicitly,
    this.resumeHandle,
    this.resumeHandleUpdatedAt,
    required this.remoteEnabled,
    required this.remoteSynced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['model'] = Variable<String>(model);
    map['status'] = Variable<String>(status);
    map['started_at'] = Variable<BigInt>(startedAt);
    map['updated_at'] = Variable<BigInt>(updatedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<BigInt>(endedAt);
    }
    map['ended_explicitly'] = Variable<bool>(endedExplicitly);
    if (!nullToAbsent || resumeHandle != null) {
      map['resume_handle'] = Variable<String>(resumeHandle);
    }
    if (!nullToAbsent || resumeHandleUpdatedAt != null) {
      map['resume_handle_updated_at'] = Variable<BigInt>(resumeHandleUpdatedAt);
    }
    map['remote_enabled'] = Variable<bool>(remoteEnabled);
    map['remote_synced'] = Variable<bool>(remoteSynced);
    return map;
  }

  VoiceSessionsCompanion toCompanion(bool nullToAbsent) {
    return VoiceSessionsCompanion(
      id: Value(id),
      model: Value(model),
      status: Value(status),
      startedAt: Value(startedAt),
      updatedAt: Value(updatedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      endedExplicitly: Value(endedExplicitly),
      resumeHandle: resumeHandle == null && nullToAbsent
          ? const Value.absent()
          : Value(resumeHandle),
      resumeHandleUpdatedAt: resumeHandleUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(resumeHandleUpdatedAt),
      remoteEnabled: Value(remoteEnabled),
      remoteSynced: Value(remoteSynced),
    );
  }

  factory VoiceSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceSession(
      id: serializer.fromJson<String>(json['id']),
      model: serializer.fromJson<String>(json['model']),
      status: serializer.fromJson<String>(json['status']),
      startedAt: serializer.fromJson<BigInt>(json['startedAt']),
      updatedAt: serializer.fromJson<BigInt>(json['updatedAt']),
      endedAt: serializer.fromJson<BigInt?>(json['endedAt']),
      endedExplicitly: serializer.fromJson<bool>(json['endedExplicitly']),
      resumeHandle: serializer.fromJson<String?>(json['resumeHandle']),
      resumeHandleUpdatedAt: serializer.fromJson<BigInt?>(
        json['resumeHandleUpdatedAt'],
      ),
      remoteEnabled: serializer.fromJson<bool>(json['remoteEnabled']),
      remoteSynced: serializer.fromJson<bool>(json['remoteSynced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'model': serializer.toJson<String>(model),
      'status': serializer.toJson<String>(status),
      'startedAt': serializer.toJson<BigInt>(startedAt),
      'updatedAt': serializer.toJson<BigInt>(updatedAt),
      'endedAt': serializer.toJson<BigInt?>(endedAt),
      'endedExplicitly': serializer.toJson<bool>(endedExplicitly),
      'resumeHandle': serializer.toJson<String?>(resumeHandle),
      'resumeHandleUpdatedAt': serializer.toJson<BigInt?>(
        resumeHandleUpdatedAt,
      ),
      'remoteEnabled': serializer.toJson<bool>(remoteEnabled),
      'remoteSynced': serializer.toJson<bool>(remoteSynced),
    };
  }

  VoiceSession copyWith({
    String? id,
    String? model,
    String? status,
    BigInt? startedAt,
    BigInt? updatedAt,
    Value<BigInt?> endedAt = const Value.absent(),
    bool? endedExplicitly,
    Value<String?> resumeHandle = const Value.absent(),
    Value<BigInt?> resumeHandleUpdatedAt = const Value.absent(),
    bool? remoteEnabled,
    bool? remoteSynced,
  }) => VoiceSession(
    id: id ?? this.id,
    model: model ?? this.model,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    endedExplicitly: endedExplicitly ?? this.endedExplicitly,
    resumeHandle: resumeHandle.present ? resumeHandle.value : this.resumeHandle,
    resumeHandleUpdatedAt: resumeHandleUpdatedAt.present
        ? resumeHandleUpdatedAt.value
        : this.resumeHandleUpdatedAt,
    remoteEnabled: remoteEnabled ?? this.remoteEnabled,
    remoteSynced: remoteSynced ?? this.remoteSynced,
  );
  VoiceSession copyWithCompanion(VoiceSessionsCompanion data) {
    return VoiceSession(
      id: data.id.present ? data.id.value : this.id,
      model: data.model.present ? data.model.value : this.model,
      status: data.status.present ? data.status.value : this.status,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      endedExplicitly: data.endedExplicitly.present
          ? data.endedExplicitly.value
          : this.endedExplicitly,
      resumeHandle: data.resumeHandle.present
          ? data.resumeHandle.value
          : this.resumeHandle,
      resumeHandleUpdatedAt: data.resumeHandleUpdatedAt.present
          ? data.resumeHandleUpdatedAt.value
          : this.resumeHandleUpdatedAt,
      remoteEnabled: data.remoteEnabled.present
          ? data.remoteEnabled.value
          : this.remoteEnabled,
      remoteSynced: data.remoteSynced.present
          ? data.remoteSynced.value
          : this.remoteSynced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceSession(')
          ..write('id: $id, ')
          ..write('model: $model, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endedExplicitly: $endedExplicitly, ')
          ..write('resumeHandle: $resumeHandle, ')
          ..write('resumeHandleUpdatedAt: $resumeHandleUpdatedAt, ')
          ..write('remoteEnabled: $remoteEnabled, ')
          ..write('remoteSynced: $remoteSynced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    model,
    status,
    startedAt,
    updatedAt,
    endedAt,
    endedExplicitly,
    resumeHandle,
    resumeHandleUpdatedAt,
    remoteEnabled,
    remoteSynced,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceSession &&
          other.id == this.id &&
          other.model == this.model &&
          other.status == this.status &&
          other.startedAt == this.startedAt &&
          other.updatedAt == this.updatedAt &&
          other.endedAt == this.endedAt &&
          other.endedExplicitly == this.endedExplicitly &&
          other.resumeHandle == this.resumeHandle &&
          other.resumeHandleUpdatedAt == this.resumeHandleUpdatedAt &&
          other.remoteEnabled == this.remoteEnabled &&
          other.remoteSynced == this.remoteSynced);
}

class VoiceSessionsCompanion extends UpdateCompanion<VoiceSession> {
  final Value<String> id;
  final Value<String> model;
  final Value<String> status;
  final Value<BigInt> startedAt;
  final Value<BigInt> updatedAt;
  final Value<BigInt?> endedAt;
  final Value<bool> endedExplicitly;
  final Value<String?> resumeHandle;
  final Value<BigInt?> resumeHandleUpdatedAt;
  final Value<bool> remoteEnabled;
  final Value<bool> remoteSynced;
  final Value<int> rowid;
  const VoiceSessionsCompanion({
    this.id = const Value.absent(),
    this.model = const Value.absent(),
    this.status = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.endedExplicitly = const Value.absent(),
    this.resumeHandle = const Value.absent(),
    this.resumeHandleUpdatedAt = const Value.absent(),
    this.remoteEnabled = const Value.absent(),
    this.remoteSynced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VoiceSessionsCompanion.insert({
    required String id,
    required String model,
    required String status,
    required BigInt startedAt,
    required BigInt updatedAt,
    this.endedAt = const Value.absent(),
    this.endedExplicitly = const Value.absent(),
    this.resumeHandle = const Value.absent(),
    this.resumeHandleUpdatedAt = const Value.absent(),
    this.remoteEnabled = const Value.absent(),
    this.remoteSynced = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       model = Value(model),
       status = Value(status),
       startedAt = Value(startedAt),
       updatedAt = Value(updatedAt);
  static Insertable<VoiceSession> custom({
    Expression<String>? id,
    Expression<String>? model,
    Expression<String>? status,
    Expression<BigInt>? startedAt,
    Expression<BigInt>? updatedAt,
    Expression<BigInt>? endedAt,
    Expression<bool>? endedExplicitly,
    Expression<String>? resumeHandle,
    Expression<BigInt>? resumeHandleUpdatedAt,
    Expression<bool>? remoteEnabled,
    Expression<bool>? remoteSynced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (model != null) 'model': model,
      if (status != null) 'status': status,
      if (startedAt != null) 'started_at': startedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (endedExplicitly != null) 'ended_explicitly': endedExplicitly,
      if (resumeHandle != null) 'resume_handle': resumeHandle,
      if (resumeHandleUpdatedAt != null)
        'resume_handle_updated_at': resumeHandleUpdatedAt,
      if (remoteEnabled != null) 'remote_enabled': remoteEnabled,
      if (remoteSynced != null) 'remote_synced': remoteSynced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VoiceSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? model,
    Value<String>? status,
    Value<BigInt>? startedAt,
    Value<BigInt>? updatedAt,
    Value<BigInt?>? endedAt,
    Value<bool>? endedExplicitly,
    Value<String?>? resumeHandle,
    Value<BigInt?>? resumeHandleUpdatedAt,
    Value<bool>? remoteEnabled,
    Value<bool>? remoteSynced,
    Value<int>? rowid,
  }) {
    return VoiceSessionsCompanion(
      id: id ?? this.id,
      model: model ?? this.model,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      endedAt: endedAt ?? this.endedAt,
      endedExplicitly: endedExplicitly ?? this.endedExplicitly,
      resumeHandle: resumeHandle ?? this.resumeHandle,
      resumeHandleUpdatedAt:
          resumeHandleUpdatedAt ?? this.resumeHandleUpdatedAt,
      remoteEnabled: remoteEnabled ?? this.remoteEnabled,
      remoteSynced: remoteSynced ?? this.remoteSynced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<BigInt>(startedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<BigInt>(updatedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<BigInt>(endedAt.value);
    }
    if (endedExplicitly.present) {
      map['ended_explicitly'] = Variable<bool>(endedExplicitly.value);
    }
    if (resumeHandle.present) {
      map['resume_handle'] = Variable<String>(resumeHandle.value);
    }
    if (resumeHandleUpdatedAt.present) {
      map['resume_handle_updated_at'] = Variable<BigInt>(
        resumeHandleUpdatedAt.value,
      );
    }
    if (remoteEnabled.present) {
      map['remote_enabled'] = Variable<bool>(remoteEnabled.value);
    }
    if (remoteSynced.present) {
      map['remote_synced'] = Variable<bool>(remoteSynced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceSessionsCompanion(')
          ..write('id: $id, ')
          ..write('model: $model, ')
          ..write('status: $status, ')
          ..write('startedAt: $startedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('endedExplicitly: $endedExplicitly, ')
          ..write('resumeHandle: $resumeHandle, ')
          ..write('resumeHandleUpdatedAt: $resumeHandleUpdatedAt, ')
          ..write('remoteEnabled: $remoteEnabled, ')
          ..write('remoteSynced: $remoteSynced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VoiceSessionEventsTable extends VoiceSessionEvents
    with TableInfo<$VoiceSessionEventsTable, VoiceSessionEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceSessionEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<BigInt> occurredAt = GeneratedColumn<BigInt>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.bigInt,
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
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modalityMeta = const VerificationMeta(
    'modality',
  );
  @override
  late final GeneratedColumn<String> modality = GeneratedColumn<String>(
    'modality',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawJsonMeta = const VerificationMeta(
    'rawJson',
  );
  @override
  late final GeneratedColumn<String> rawJson = GeneratedColumn<String>(
    'raw_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _binaryDataMeta = const VerificationMeta(
    'binaryData',
  );
  @override
  late final GeneratedColumn<Uint8List> binaryData = GeneratedColumn<Uint8List>(
    'binary_data',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _binaryMimeTypeMeta = const VerificationMeta(
    'binaryMimeType',
  );
  @override
  late final GeneratedColumn<String> binaryMimeType = GeneratedColumn<String>(
    'binary_mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteSyncedMeta = const VerificationMeta(
    'remoteSynced',
  );
  @override
  late final GeneratedColumn<bool> remoteSynced = GeneratedColumn<bool>(
    'remote_synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("remote_synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    sequence,
    occurredAt,
    type,
    direction,
    modality,
    payloadJson,
    rawJson,
    binaryData,
    binaryMimeType,
    remoteSynced,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_session_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoiceSessionEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('modality')) {
      context.handle(
        _modalityMeta,
        modality.isAcceptableOrUnknown(data['modality']!, _modalityMeta),
      );
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('raw_json')) {
      context.handle(
        _rawJsonMeta,
        rawJson.isAcceptableOrUnknown(data['raw_json']!, _rawJsonMeta),
      );
    }
    if (data.containsKey('binary_data')) {
      context.handle(
        _binaryDataMeta,
        binaryData.isAcceptableOrUnknown(data['binary_data']!, _binaryDataMeta),
      );
    }
    if (data.containsKey('binary_mime_type')) {
      context.handle(
        _binaryMimeTypeMeta,
        binaryMimeType.isAcceptableOrUnknown(
          data['binary_mime_type']!,
          _binaryMimeTypeMeta,
        ),
      );
    }
    if (data.containsKey('remote_synced')) {
      context.handle(
        _remoteSyncedMeta,
        remoteSynced.isAcceptableOrUnknown(
          data['remote_synced']!,
          _remoteSyncedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, sequence},
  ];
  @override
  VoiceSessionEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceSessionEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.bigInt,
        data['${effectivePrefix}occurred_at'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      modality: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}modality'],
      ),
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      rawJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_json'],
      ),
      binaryData: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}binary_data'],
      ),
      binaryMimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}binary_mime_type'],
      ),
      remoteSynced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}remote_synced'],
      )!,
    );
  }

  @override
  $VoiceSessionEventsTable createAlias(String alias) {
    return $VoiceSessionEventsTable(attachedDatabase, alias);
  }
}

class VoiceSessionEvent extends DataClass
    implements Insertable<VoiceSessionEvent> {
  final String id;
  final String sessionId;
  final int sequence;
  final BigInt occurredAt;
  final String type;
  final String direction;
  final String? modality;
  final String payloadJson;
  final String? rawJson;
  final Uint8List? binaryData;
  final String? binaryMimeType;
  final bool remoteSynced;
  const VoiceSessionEvent({
    required this.id,
    required this.sessionId,
    required this.sequence,
    required this.occurredAt,
    required this.type,
    required this.direction,
    this.modality,
    required this.payloadJson,
    this.rawJson,
    this.binaryData,
    this.binaryMimeType,
    required this.remoteSynced,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['sequence'] = Variable<int>(sequence);
    map['occurred_at'] = Variable<BigInt>(occurredAt);
    map['type'] = Variable<String>(type);
    map['direction'] = Variable<String>(direction);
    if (!nullToAbsent || modality != null) {
      map['modality'] = Variable<String>(modality);
    }
    map['payload_json'] = Variable<String>(payloadJson);
    if (!nullToAbsent || rawJson != null) {
      map['raw_json'] = Variable<String>(rawJson);
    }
    if (!nullToAbsent || binaryData != null) {
      map['binary_data'] = Variable<Uint8List>(binaryData);
    }
    if (!nullToAbsent || binaryMimeType != null) {
      map['binary_mime_type'] = Variable<String>(binaryMimeType);
    }
    map['remote_synced'] = Variable<bool>(remoteSynced);
    return map;
  }

  VoiceSessionEventsCompanion toCompanion(bool nullToAbsent) {
    return VoiceSessionEventsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      sequence: Value(sequence),
      occurredAt: Value(occurredAt),
      type: Value(type),
      direction: Value(direction),
      modality: modality == null && nullToAbsent
          ? const Value.absent()
          : Value(modality),
      payloadJson: Value(payloadJson),
      rawJson: rawJson == null && nullToAbsent
          ? const Value.absent()
          : Value(rawJson),
      binaryData: binaryData == null && nullToAbsent
          ? const Value.absent()
          : Value(binaryData),
      binaryMimeType: binaryMimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(binaryMimeType),
      remoteSynced: Value(remoteSynced),
    );
  }

  factory VoiceSessionEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceSessionEvent(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      occurredAt: serializer.fromJson<BigInt>(json['occurredAt']),
      type: serializer.fromJson<String>(json['type']),
      direction: serializer.fromJson<String>(json['direction']),
      modality: serializer.fromJson<String?>(json['modality']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      rawJson: serializer.fromJson<String?>(json['rawJson']),
      binaryData: serializer.fromJson<Uint8List?>(json['binaryData']),
      binaryMimeType: serializer.fromJson<String?>(json['binaryMimeType']),
      remoteSynced: serializer.fromJson<bool>(json['remoteSynced']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'sequence': serializer.toJson<int>(sequence),
      'occurredAt': serializer.toJson<BigInt>(occurredAt),
      'type': serializer.toJson<String>(type),
      'direction': serializer.toJson<String>(direction),
      'modality': serializer.toJson<String?>(modality),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'rawJson': serializer.toJson<String?>(rawJson),
      'binaryData': serializer.toJson<Uint8List?>(binaryData),
      'binaryMimeType': serializer.toJson<String?>(binaryMimeType),
      'remoteSynced': serializer.toJson<bool>(remoteSynced),
    };
  }

  VoiceSessionEvent copyWith({
    String? id,
    String? sessionId,
    int? sequence,
    BigInt? occurredAt,
    String? type,
    String? direction,
    Value<String?> modality = const Value.absent(),
    String? payloadJson,
    Value<String?> rawJson = const Value.absent(),
    Value<Uint8List?> binaryData = const Value.absent(),
    Value<String?> binaryMimeType = const Value.absent(),
    bool? remoteSynced,
  }) => VoiceSessionEvent(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    sequence: sequence ?? this.sequence,
    occurredAt: occurredAt ?? this.occurredAt,
    type: type ?? this.type,
    direction: direction ?? this.direction,
    modality: modality.present ? modality.value : this.modality,
    payloadJson: payloadJson ?? this.payloadJson,
    rawJson: rawJson.present ? rawJson.value : this.rawJson,
    binaryData: binaryData.present ? binaryData.value : this.binaryData,
    binaryMimeType: binaryMimeType.present
        ? binaryMimeType.value
        : this.binaryMimeType,
    remoteSynced: remoteSynced ?? this.remoteSynced,
  );
  VoiceSessionEvent copyWithCompanion(VoiceSessionEventsCompanion data) {
    return VoiceSessionEvent(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      type: data.type.present ? data.type.value : this.type,
      direction: data.direction.present ? data.direction.value : this.direction,
      modality: data.modality.present ? data.modality.value : this.modality,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      rawJson: data.rawJson.present ? data.rawJson.value : this.rawJson,
      binaryData: data.binaryData.present
          ? data.binaryData.value
          : this.binaryData,
      binaryMimeType: data.binaryMimeType.present
          ? data.binaryMimeType.value
          : this.binaryMimeType,
      remoteSynced: data.remoteSynced.present
          ? data.remoteSynced.value
          : this.remoteSynced,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceSessionEvent(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('sequence: $sequence, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('type: $type, ')
          ..write('direction: $direction, ')
          ..write('modality: $modality, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('binaryData: $binaryData, ')
          ..write('binaryMimeType: $binaryMimeType, ')
          ..write('remoteSynced: $remoteSynced')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    sequence,
    occurredAt,
    type,
    direction,
    modality,
    payloadJson,
    rawJson,
    $driftBlobEquality.hash(binaryData),
    binaryMimeType,
    remoteSynced,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceSessionEvent &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.sequence == this.sequence &&
          other.occurredAt == this.occurredAt &&
          other.type == this.type &&
          other.direction == this.direction &&
          other.modality == this.modality &&
          other.payloadJson == this.payloadJson &&
          other.rawJson == this.rawJson &&
          $driftBlobEquality.equals(other.binaryData, this.binaryData) &&
          other.binaryMimeType == this.binaryMimeType &&
          other.remoteSynced == this.remoteSynced);
}

class VoiceSessionEventsCompanion extends UpdateCompanion<VoiceSessionEvent> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<int> sequence;
  final Value<BigInt> occurredAt;
  final Value<String> type;
  final Value<String> direction;
  final Value<String?> modality;
  final Value<String> payloadJson;
  final Value<String?> rawJson;
  final Value<Uint8List?> binaryData;
  final Value<String?> binaryMimeType;
  final Value<bool> remoteSynced;
  final Value<int> rowid;
  const VoiceSessionEventsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.type = const Value.absent(),
    this.direction = const Value.absent(),
    this.modality = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.rawJson = const Value.absent(),
    this.binaryData = const Value.absent(),
    this.binaryMimeType = const Value.absent(),
    this.remoteSynced = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VoiceSessionEventsCompanion.insert({
    required String id,
    required String sessionId,
    required int sequence,
    required BigInt occurredAt,
    required String type,
    required String direction,
    this.modality = const Value.absent(),
    required String payloadJson,
    this.rawJson = const Value.absent(),
    this.binaryData = const Value.absent(),
    this.binaryMimeType = const Value.absent(),
    this.remoteSynced = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       sequence = Value(sequence),
       occurredAt = Value(occurredAt),
       type = Value(type),
       direction = Value(direction),
       payloadJson = Value(payloadJson);
  static Insertable<VoiceSessionEvent> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<int>? sequence,
    Expression<BigInt>? occurredAt,
    Expression<String>? type,
    Expression<String>? direction,
    Expression<String>? modality,
    Expression<String>? payloadJson,
    Expression<String>? rawJson,
    Expression<Uint8List>? binaryData,
    Expression<String>? binaryMimeType,
    Expression<bool>? remoteSynced,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (sequence != null) 'sequence': sequence,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (type != null) 'type': type,
      if (direction != null) 'direction': direction,
      if (modality != null) 'modality': modality,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (rawJson != null) 'raw_json': rawJson,
      if (binaryData != null) 'binary_data': binaryData,
      if (binaryMimeType != null) 'binary_mime_type': binaryMimeType,
      if (remoteSynced != null) 'remote_synced': remoteSynced,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VoiceSessionEventsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<int>? sequence,
    Value<BigInt>? occurredAt,
    Value<String>? type,
    Value<String>? direction,
    Value<String?>? modality,
    Value<String>? payloadJson,
    Value<String?>? rawJson,
    Value<Uint8List?>? binaryData,
    Value<String?>? binaryMimeType,
    Value<bool>? remoteSynced,
    Value<int>? rowid,
  }) {
    return VoiceSessionEventsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      sequence: sequence ?? this.sequence,
      occurredAt: occurredAt ?? this.occurredAt,
      type: type ?? this.type,
      direction: direction ?? this.direction,
      modality: modality ?? this.modality,
      payloadJson: payloadJson ?? this.payloadJson,
      rawJson: rawJson ?? this.rawJson,
      binaryData: binaryData ?? this.binaryData,
      binaryMimeType: binaryMimeType ?? this.binaryMimeType,
      remoteSynced: remoteSynced ?? this.remoteSynced,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<BigInt>(occurredAt.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (modality.present) {
      map['modality'] = Variable<String>(modality.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (rawJson.present) {
      map['raw_json'] = Variable<String>(rawJson.value);
    }
    if (binaryData.present) {
      map['binary_data'] = Variable<Uint8List>(binaryData.value);
    }
    if (binaryMimeType.present) {
      map['binary_mime_type'] = Variable<String>(binaryMimeType.value);
    }
    if (remoteSynced.present) {
      map['remote_synced'] = Variable<bool>(remoteSynced.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceSessionEventsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('sequence: $sequence, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('type: $type, ')
          ..write('direction: $direction, ')
          ..write('modality: $modality, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('rawJson: $rawJson, ')
          ..write('binaryData: $binaryData, ')
          ..write('binaryMimeType: $binaryMimeType, ')
          ..write('remoteSynced: $remoteSynced, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $AccountsTable accounts = $AccountsTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $TransactionsTable transactions = $TransactionsTable(this);
  late final $TagsTable tags = $TagsTable(this);
  late final $TransactionTagsTable transactionTags = $TransactionTagsTable(
    this,
  );
  late final $SavedFiltersTable savedFilters = $SavedFiltersTable(this);
  late final $DashboardWidgetsTable dashboardWidgets = $DashboardWidgetsTable(
    this,
  );
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $TombstonesTable tombstones = $TombstonesTable(this);
  late final $VoiceSessionsTable voiceSessions = $VoiceSessionsTable(this);
  late final $VoiceSessionEventsTable voiceSessionEvents =
      $VoiceSessionEventsTable(this);
  late final Index accountsArchived = Index(
    'accounts_archived',
    'CREATE INDEX accounts_archived ON accounts (is_archived)',
  );
  late final Index accountsUpdatedAt = Index(
    'accounts_updated_at',
    'CREATE INDEX accounts_updated_at ON accounts (updated_at)',
  );
  late final Index accountsNeedsSync = Index(
    'accounts_needs_sync',
    'CREATE INDEX accounts_needs_sync ON accounts (updated_at) WHERE dirty = 1',
  );
  late final Index categoriesArchived = Index(
    'categories_archived',
    'CREATE INDEX categories_archived ON categories (is_archived)',
  );
  late final Index categoriesUpdatedAt = Index(
    'categories_updated_at',
    'CREATE INDEX categories_updated_at ON categories (updated_at)',
  );
  late final Index categoriesNeedsSync = Index(
    'categories_needs_sync',
    'CREATE INDEX categories_needs_sync ON categories (updated_at) WHERE dirty = 1',
  );
  late final Index transactionsAccountId = Index(
    'transactions_account_id',
    'CREATE INDEX transactions_account_id ON transactions (account_id)',
  );
  late final Index transactionsCategoryId = Index(
    'transactions_category_id',
    'CREATE INDEX transactions_category_id ON transactions (category_id)',
  );
  late final Index transactionsToAccountId = Index(
    'transactions_to_account_id',
    'CREATE INDEX transactions_to_account_id ON transactions (to_account_id)',
  );
  late final Index transactionsDate = Index(
    'transactions_date',
    'CREATE INDEX transactions_date ON transactions (date)',
  );
  late final Index transactionsStatus = Index(
    'transactions_status',
    'CREATE INDEX transactions_status ON transactions (status)',
  );
  late final Index transactionsType = Index(
    'transactions_type',
    'CREATE INDEX transactions_type ON transactions (type)',
  );
  late final Index transactionsArchived = Index(
    'transactions_archived',
    'CREATE INDEX transactions_archived ON transactions (is_archived)',
  );
  late final Index transactionsUpdatedAt = Index(
    'transactions_updated_at',
    'CREATE INDEX transactions_updated_at ON transactions (updated_at)',
  );
  late final Index transactionsAccountIdDate = Index(
    'transactions_account_id_date',
    'CREATE INDEX transactions_account_id_date ON transactions (account_id, date)',
  );
  late final Index transactionsCategoryIdDate = Index(
    'transactions_category_id_date',
    'CREATE INDEX transactions_category_id_date ON transactions (category_id, date)',
  );
  late final Index transactionsNeedsSync = Index(
    'transactions_needs_sync',
    'CREATE INDEX transactions_needs_sync ON transactions (updated_at) WHERE dirty = 1',
  );
  late final Index tagsParentId = Index(
    'tags_parent_id',
    'CREATE INDEX tags_parent_id ON tags (parent_id)',
  );
  late final Index tagsArchived = Index(
    'tags_archived',
    'CREATE INDEX tags_archived ON tags (is_archived)',
  );
  late final Index tagsUpdatedAt = Index(
    'tags_updated_at',
    'CREATE INDEX tags_updated_at ON tags (updated_at)',
  );
  late final Index tagsNeedsSync = Index(
    'tags_needs_sync',
    'CREATE INDEX tags_needs_sync ON tags (updated_at) WHERE dirty = 1',
  );
  late final Index transactionTagsTransactionId = Index(
    'transaction_tags_transaction_id',
    'CREATE INDEX transaction_tags_transaction_id ON transaction_tags (transaction_id)',
  );
  late final Index transactionTagsTagId = Index(
    'transaction_tags_tag_id',
    'CREATE INDEX transaction_tags_tag_id ON transaction_tags (tag_id)',
  );
  late final Index transactionTagsUpdatedAt = Index(
    'transaction_tags_updated_at',
    'CREATE INDEX transaction_tags_updated_at ON transaction_tags (updated_at)',
  );
  late final Index transactionTagsNeedsSync = Index(
    'transaction_tags_needs_sync',
    'CREATE INDEX transaction_tags_needs_sync ON transaction_tags (updated_at) WHERE dirty = 1',
  );
  late final Index savedFiltersArchived = Index(
    'saved_filters_archived',
    'CREATE INDEX saved_filters_archived ON saved_filters (is_archived)',
  );
  late final Index savedFiltersUpdatedAt = Index(
    'saved_filters_updated_at',
    'CREATE INDEX saved_filters_updated_at ON saved_filters (updated_at)',
  );
  late final Index savedFiltersNeedsSync = Index(
    'saved_filters_needs_sync',
    'CREATE INDEX saved_filters_needs_sync ON saved_filters (updated_at) WHERE dirty = 1',
  );
  late final Index dashboardWidgetsPosition = Index(
    'dashboard_widgets_position',
    'CREATE INDEX dashboard_widgets_position ON dashboard_widgets (position)',
  );
  late final Index dashboardWidgetsArchived = Index(
    'dashboard_widgets_archived',
    'CREATE INDEX dashboard_widgets_archived ON dashboard_widgets (is_archived)',
  );
  late final Index dashboardWidgetsUpdatedAt = Index(
    'dashboard_widgets_updated_at',
    'CREATE INDEX dashboard_widgets_updated_at ON dashboard_widgets (updated_at)',
  );
  late final Index dashboardWidgetsNeedsSync = Index(
    'dashboard_widgets_needs_sync',
    'CREATE INDEX dashboard_widgets_needs_sync ON dashboard_widgets (updated_at) WHERE dirty = 1',
  );
  late final Index tombstonesEntityTable = Index(
    'tombstones_entity_table',
    'CREATE INDEX tombstones_entity_table ON tombstones (entity_table)',
  );
  late final Index tombstonesUpdatedAt = Index(
    'tombstones_updated_at',
    'CREATE INDEX tombstones_updated_at ON tombstones (updated_at)',
  );
  late final Index tombstonesNeedsSync = Index(
    'tombstones_needs_sync',
    'CREATE INDEX tombstones_needs_sync ON tombstones (updated_at) WHERE dirty = 1',
  );
  late final Index voiceSessionsStatus = Index(
    'voice_sessions_status',
    'CREATE INDEX voice_sessions_status ON voice_sessions (status)',
  );
  late final Index voiceSessionsUpdatedAt = Index(
    'voice_sessions_updated_at',
    'CREATE INDEX voice_sessions_updated_at ON voice_sessions (updated_at)',
  );
  late final Index voiceEventsSessionId = Index(
    'voice_events_session_id',
    'CREATE INDEX voice_events_session_id ON voice_session_events (session_id)',
  );
  late final Index voiceEventsRemoteSynced = Index(
    'voice_events_remote_synced',
    'CREATE INDEX voice_events_remote_synced ON voice_session_events (remote_synced)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    accounts,
    categories,
    transactions,
    tags,
    transactionTags,
    savedFilters,
    dashboardWidgets,
    syncState,
    tombstones,
    voiceSessions,
    voiceSessionEvents,
    accountsArchived,
    accountsUpdatedAt,
    accountsNeedsSync,
    categoriesArchived,
    categoriesUpdatedAt,
    categoriesNeedsSync,
    transactionsAccountId,
    transactionsCategoryId,
    transactionsToAccountId,
    transactionsDate,
    transactionsStatus,
    transactionsType,
    transactionsArchived,
    transactionsUpdatedAt,
    transactionsAccountIdDate,
    transactionsCategoryIdDate,
    transactionsNeedsSync,
    tagsParentId,
    tagsArchived,
    tagsUpdatedAt,
    tagsNeedsSync,
    transactionTagsTransactionId,
    transactionTagsTagId,
    transactionTagsUpdatedAt,
    transactionTagsNeedsSync,
    savedFiltersArchived,
    savedFiltersUpdatedAt,
    savedFiltersNeedsSync,
    dashboardWidgetsPosition,
    dashboardWidgetsArchived,
    dashboardWidgetsUpdatedAt,
    dashboardWidgetsNeedsSync,
    tombstonesEntityTable,
    tombstonesUpdatedAt,
    tombstonesNeedsSync,
    voiceSessionsStatus,
    voiceSessionsUpdatedAt,
    voiceEventsSessionId,
    voiceEventsRemoteSynced,
  ];
}

typedef $$AccountsTableCreateCompanionBuilder =
    AccountsCompanion Function({
      required String id,
      required String name,
      required String currency,
      Value<String?> description,
      Value<String> color,
      Value<String> icon,
      Value<bool> archived,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$AccountsTableUpdateCompanionBuilder =
    AccountsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> currency,
      Value<String?> description,
      Value<String> color,
      Value<String> icon,
      Value<bool> archived,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$AccountsTableFilterComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AccountsTableOrderingComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AccountsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AccountsTable> {
  $$AccountsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$AccountsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AccountsTable,
          Account,
          $$AccountsTableFilterComposer,
          $$AccountsTableOrderingComposer,
          $$AccountsTableAnnotationComposer,
          $$AccountsTableCreateCompanionBuilder,
          $$AccountsTableUpdateCompanionBuilder,
          (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
          Account,
          PrefetchHooks Function()
        > {
  $$AccountsTableTableManager(_$AppDatabase db, $AccountsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AccountsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AccountsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AccountsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion(
                id: id,
                name: name,
                currency: currency,
                description: description,
                color: color,
                icon: icon,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String currency,
                Value<String?> description = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AccountsCompanion.insert(
                id: id,
                name: name,
                currency: currency,
                description: description,
                color: color,
                icon: icon,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AccountsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AccountsTable,
      Account,
      $$AccountsTableFilterComposer,
      $$AccountsTableOrderingComposer,
      $$AccountsTableAnnotationComposer,
      $$AccountsTableCreateCompanionBuilder,
      $$AccountsTableUpdateCompanionBuilder,
      (Account, BaseReferences<_$AppDatabase, $AccountsTable, Account>),
      Account,
      PrefetchHooks Function()
    >;
typedef $$CategoriesTableCreateCompanionBuilder =
    CategoriesCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      Value<String> color,
      Value<String> icon,
      Value<bool> archived,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$CategoriesTableUpdateCompanionBuilder =
    CategoriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<String> color,
      Value<String> icon,
      Value<bool> archived,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get icon => $composableBuilder(
    column: $table.icon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<String> get icon =>
      $composableBuilder(column: $table.icon, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          Category,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
          Category,
          PrefetchHooks Function()
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                name: name,
                description: description,
                color: color,
                icon: icon,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<String> icon = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                name: name,
                description: description,
                color: color,
                icon: icon,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      Category,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (Category, BaseReferences<_$AppDatabase, $CategoriesTable, Category>),
      Category,
      PrefetchHooks Function()
    >;
typedef $$TransactionsTableCreateCompanionBuilder =
    TransactionsCompanion Function({
      required String id,
      required String type,
      required String name,
      Value<String?> description,
      required String status,
      required BigInt date,
      Value<TransactionTimeStatus> timeStatus,
      required String accountId,
      required String categoryId,
      required BigInt amount,
      required String currency,
      Value<bool> dateConfirmed,
      Value<String?> toAccountId,
      Value<BigInt?> toAmount,
      Value<String?> toCurrency,
      Value<double?> exchangeRate,
      Value<BigInt?> balanceAfter,
      Value<bool> archived,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$TransactionsTableUpdateCompanionBuilder =
    TransactionsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String> name,
      Value<String?> description,
      Value<String> status,
      Value<BigInt> date,
      Value<TransactionTimeStatus> timeStatus,
      Value<String> accountId,
      Value<String> categoryId,
      Value<BigInt> amount,
      Value<String> currency,
      Value<bool> dateConfirmed,
      Value<String?> toAccountId,
      Value<BigInt?> toAmount,
      Value<String?> toCurrency,
      Value<double?> exchangeRate,
      Value<BigInt?> balanceAfter,
      Value<bool> archived,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$TransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    TransactionTimeStatus,
    TransactionTimeStatus,
    String
  >
  get timeStatus => $composableBuilder(
    column: $table.timeStatus,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dateConfirmed => $composableBuilder(
    column: $table.dateConfirmed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toAccountId => $composableBuilder(
    column: $table.toAccountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get toAmount => $composableBuilder(
    column: $table.toAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toCurrency => $composableBuilder(
    column: $table.toCurrency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get exchangeRate => $composableBuilder(
    column: $table.exchangeRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeStatus => $composableBuilder(
    column: $table.timeStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dateConfirmed => $composableBuilder(
    column: $table.dateConfirmed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toAccountId => $composableBuilder(
    column: $table.toAccountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get toAmount => $composableBuilder(
    column: $table.toAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toCurrency => $composableBuilder(
    column: $table.toCurrency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get exchangeRate => $composableBuilder(
    column: $table.exchangeRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionsTable> {
  $$TransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<BigInt> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TransactionTimeStatus, String>
  get timeStatus => $composableBuilder(
    column: $table.timeStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<BigInt> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<bool> get dateConfirmed => $composableBuilder(
    column: $table.dateConfirmed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get toAccountId => $composableBuilder(
    column: $table.toAccountId,
    builder: (column) => column,
  );

  GeneratedColumn<BigInt> get toAmount =>
      $composableBuilder(column: $table.toAmount, builder: (column) => column);

  GeneratedColumn<String> get toCurrency => $composableBuilder(
    column: $table.toCurrency,
    builder: (column) => column,
  );

  GeneratedColumn<double> get exchangeRate => $composableBuilder(
    column: $table.exchangeRate,
    builder: (column) => column,
  );

  GeneratedColumn<BigInt> get balanceAfter => $composableBuilder(
    column: $table.balanceAfter,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$TransactionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionsTable,
          Transaction,
          $$TransactionsTableFilterComposer,
          $$TransactionsTableOrderingComposer,
          $$TransactionsTableAnnotationComposer,
          $$TransactionsTableCreateCompanionBuilder,
          $$TransactionsTableUpdateCompanionBuilder,
          (
            Transaction,
            BaseReferences<_$AppDatabase, $TransactionsTable, Transaction>,
          ),
          Transaction,
          PrefetchHooks Function()
        > {
  $$TransactionsTableTableManager(_$AppDatabase db, $TransactionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<BigInt> date = const Value.absent(),
                Value<TransactionTimeStatus> timeStatus = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<BigInt> amount = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<bool> dateConfirmed = const Value.absent(),
                Value<String?> toAccountId = const Value.absent(),
                Value<BigInt?> toAmount = const Value.absent(),
                Value<String?> toCurrency = const Value.absent(),
                Value<double?> exchangeRate = const Value.absent(),
                Value<BigInt?> balanceAfter = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion(
                id: id,
                type: type,
                name: name,
                description: description,
                status: status,
                date: date,
                timeStatus: timeStatus,
                accountId: accountId,
                categoryId: categoryId,
                amount: amount,
                currency: currency,
                dateConfirmed: dateConfirmed,
                toAccountId: toAccountId,
                toAmount: toAmount,
                toCurrency: toCurrency,
                exchangeRate: exchangeRate,
                balanceAfter: balanceAfter,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                required String name,
                Value<String?> description = const Value.absent(),
                required String status,
                required BigInt date,
                Value<TransactionTimeStatus> timeStatus = const Value.absent(),
                required String accountId,
                required String categoryId,
                required BigInt amount,
                required String currency,
                Value<bool> dateConfirmed = const Value.absent(),
                Value<String?> toAccountId = const Value.absent(),
                Value<BigInt?> toAmount = const Value.absent(),
                Value<String?> toCurrency = const Value.absent(),
                Value<double?> exchangeRate = const Value.absent(),
                Value<BigInt?> balanceAfter = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionsCompanion.insert(
                id: id,
                type: type,
                name: name,
                description: description,
                status: status,
                date: date,
                timeStatus: timeStatus,
                accountId: accountId,
                categoryId: categoryId,
                amount: amount,
                currency: currency,
                dateConfirmed: dateConfirmed,
                toAccountId: toAccountId,
                toAmount: toAmount,
                toCurrency: toCurrency,
                exchangeRate: exchangeRate,
                balanceAfter: balanceAfter,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionsTable,
      Transaction,
      $$TransactionsTableFilterComposer,
      $$TransactionsTableOrderingComposer,
      $$TransactionsTableAnnotationComposer,
      $$TransactionsTableCreateCompanionBuilder,
      $$TransactionsTableUpdateCompanionBuilder,
      (
        Transaction,
        BaseReferences<_$AppDatabase, $TransactionsTable, Transaction>,
      ),
      Transaction,
      PrefetchHooks Function()
    >;
typedef $$TagsTableCreateCompanionBuilder =
    TagsCompanion Function({
      required String id,
      required String name,
      Value<String?> description,
      Value<String?> parentId,
      Value<String> color,
      Value<bool> archived,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$TagsTableUpdateCompanionBuilder =
    TagsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> description,
      Value<String?> parentId,
      Value<String> color,
      Value<bool> archived,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$TagsTableFilterComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TagsTableOrderingComposer extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentId => $composableBuilder(
    column: $table.parentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TagsTable> {
  $$TagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get parentId =>
      $composableBuilder(column: $table.parentId, builder: (column) => column);

  GeneratedColumn<String> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$TagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TagsTable,
          Tag,
          $$TagsTableFilterComposer,
          $$TagsTableOrderingComposer,
          $$TagsTableAnnotationComposer,
          $$TagsTableCreateCompanionBuilder,
          $$TagsTableUpdateCompanionBuilder,
          (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
          Tag,
          PrefetchHooks Function()
        > {
  $$TagsTableTableManager(_$AppDatabase db, $TagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion(
                id: id,
                name: name,
                description: description,
                parentId: parentId,
                color: color,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> parentId = const Value.absent(),
                Value<String> color = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TagsCompanion.insert(
                id: id,
                name: name,
                description: description,
                parentId: parentId,
                color: color,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TagsTable,
      Tag,
      $$TagsTableFilterComposer,
      $$TagsTableOrderingComposer,
      $$TagsTableAnnotationComposer,
      $$TagsTableCreateCompanionBuilder,
      $$TagsTableUpdateCompanionBuilder,
      (Tag, BaseReferences<_$AppDatabase, $TagsTable, Tag>),
      Tag,
      PrefetchHooks Function()
    >;
typedef $$TransactionTagsTableCreateCompanionBuilder =
    TransactionTagsCompanion Function({
      required String id,
      required String transactionId,
      required String tagId,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$TransactionTagsTableUpdateCompanionBuilder =
    TransactionTagsCompanion Function({
      Value<String> id,
      Value<String> transactionId,
      Value<String> tagId,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$TransactionTagsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionTagsTable> {
  $$TransactionTagsTableFilterComposer({
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

  ColumnFilters<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransactionTagsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionTagsTable> {
  $$TransactionTagsTableOrderingComposer({
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

  ColumnOrderings<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagId => $composableBuilder(
    column: $table.tagId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransactionTagsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionTagsTable> {
  $$TransactionTagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tagId =>
      $composableBuilder(column: $table.tagId, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$TransactionTagsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionTagsTable,
          TransactionTag,
          $$TransactionTagsTableFilterComposer,
          $$TransactionTagsTableOrderingComposer,
          $$TransactionTagsTableAnnotationComposer,
          $$TransactionTagsTableCreateCompanionBuilder,
          $$TransactionTagsTableUpdateCompanionBuilder,
          (
            TransactionTag,
            BaseReferences<
              _$AppDatabase,
              $TransactionTagsTable,
              TransactionTag
            >,
          ),
          TransactionTag,
          PrefetchHooks Function()
        > {
  $$TransactionTagsTableTableManager(
    _$AppDatabase db,
    $TransactionTagsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionTagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionTagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionTagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> transactionId = const Value.absent(),
                Value<String> tagId = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionTagsCompanion(
                id: id,
                transactionId: transactionId,
                tagId: tagId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String transactionId,
                required String tagId,
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionTagsCompanion.insert(
                id: id,
                transactionId: transactionId,
                tagId: tagId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransactionTagsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionTagsTable,
      TransactionTag,
      $$TransactionTagsTableFilterComposer,
      $$TransactionTagsTableOrderingComposer,
      $$TransactionTagsTableAnnotationComposer,
      $$TransactionTagsTableCreateCompanionBuilder,
      $$TransactionTagsTableUpdateCompanionBuilder,
      (
        TransactionTag,
        BaseReferences<_$AppDatabase, $TransactionTagsTable, TransactionTag>,
      ),
      TransactionTag,
      PrefetchHooks Function()
    >;
typedef $$SavedFiltersTableCreateCompanionBuilder =
    SavedFiltersCompanion Function({
      required String id,
      required String name,
      required String config,
      Value<bool> archived,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$SavedFiltersTableUpdateCompanionBuilder =
    SavedFiltersCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> config,
      Value<bool> archived,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$SavedFiltersTableFilterComposer
    extends Composer<_$AppDatabase, $SavedFiltersTable> {
  $$SavedFiltersTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedFiltersTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedFiltersTable> {
  $$SavedFiltersTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get config => $composableBuilder(
    column: $table.config,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedFiltersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedFiltersTable> {
  $$SavedFiltersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get config =>
      $composableBuilder(column: $table.config, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$SavedFiltersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedFiltersTable,
          SavedFilter,
          $$SavedFiltersTableFilterComposer,
          $$SavedFiltersTableOrderingComposer,
          $$SavedFiltersTableAnnotationComposer,
          $$SavedFiltersTableCreateCompanionBuilder,
          $$SavedFiltersTableUpdateCompanionBuilder,
          (
            SavedFilter,
            BaseReferences<_$AppDatabase, $SavedFiltersTable, SavedFilter>,
          ),
          SavedFilter,
          PrefetchHooks Function()
        > {
  $$SavedFiltersTableTableManager(_$AppDatabase db, $SavedFiltersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedFiltersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedFiltersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedFiltersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> config = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedFiltersCompanion(
                id: id,
                name: name,
                config: config,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String config,
                Value<bool> archived = const Value.absent(),
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedFiltersCompanion.insert(
                id: id,
                name: name,
                config: config,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedFiltersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedFiltersTable,
      SavedFilter,
      $$SavedFiltersTableFilterComposer,
      $$SavedFiltersTableOrderingComposer,
      $$SavedFiltersTableAnnotationComposer,
      $$SavedFiltersTableCreateCompanionBuilder,
      $$SavedFiltersTableUpdateCompanionBuilder,
      (
        SavedFilter,
        BaseReferences<_$AppDatabase, $SavedFiltersTable, SavedFilter>,
      ),
      SavedFilter,
      PrefetchHooks Function()
    >;
typedef $$DashboardWidgetsTableCreateCompanionBuilder =
    DashboardWidgetsCompanion Function({
      required String id,
      required String type,
      Value<String?> filterId,
      required int position,
      required String width,
      required String options,
      Value<bool> archived,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$DashboardWidgetsTableUpdateCompanionBuilder =
    DashboardWidgetsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String?> filterId,
      Value<int> position,
      Value<String> width,
      Value<String> options,
      Value<bool> archived,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$DashboardWidgetsTableFilterComposer
    extends Composer<_$AppDatabase, $DashboardWidgetsTable> {
  $$DashboardWidgetsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filterId => $composableBuilder(
    column: $table.filterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get options => $composableBuilder(
    column: $table.options,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DashboardWidgetsTableOrderingComposer
    extends Composer<_$AppDatabase, $DashboardWidgetsTable> {
  $$DashboardWidgetsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filterId => $composableBuilder(
    column: $table.filterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get width => $composableBuilder(
    column: $table.width,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get options => $composableBuilder(
    column: $table.options,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get archived => $composableBuilder(
    column: $table.archived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DashboardWidgetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DashboardWidgetsTable> {
  $$DashboardWidgetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get filterId =>
      $composableBuilder(column: $table.filterId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<String> get options =>
      $composableBuilder(column: $table.options, builder: (column) => column);

  GeneratedColumn<bool> get archived =>
      $composableBuilder(column: $table.archived, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$DashboardWidgetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DashboardWidgetsTable,
          DashboardWidget,
          $$DashboardWidgetsTableFilterComposer,
          $$DashboardWidgetsTableOrderingComposer,
          $$DashboardWidgetsTableAnnotationComposer,
          $$DashboardWidgetsTableCreateCompanionBuilder,
          $$DashboardWidgetsTableUpdateCompanionBuilder,
          (
            DashboardWidget,
            BaseReferences<
              _$AppDatabase,
              $DashboardWidgetsTable,
              DashboardWidget
            >,
          ),
          DashboardWidget,
          PrefetchHooks Function()
        > {
  $$DashboardWidgetsTableTableManager(
    _$AppDatabase db,
    $DashboardWidgetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DashboardWidgetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DashboardWidgetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DashboardWidgetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> filterId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> width = const Value.absent(),
                Value<String> options = const Value.absent(),
                Value<bool> archived = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DashboardWidgetsCompanion(
                id: id,
                type: type,
                filterId: filterId,
                position: position,
                width: width,
                options: options,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                Value<String?> filterId = const Value.absent(),
                required int position,
                required String width,
                required String options,
                Value<bool> archived = const Value.absent(),
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DashboardWidgetsCompanion.insert(
                id: id,
                type: type,
                filterId: filterId,
                position: position,
                width: width,
                options: options,
                archived: archived,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DashboardWidgetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DashboardWidgetsTable,
      DashboardWidget,
      $$DashboardWidgetsTableFilterComposer,
      $$DashboardWidgetsTableOrderingComposer,
      $$DashboardWidgetsTableAnnotationComposer,
      $$DashboardWidgetsTableCreateCompanionBuilder,
      $$DashboardWidgetsTableUpdateCompanionBuilder,
      (
        DashboardWidget,
        BaseReferences<_$AppDatabase, $DashboardWidgetsTable, DashboardWidget>,
      ),
      DashboardWidget,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> id,
      Value<BigInt> lastServerSeq,
      Value<BigInt?> lastSyncedAt,
      Value<bool> dashboardSeeded,
      Value<int> rowid,
    });
typedef $$SyncStateTableUpdateCompanionBuilder =
    SyncStateCompanion Function({
      Value<String> id,
      Value<BigInt> lastServerSeq,
      Value<BigInt?> lastSyncedAt,
      Value<bool> dashboardSeeded,
      Value<int> rowid,
    });

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
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

  ColumnFilters<BigInt> get lastServerSeq => $composableBuilder(
    column: $table.lastServerSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dashboardSeeded => $composableBuilder(
    column: $table.dashboardSeeded,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
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

  ColumnOrderings<BigInt> get lastServerSeq => $composableBuilder(
    column: $table.lastServerSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dashboardSeeded => $composableBuilder(
    column: $table.dashboardSeeded,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<BigInt> get lastServerSeq => $composableBuilder(
    column: $table.lastServerSeq,
    builder: (column) => column,
  );

  GeneratedColumn<BigInt> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get dashboardSeeded => $composableBuilder(
    column: $table.dashboardSeeded,
    builder: (column) => column,
  );
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (
            SyncStateData,
            BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
          ),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<BigInt> lastServerSeq = const Value.absent(),
                Value<BigInt?> lastSyncedAt = const Value.absent(),
                Value<bool> dashboardSeeded = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion(
                id: id,
                lastServerSeq: lastServerSeq,
                lastSyncedAt: lastSyncedAt,
                dashboardSeeded: dashboardSeeded,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<BigInt> lastServerSeq = const Value.absent(),
                Value<BigInt?> lastSyncedAt = const Value.absent(),
                Value<bool> dashboardSeeded = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncStateCompanion.insert(
                id: id,
                lastServerSeq: lastServerSeq,
                lastSyncedAt: lastSyncedAt,
                dashboardSeeded: dashboardSeeded,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (
        SyncStateData,
        BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>,
      ),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$TombstonesTableCreateCompanionBuilder =
    TombstonesCompanion Function({
      required String entityTable,
      required String entityId,
      required BigInt deletedAt,
      required BigInt createdAt,
      required BigInt updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });
typedef $$TombstonesTableUpdateCompanionBuilder =
    TombstonesCompanion Function({
      Value<String> entityTable,
      Value<String> entityId,
      Value<BigInt> deletedAt,
      Value<BigInt> createdAt,
      Value<BigInt> updatedAt,
      Value<bool> dirty,
      Value<int> rowid,
    });

class $$TombstonesTableFilterComposer
    extends Composer<_$AppDatabase, $TombstonesTable> {
  $$TombstonesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TombstonesTableOrderingComposer
    extends Composer<_$AppDatabase, $TombstonesTable> {
  $$TombstonesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get dirty => $composableBuilder(
    column: $table.dirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TombstonesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TombstonesTable> {
  $$TombstonesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entityTable => $composableBuilder(
    column: $table.entityTable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<BigInt> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<BigInt> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get dirty =>
      $composableBuilder(column: $table.dirty, builder: (column) => column);
}

class $$TombstonesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TombstonesTable,
          Tombstone,
          $$TombstonesTableFilterComposer,
          $$TombstonesTableOrderingComposer,
          $$TombstonesTableAnnotationComposer,
          $$TombstonesTableCreateCompanionBuilder,
          $$TombstonesTableUpdateCompanionBuilder,
          (
            Tombstone,
            BaseReferences<_$AppDatabase, $TombstonesTable, Tombstone>,
          ),
          Tombstone,
          PrefetchHooks Function()
        > {
  $$TombstonesTableTableManager(_$AppDatabase db, $TombstonesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TombstonesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TombstonesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TombstonesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entityTable = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<BigInt> deletedAt = const Value.absent(),
                Value<BigInt> createdAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TombstonesCompanion(
                entityTable: entityTable,
                entityId: entityId,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entityTable,
                required String entityId,
                required BigInt deletedAt,
                required BigInt createdAt,
                required BigInt updatedAt,
                Value<bool> dirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TombstonesCompanion.insert(
                entityTable: entityTable,
                entityId: entityId,
                deletedAt: deletedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                dirty: dirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TombstonesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TombstonesTable,
      Tombstone,
      $$TombstonesTableFilterComposer,
      $$TombstonesTableOrderingComposer,
      $$TombstonesTableAnnotationComposer,
      $$TombstonesTableCreateCompanionBuilder,
      $$TombstonesTableUpdateCompanionBuilder,
      (Tombstone, BaseReferences<_$AppDatabase, $TombstonesTable, Tombstone>),
      Tombstone,
      PrefetchHooks Function()
    >;
typedef $$VoiceSessionsTableCreateCompanionBuilder =
    VoiceSessionsCompanion Function({
      required String id,
      required String model,
      required String status,
      required BigInt startedAt,
      required BigInt updatedAt,
      Value<BigInt?> endedAt,
      Value<bool> endedExplicitly,
      Value<String?> resumeHandle,
      Value<BigInt?> resumeHandleUpdatedAt,
      Value<bool> remoteEnabled,
      Value<bool> remoteSynced,
      Value<int> rowid,
    });
typedef $$VoiceSessionsTableUpdateCompanionBuilder =
    VoiceSessionsCompanion Function({
      Value<String> id,
      Value<String> model,
      Value<String> status,
      Value<BigInt> startedAt,
      Value<BigInt> updatedAt,
      Value<BigInt?> endedAt,
      Value<bool> endedExplicitly,
      Value<String?> resumeHandle,
      Value<BigInt?> resumeHandleUpdatedAt,
      Value<bool> remoteEnabled,
      Value<bool> remoteSynced,
      Value<int> rowid,
    });

class $$VoiceSessionsTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceSessionsTable> {
  $$VoiceSessionsTableFilterComposer({
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

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get endedExplicitly => $composableBuilder(
    column: $table.endedExplicitly,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resumeHandle => $composableBuilder(
    column: $table.resumeHandle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get resumeHandleUpdatedAt => $composableBuilder(
    column: $table.resumeHandleUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get remoteEnabled => $composableBuilder(
    column: $table.remoteEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get remoteSynced => $composableBuilder(
    column: $table.remoteSynced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoiceSessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceSessionsTable> {
  $$VoiceSessionsTableOrderingComposer({
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

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get endedExplicitly => $composableBuilder(
    column: $table.endedExplicitly,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resumeHandle => $composableBuilder(
    column: $table.resumeHandle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get resumeHandleUpdatedAt => $composableBuilder(
    column: $table.resumeHandleUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remoteEnabled => $composableBuilder(
    column: $table.remoteEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remoteSynced => $composableBuilder(
    column: $table.remoteSynced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoiceSessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceSessionsTable> {
  $$VoiceSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<BigInt> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<BigInt> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<BigInt> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<bool> get endedExplicitly => $composableBuilder(
    column: $table.endedExplicitly,
    builder: (column) => column,
  );

  GeneratedColumn<String> get resumeHandle => $composableBuilder(
    column: $table.resumeHandle,
    builder: (column) => column,
  );

  GeneratedColumn<BigInt> get resumeHandleUpdatedAt => $composableBuilder(
    column: $table.resumeHandleUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get remoteEnabled => $composableBuilder(
    column: $table.remoteEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get remoteSynced => $composableBuilder(
    column: $table.remoteSynced,
    builder: (column) => column,
  );
}

class $$VoiceSessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VoiceSessionsTable,
          VoiceSession,
          $$VoiceSessionsTableFilterComposer,
          $$VoiceSessionsTableOrderingComposer,
          $$VoiceSessionsTableAnnotationComposer,
          $$VoiceSessionsTableCreateCompanionBuilder,
          $$VoiceSessionsTableUpdateCompanionBuilder,
          (
            VoiceSession,
            BaseReferences<_$AppDatabase, $VoiceSessionsTable, VoiceSession>,
          ),
          VoiceSession,
          PrefetchHooks Function()
        > {
  $$VoiceSessionsTableTableManager(_$AppDatabase db, $VoiceSessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<BigInt> startedAt = const Value.absent(),
                Value<BigInt> updatedAt = const Value.absent(),
                Value<BigInt?> endedAt = const Value.absent(),
                Value<bool> endedExplicitly = const Value.absent(),
                Value<String?> resumeHandle = const Value.absent(),
                Value<BigInt?> resumeHandleUpdatedAt = const Value.absent(),
                Value<bool> remoteEnabled = const Value.absent(),
                Value<bool> remoteSynced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceSessionsCompanion(
                id: id,
                model: model,
                status: status,
                startedAt: startedAt,
                updatedAt: updatedAt,
                endedAt: endedAt,
                endedExplicitly: endedExplicitly,
                resumeHandle: resumeHandle,
                resumeHandleUpdatedAt: resumeHandleUpdatedAt,
                remoteEnabled: remoteEnabled,
                remoteSynced: remoteSynced,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String model,
                required String status,
                required BigInt startedAt,
                required BigInt updatedAt,
                Value<BigInt?> endedAt = const Value.absent(),
                Value<bool> endedExplicitly = const Value.absent(),
                Value<String?> resumeHandle = const Value.absent(),
                Value<BigInt?> resumeHandleUpdatedAt = const Value.absent(),
                Value<bool> remoteEnabled = const Value.absent(),
                Value<bool> remoteSynced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceSessionsCompanion.insert(
                id: id,
                model: model,
                status: status,
                startedAt: startedAt,
                updatedAt: updatedAt,
                endedAt: endedAt,
                endedExplicitly: endedExplicitly,
                resumeHandle: resumeHandle,
                resumeHandleUpdatedAt: resumeHandleUpdatedAt,
                remoteEnabled: remoteEnabled,
                remoteSynced: remoteSynced,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoiceSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VoiceSessionsTable,
      VoiceSession,
      $$VoiceSessionsTableFilterComposer,
      $$VoiceSessionsTableOrderingComposer,
      $$VoiceSessionsTableAnnotationComposer,
      $$VoiceSessionsTableCreateCompanionBuilder,
      $$VoiceSessionsTableUpdateCompanionBuilder,
      (
        VoiceSession,
        BaseReferences<_$AppDatabase, $VoiceSessionsTable, VoiceSession>,
      ),
      VoiceSession,
      PrefetchHooks Function()
    >;
typedef $$VoiceSessionEventsTableCreateCompanionBuilder =
    VoiceSessionEventsCompanion Function({
      required String id,
      required String sessionId,
      required int sequence,
      required BigInt occurredAt,
      required String type,
      required String direction,
      Value<String?> modality,
      required String payloadJson,
      Value<String?> rawJson,
      Value<Uint8List?> binaryData,
      Value<String?> binaryMimeType,
      Value<bool> remoteSynced,
      Value<int> rowid,
    });
typedef $$VoiceSessionEventsTableUpdateCompanionBuilder =
    VoiceSessionEventsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<int> sequence,
      Value<BigInt> occurredAt,
      Value<String> type,
      Value<String> direction,
      Value<String?> modality,
      Value<String> payloadJson,
      Value<String?> rawJson,
      Value<Uint8List?> binaryData,
      Value<String?> binaryMimeType,
      Value<bool> remoteSynced,
      Value<int> rowid,
    });

class $$VoiceSessionEventsTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceSessionEventsTable> {
  $$VoiceSessionEventsTableFilterComposer({
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

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<BigInt> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modality => $composableBuilder(
    column: $table.modality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get binaryData => $composableBuilder(
    column: $table.binaryData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get binaryMimeType => $composableBuilder(
    column: $table.binaryMimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get remoteSynced => $composableBuilder(
    column: $table.remoteSynced,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoiceSessionEventsTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceSessionEventsTable> {
  $$VoiceSessionEventsTableOrderingComposer({
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

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<BigInt> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modality => $composableBuilder(
    column: $table.modality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawJson => $composableBuilder(
    column: $table.rawJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get binaryData => $composableBuilder(
    column: $table.binaryData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get binaryMimeType => $composableBuilder(
    column: $table.binaryMimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get remoteSynced => $composableBuilder(
    column: $table.remoteSynced,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoiceSessionEventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceSessionEventsTable> {
  $$VoiceSessionEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<BigInt> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get modality =>
      $composableBuilder(column: $table.modality, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawJson =>
      $composableBuilder(column: $table.rawJson, builder: (column) => column);

  GeneratedColumn<Uint8List> get binaryData => $composableBuilder(
    column: $table.binaryData,
    builder: (column) => column,
  );

  GeneratedColumn<String> get binaryMimeType => $composableBuilder(
    column: $table.binaryMimeType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get remoteSynced => $composableBuilder(
    column: $table.remoteSynced,
    builder: (column) => column,
  );
}

class $$VoiceSessionEventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VoiceSessionEventsTable,
          VoiceSessionEvent,
          $$VoiceSessionEventsTableFilterComposer,
          $$VoiceSessionEventsTableOrderingComposer,
          $$VoiceSessionEventsTableAnnotationComposer,
          $$VoiceSessionEventsTableCreateCompanionBuilder,
          $$VoiceSessionEventsTableUpdateCompanionBuilder,
          (
            VoiceSessionEvent,
            BaseReferences<
              _$AppDatabase,
              $VoiceSessionEventsTable,
              VoiceSessionEvent
            >,
          ),
          VoiceSessionEvent,
          PrefetchHooks Function()
        > {
  $$VoiceSessionEventsTableTableManager(
    _$AppDatabase db,
    $VoiceSessionEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceSessionEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceSessionEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceSessionEventsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<BigInt> occurredAt = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String?> modality = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<String?> rawJson = const Value.absent(),
                Value<Uint8List?> binaryData = const Value.absent(),
                Value<String?> binaryMimeType = const Value.absent(),
                Value<bool> remoteSynced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceSessionEventsCompanion(
                id: id,
                sessionId: sessionId,
                sequence: sequence,
                occurredAt: occurredAt,
                type: type,
                direction: direction,
                modality: modality,
                payloadJson: payloadJson,
                rawJson: rawJson,
                binaryData: binaryData,
                binaryMimeType: binaryMimeType,
                remoteSynced: remoteSynced,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required int sequence,
                required BigInt occurredAt,
                required String type,
                required String direction,
                Value<String?> modality = const Value.absent(),
                required String payloadJson,
                Value<String?> rawJson = const Value.absent(),
                Value<Uint8List?> binaryData = const Value.absent(),
                Value<String?> binaryMimeType = const Value.absent(),
                Value<bool> remoteSynced = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceSessionEventsCompanion.insert(
                id: id,
                sessionId: sessionId,
                sequence: sequence,
                occurredAt: occurredAt,
                type: type,
                direction: direction,
                modality: modality,
                payloadJson: payloadJson,
                rawJson: rawJson,
                binaryData: binaryData,
                binaryMimeType: binaryMimeType,
                remoteSynced: remoteSynced,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoiceSessionEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VoiceSessionEventsTable,
      VoiceSessionEvent,
      $$VoiceSessionEventsTableFilterComposer,
      $$VoiceSessionEventsTableOrderingComposer,
      $$VoiceSessionEventsTableAnnotationComposer,
      $$VoiceSessionEventsTableCreateCompanionBuilder,
      $$VoiceSessionEventsTableUpdateCompanionBuilder,
      (
        VoiceSessionEvent,
        BaseReferences<
          _$AppDatabase,
          $VoiceSessionEventsTable,
          VoiceSessionEvent
        >,
      ),
      VoiceSessionEvent,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$AccountsTableTableManager get accounts =>
      $$AccountsTableTableManager(_db, _db.accounts);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$TransactionsTableTableManager get transactions =>
      $$TransactionsTableTableManager(_db, _db.transactions);
  $$TagsTableTableManager get tags => $$TagsTableTableManager(_db, _db.tags);
  $$TransactionTagsTableTableManager get transactionTags =>
      $$TransactionTagsTableTableManager(_db, _db.transactionTags);
  $$SavedFiltersTableTableManager get savedFilters =>
      $$SavedFiltersTableTableManager(_db, _db.savedFilters);
  $$DashboardWidgetsTableTableManager get dashboardWidgets =>
      $$DashboardWidgetsTableTableManager(_db, _db.dashboardWidgets);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
  $$TombstonesTableTableManager get tombstones =>
      $$TombstonesTableTableManager(_db, _db.tombstones);
  $$VoiceSessionsTableTableManager get voiceSessions =>
      $$VoiceSessionsTableTableManager(_db, _db.voiceSessions);
  $$VoiceSessionEventsTableTableManager get voiceSessionEvents =>
      $$VoiceSessionEventsTableTableManager(_db, _db.voiceSessionEvents);
}
