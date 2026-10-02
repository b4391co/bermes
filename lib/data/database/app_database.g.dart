// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConnectionsTable extends Connections
    with TableInfo<$ConnectionsTable, Connection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConnectionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _schemeMeta = const VerificationMeta('scheme');
  @override
  late final GeneratedColumn<String> scheme = GeneratedColumn<String>(
    'scheme',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _basePathMeta = const VerificationMeta(
    'basePath',
  );
  @override
  late final GeneratedColumn<String> basePath = GeneratedColumn<String>(
    'base_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authKindMeta = const VerificationMeta(
    'authKind',
  );
  @override
  late final GeneratedColumn<String> authKind = GeneratedColumn<String>(
    'auth_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _allowInsecureTlsMeta = const VerificationMeta(
    'allowInsecureTls',
  );
  @override
  late final GeneratedColumn<bool> allowInsecureTls = GeneratedColumn<bool>(
    'allow_insecure_tls',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_insecure_tls" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
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
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _installIdMeta = const VerificationMeta(
    'installId',
  );
  @override
  late final GeneratedColumn<String> installId = GeneratedColumn<String>(
    'install_id',
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    scheme,
    host,
    port,
    basePath,
    authKind,
    username,
    allowInsecureTls,
    enabled,
    displayOrder,
    installId,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'connections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Connection> instance, {
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
    if (data.containsKey('scheme')) {
      context.handle(
        _schemeMeta,
        scheme.isAcceptableOrUnknown(data['scheme']!, _schemeMeta),
      );
    } else if (isInserting) {
      context.missing(_schemeMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('base_path')) {
      context.handle(
        _basePathMeta,
        basePath.isAcceptableOrUnknown(data['base_path']!, _basePathMeta),
      );
    }
    if (data.containsKey('auth_kind')) {
      context.handle(
        _authKindMeta,
        authKind.isAcceptableOrUnknown(data['auth_kind']!, _authKindMeta),
      );
    } else if (isInserting) {
      context.missing(_authKindMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    }
    if (data.containsKey('allow_insecure_tls')) {
      context.handle(
        _allowInsecureTlsMeta,
        allowInsecureTls.isAcceptableOrUnknown(
          data['allow_insecure_tls']!,
          _allowInsecureTlsMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    }
    if (data.containsKey('install_id')) {
      context.handle(
        _installIdMeta,
        installId.isAcceptableOrUnknown(data['install_id']!, _installIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Connection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Connection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      scheme: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scheme'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      basePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}base_path'],
      )!,
      authKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_kind'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      allowInsecureTls: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_insecure_tls'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      installId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}install_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ConnectionsTable createAlias(String alias) {
    return $ConnectionsTable(attachedDatabase, alias);
  }
}

class Connection extends DataClass implements Insertable<Connection> {
  final String id;
  final String name;
  final String scheme;
  final String host;
  final int port;
  final String basePath;
  final String authKind;
  final String username;
  final bool allowInsecureTls;
  final bool enabled;
  final int displayOrder;
  final String? installId;
  final DateTime createdAt;
  const Connection({
    required this.id,
    required this.name,
    required this.scheme,
    required this.host,
    required this.port,
    required this.basePath,
    required this.authKind,
    required this.username,
    required this.allowInsecureTls,
    required this.enabled,
    required this.displayOrder,
    this.installId,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['scheme'] = Variable<String>(scheme);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['base_path'] = Variable<String>(basePath);
    map['auth_kind'] = Variable<String>(authKind);
    map['username'] = Variable<String>(username);
    map['allow_insecure_tls'] = Variable<bool>(allowInsecureTls);
    map['enabled'] = Variable<bool>(enabled);
    map['display_order'] = Variable<int>(displayOrder);
    if (!nullToAbsent || installId != null) {
      map['install_id'] = Variable<String>(installId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ConnectionsCompanion toCompanion(bool nullToAbsent) {
    return ConnectionsCompanion(
      id: Value(id),
      name: Value(name),
      scheme: Value(scheme),
      host: Value(host),
      port: Value(port),
      basePath: Value(basePath),
      authKind: Value(authKind),
      username: Value(username),
      allowInsecureTls: Value(allowInsecureTls),
      enabled: Value(enabled),
      displayOrder: Value(displayOrder),
      installId: installId == null && nullToAbsent
          ? const Value.absent()
          : Value(installId),
      createdAt: Value(createdAt),
    );
  }

  factory Connection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Connection(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      scheme: serializer.fromJson<String>(json['scheme']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      basePath: serializer.fromJson<String>(json['basePath']),
      authKind: serializer.fromJson<String>(json['authKind']),
      username: serializer.fromJson<String>(json['username']),
      allowInsecureTls: serializer.fromJson<bool>(json['allowInsecureTls']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      installId: serializer.fromJson<String?>(json['installId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'scheme': serializer.toJson<String>(scheme),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'basePath': serializer.toJson<String>(basePath),
      'authKind': serializer.toJson<String>(authKind),
      'username': serializer.toJson<String>(username),
      'allowInsecureTls': serializer.toJson<bool>(allowInsecureTls),
      'enabled': serializer.toJson<bool>(enabled),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'installId': serializer.toJson<String?>(installId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Connection copyWith({
    String? id,
    String? name,
    String? scheme,
    String? host,
    int? port,
    String? basePath,
    String? authKind,
    String? username,
    bool? allowInsecureTls,
    bool? enabled,
    int? displayOrder,
    Value<String?> installId = const Value.absent(),
    DateTime? createdAt,
  }) => Connection(
    id: id ?? this.id,
    name: name ?? this.name,
    scheme: scheme ?? this.scheme,
    host: host ?? this.host,
    port: port ?? this.port,
    basePath: basePath ?? this.basePath,
    authKind: authKind ?? this.authKind,
    username: username ?? this.username,
    allowInsecureTls: allowInsecureTls ?? this.allowInsecureTls,
    enabled: enabled ?? this.enabled,
    displayOrder: displayOrder ?? this.displayOrder,
    installId: installId.present ? installId.value : this.installId,
    createdAt: createdAt ?? this.createdAt,
  );
  Connection copyWithCompanion(ConnectionsCompanion data) {
    return Connection(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      scheme: data.scheme.present ? data.scheme.value : this.scheme,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      basePath: data.basePath.present ? data.basePath.value : this.basePath,
      authKind: data.authKind.present ? data.authKind.value : this.authKind,
      username: data.username.present ? data.username.value : this.username,
      allowInsecureTls: data.allowInsecureTls.present
          ? data.allowInsecureTls.value
          : this.allowInsecureTls,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      installId: data.installId.present ? data.installId.value : this.installId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Connection(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('scheme: $scheme, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('basePath: $basePath, ')
          ..write('authKind: $authKind, ')
          ..write('username: $username, ')
          ..write('allowInsecureTls: $allowInsecureTls, ')
          ..write('enabled: $enabled, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('installId: $installId, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    scheme,
    host,
    port,
    basePath,
    authKind,
    username,
    allowInsecureTls,
    enabled,
    displayOrder,
    installId,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Connection &&
          other.id == this.id &&
          other.name == this.name &&
          other.scheme == this.scheme &&
          other.host == this.host &&
          other.port == this.port &&
          other.basePath == this.basePath &&
          other.authKind == this.authKind &&
          other.username == this.username &&
          other.allowInsecureTls == this.allowInsecureTls &&
          other.enabled == this.enabled &&
          other.displayOrder == this.displayOrder &&
          other.installId == this.installId &&
          other.createdAt == this.createdAt);
}

class ConnectionsCompanion extends UpdateCompanion<Connection> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> scheme;
  final Value<String> host;
  final Value<int> port;
  final Value<String> basePath;
  final Value<String> authKind;
  final Value<String> username;
  final Value<bool> allowInsecureTls;
  final Value<bool> enabled;
  final Value<int> displayOrder;
  final Value<String?> installId;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ConnectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.scheme = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.basePath = const Value.absent(),
    this.authKind = const Value.absent(),
    this.username = const Value.absent(),
    this.allowInsecureTls = const Value.absent(),
    this.enabled = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.installId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConnectionsCompanion.insert({
    required String id,
    required String name,
    required String scheme,
    required String host,
    required int port,
    this.basePath = const Value.absent(),
    required String authKind,
    this.username = const Value.absent(),
    this.allowInsecureTls = const Value.absent(),
    this.enabled = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.installId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       scheme = Value(scheme),
       host = Value(host),
       port = Value(port),
       authKind = Value(authKind);
  static Insertable<Connection> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? scheme,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? basePath,
    Expression<String>? authKind,
    Expression<String>? username,
    Expression<bool>? allowInsecureTls,
    Expression<bool>? enabled,
    Expression<int>? displayOrder,
    Expression<String>? installId,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (scheme != null) 'scheme': scheme,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (basePath != null) 'base_path': basePath,
      if (authKind != null) 'auth_kind': authKind,
      if (username != null) 'username': username,
      if (allowInsecureTls != null) 'allow_insecure_tls': allowInsecureTls,
      if (enabled != null) 'enabled': enabled,
      if (displayOrder != null) 'display_order': displayOrder,
      if (installId != null) 'install_id': installId,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConnectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? scheme,
    Value<String>? host,
    Value<int>? port,
    Value<String>? basePath,
    Value<String>? authKind,
    Value<String>? username,
    Value<bool>? allowInsecureTls,
    Value<bool>? enabled,
    Value<int>? displayOrder,
    Value<String?>? installId,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ConnectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      scheme: scheme ?? this.scheme,
      host: host ?? this.host,
      port: port ?? this.port,
      basePath: basePath ?? this.basePath,
      authKind: authKind ?? this.authKind,
      username: username ?? this.username,
      allowInsecureTls: allowInsecureTls ?? this.allowInsecureTls,
      enabled: enabled ?? this.enabled,
      displayOrder: displayOrder ?? this.displayOrder,
      installId: installId ?? this.installId,
      createdAt: createdAt ?? this.createdAt,
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
    if (scheme.present) {
      map['scheme'] = Variable<String>(scheme.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (basePath.present) {
      map['base_path'] = Variable<String>(basePath.value);
    }
    if (authKind.present) {
      map['auth_kind'] = Variable<String>(authKind.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (allowInsecureTls.present) {
      map['allow_insecure_tls'] = Variable<bool>(allowInsecureTls.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (installId.present) {
      map['install_id'] = Variable<String>(installId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('scheme: $scheme, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('basePath: $basePath, ')
          ..write('authKind: $authKind, ')
          ..write('username: $username, ')
          ..write('allowInsecureTls: $allowInsecureTls, ')
          ..write('enabled: $enabled, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('installId: $installId, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionIdMeta = const VerificationMeta(
    'connectionId',
  );
  @override
  late final GeneratedColumn<String> connectionId = GeneratedColumn<String>(
    'connection_id',
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
  static const VerificationMeta _gatewayIdMeta = const VerificationMeta(
    'gatewayId',
  );
  @override
  late final GeneratedColumn<String> gatewayId = GeneratedColumn<String>(
    'gateway_id',
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtitleMeta = const VerificationMeta(
    'subtitle',
  );
  @override
  late final GeneratedColumn<String> subtitle = GeneratedColumn<String>(
    'subtitle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarSeedMeta = const VerificationMeta(
    'avatarSeed',
  );
  @override
  late final GeneratedColumn<String> avatarSeed = GeneratedColumn<String>(
    'avatar_seed',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta(
    'avatarUrl',
  );
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _botAvatarMetaMeta = const VerificationMeta(
    'botAvatarMeta',
  );
  @override
  late final GeneratedColumn<String> botAvatarMeta = GeneratedColumn<String>(
    'bot_avatar_meta',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _canonicalSessionMeta = const VerificationMeta(
    'canonicalSession',
  );
  @override
  late final GeneratedColumn<String> canonicalSession = GeneratedColumn<String>(
    'canonical_session',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isGroupMeta = const VerificationMeta(
    'isGroup',
  );
  @override
  late final GeneratedColumn<bool> isGroup = GeneratedColumn<bool>(
    'is_group',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_group" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _gatewayLabelMeta = const VerificationMeta(
    'gatewayLabel',
  );
  @override
  late final GeneratedColumn<String> gatewayLabel = GeneratedColumn<String>(
    'gateway_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastActivityMeta = const VerificationMeta(
    'lastActivity',
  );
  @override
  late final GeneratedColumn<DateTime> lastActivity = GeneratedColumn<DateTime>(
    'last_activity',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _previewMeta = const VerificationMeta(
    'preview',
  );
  @override
  late final GeneratedColumn<String> preview = GeneratedColumn<String>(
    'preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pinnedMeta = const VerificationMeta('pinned');
  @override
  late final GeneratedColumn<bool> pinned = GeneratedColumn<bool>(
    'pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedGatewayMeta = const VerificationMeta(
    'pinnedGateway',
  );
  @override
  late final GeneratedColumn<bool> pinnedGateway = GeneratedColumn<bool>(
    'pinned_gateway',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pinned_gateway" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _groupRoomIdMeta = const VerificationMeta(
    'groupRoomId',
  );
  @override
  late final GeneratedColumn<String> groupRoomId = GeneratedColumn<String>(
    'group_room_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupSyncRevisionMeta = const VerificationMeta(
    'groupSyncRevision',
  );
  @override
  late final GeneratedColumn<int> groupSyncRevision = GeneratedColumn<int>(
    'group_sync_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _groupSyncNameMeta = const VerificationMeta(
    'groupSyncName',
  );
  @override
  late final GeneratedColumn<String> groupSyncName = GeneratedColumn<String>(
    'group_sync_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    connectionId,
    kind,
    gatewayId,
    title,
    subtitle,
    avatarSeed,
    avatarUrl,
    botAvatarMeta,
    canonicalSession,
    isGroup,
    gatewayLabel,
    lastActivity,
    preview,
    unreadCount,
    sortOrder,
    pinned,
    pinnedGateway,
    groupRoomId,
    groupSyncRevision,
    groupSyncName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('connection_id')) {
      context.handle(
        _connectionIdMeta,
        connectionId.isAcceptableOrUnknown(
          data['connection_id']!,
          _connectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('gateway_id')) {
      context.handle(
        _gatewayIdMeta,
        gatewayId.isAcceptableOrUnknown(data['gateway_id']!, _gatewayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gatewayIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subtitle')) {
      context.handle(
        _subtitleMeta,
        subtitle.isAcceptableOrUnknown(data['subtitle']!, _subtitleMeta),
      );
    }
    if (data.containsKey('avatar_seed')) {
      context.handle(
        _avatarSeedMeta,
        avatarSeed.isAcceptableOrUnknown(data['avatar_seed']!, _avatarSeedMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    if (data.containsKey('bot_avatar_meta')) {
      context.handle(
        _botAvatarMetaMeta,
        botAvatarMeta.isAcceptableOrUnknown(
          data['bot_avatar_meta']!,
          _botAvatarMetaMeta,
        ),
      );
    }
    if (data.containsKey('canonical_session')) {
      context.handle(
        _canonicalSessionMeta,
        canonicalSession.isAcceptableOrUnknown(
          data['canonical_session']!,
          _canonicalSessionMeta,
        ),
      );
    }
    if (data.containsKey('is_group')) {
      context.handle(
        _isGroupMeta,
        isGroup.isAcceptableOrUnknown(data['is_group']!, _isGroupMeta),
      );
    }
    if (data.containsKey('gateway_label')) {
      context.handle(
        _gatewayLabelMeta,
        gatewayLabel.isAcceptableOrUnknown(
          data['gateway_label']!,
          _gatewayLabelMeta,
        ),
      );
    }
    if (data.containsKey('last_activity')) {
      context.handle(
        _lastActivityMeta,
        lastActivity.isAcceptableOrUnknown(
          data['last_activity']!,
          _lastActivityMeta,
        ),
      );
    }
    if (data.containsKey('preview')) {
      context.handle(
        _previewMeta,
        preview.isAcceptableOrUnknown(data['preview']!, _previewMeta),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('pinned')) {
      context.handle(
        _pinnedMeta,
        pinned.isAcceptableOrUnknown(data['pinned']!, _pinnedMeta),
      );
    }
    if (data.containsKey('pinned_gateway')) {
      context.handle(
        _pinnedGatewayMeta,
        pinnedGateway.isAcceptableOrUnknown(
          data['pinned_gateway']!,
          _pinnedGatewayMeta,
        ),
      );
    }
    if (data.containsKey('group_room_id')) {
      context.handle(
        _groupRoomIdMeta,
        groupRoomId.isAcceptableOrUnknown(
          data['group_room_id']!,
          _groupRoomIdMeta,
        ),
      );
    }
    if (data.containsKey('group_sync_revision')) {
      context.handle(
        _groupSyncRevisionMeta,
        groupSyncRevision.isAcceptableOrUnknown(
          data['group_sync_revision']!,
          _groupSyncRevisionMeta,
        ),
      );
    }
    if (data.containsKey('group_sync_name')) {
      context.handle(
        _groupSyncNameMeta,
        groupSyncName.isAcceptableOrUnknown(
          data['group_sync_name']!,
          _groupSyncNameMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      connectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      gatewayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subtitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle'],
      ),
      avatarSeed: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_seed'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
      botAvatarMeta: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bot_avatar_meta'],
      ),
      canonicalSession: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_session'],
      ),
      isGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_group'],
      )!,
      gatewayLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway_label'],
      ),
      lastActivity: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_activity'],
      ),
      preview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preview'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      pinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned'],
      )!,
      pinnedGateway: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pinned_gateway'],
      )!,
      groupRoomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_room_id'],
      ),
      groupSyncRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}group_sync_revision'],
      )!,
      groupSyncName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_sync_name'],
      ),
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;
  final String connectionId;
  final String kind;
  final String gatewayId;
  final String title;
  final String? subtitle;
  final String? avatarSeed;
  final String? avatarUrl;
  final String? botAvatarMeta;
  final String? canonicalSession;
  final bool isGroup;
  final String? gatewayLabel;
  final DateTime? lastActivity;
  final String? preview;
  final int unreadCount;
  final int sortOrder;
  final bool pinned;
  final bool pinnedGateway;
  final String? groupRoomId;
  final int groupSyncRevision;
  final String? groupSyncName;
  const Conversation({
    required this.id,
    required this.connectionId,
    required this.kind,
    required this.gatewayId,
    required this.title,
    this.subtitle,
    this.avatarSeed,
    this.avatarUrl,
    this.botAvatarMeta,
    this.canonicalSession,
    required this.isGroup,
    this.gatewayLabel,
    this.lastActivity,
    this.preview,
    required this.unreadCount,
    required this.sortOrder,
    required this.pinned,
    required this.pinnedGateway,
    this.groupRoomId,
    required this.groupSyncRevision,
    this.groupSyncName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['connection_id'] = Variable<String>(connectionId);
    map['kind'] = Variable<String>(kind);
    map['gateway_id'] = Variable<String>(gatewayId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subtitle != null) {
      map['subtitle'] = Variable<String>(subtitle);
    }
    if (!nullToAbsent || avatarSeed != null) {
      map['avatar_seed'] = Variable<String>(avatarSeed);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || botAvatarMeta != null) {
      map['bot_avatar_meta'] = Variable<String>(botAvatarMeta);
    }
    if (!nullToAbsent || canonicalSession != null) {
      map['canonical_session'] = Variable<String>(canonicalSession);
    }
    map['is_group'] = Variable<bool>(isGroup);
    if (!nullToAbsent || gatewayLabel != null) {
      map['gateway_label'] = Variable<String>(gatewayLabel);
    }
    if (!nullToAbsent || lastActivity != null) {
      map['last_activity'] = Variable<DateTime>(lastActivity);
    }
    if (!nullToAbsent || preview != null) {
      map['preview'] = Variable<String>(preview);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['sort_order'] = Variable<int>(sortOrder);
    map['pinned'] = Variable<bool>(pinned);
    map['pinned_gateway'] = Variable<bool>(pinnedGateway);
    if (!nullToAbsent || groupRoomId != null) {
      map['group_room_id'] = Variable<String>(groupRoomId);
    }
    map['group_sync_revision'] = Variable<int>(groupSyncRevision);
    if (!nullToAbsent || groupSyncName != null) {
      map['group_sync_name'] = Variable<String>(groupSyncName);
    }
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      connectionId: Value(connectionId),
      kind: Value(kind),
      gatewayId: Value(gatewayId),
      title: Value(title),
      subtitle: subtitle == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitle),
      avatarSeed: avatarSeed == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarSeed),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      botAvatarMeta: botAvatarMeta == null && nullToAbsent
          ? const Value.absent()
          : Value(botAvatarMeta),
      canonicalSession: canonicalSession == null && nullToAbsent
          ? const Value.absent()
          : Value(canonicalSession),
      isGroup: Value(isGroup),
      gatewayLabel: gatewayLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(gatewayLabel),
      lastActivity: lastActivity == null && nullToAbsent
          ? const Value.absent()
          : Value(lastActivity),
      preview: preview == null && nullToAbsent
          ? const Value.absent()
          : Value(preview),
      unreadCount: Value(unreadCount),
      sortOrder: Value(sortOrder),
      pinned: Value(pinned),
      pinnedGateway: Value(pinnedGateway),
      groupRoomId: groupRoomId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupRoomId),
      groupSyncRevision: Value(groupSyncRevision),
      groupSyncName: groupSyncName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupSyncName),
    );
  }

  factory Conversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      connectionId: serializer.fromJson<String>(json['connectionId']),
      kind: serializer.fromJson<String>(json['kind']),
      gatewayId: serializer.fromJson<String>(json['gatewayId']),
      title: serializer.fromJson<String>(json['title']),
      subtitle: serializer.fromJson<String?>(json['subtitle']),
      avatarSeed: serializer.fromJson<String?>(json['avatarSeed']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      botAvatarMeta: serializer.fromJson<String?>(json['botAvatarMeta']),
      canonicalSession: serializer.fromJson<String?>(json['canonicalSession']),
      isGroup: serializer.fromJson<bool>(json['isGroup']),
      gatewayLabel: serializer.fromJson<String?>(json['gatewayLabel']),
      lastActivity: serializer.fromJson<DateTime?>(json['lastActivity']),
      preview: serializer.fromJson<String?>(json['preview']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      pinned: serializer.fromJson<bool>(json['pinned']),
      pinnedGateway: serializer.fromJson<bool>(json['pinnedGateway']),
      groupRoomId: serializer.fromJson<String?>(json['groupRoomId']),
      groupSyncRevision: serializer.fromJson<int>(json['groupSyncRevision']),
      groupSyncName: serializer.fromJson<String?>(json['groupSyncName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'connectionId': serializer.toJson<String>(connectionId),
      'kind': serializer.toJson<String>(kind),
      'gatewayId': serializer.toJson<String>(gatewayId),
      'title': serializer.toJson<String>(title),
      'subtitle': serializer.toJson<String?>(subtitle),
      'avatarSeed': serializer.toJson<String?>(avatarSeed),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'botAvatarMeta': serializer.toJson<String?>(botAvatarMeta),
      'canonicalSession': serializer.toJson<String?>(canonicalSession),
      'isGroup': serializer.toJson<bool>(isGroup),
      'gatewayLabel': serializer.toJson<String?>(gatewayLabel),
      'lastActivity': serializer.toJson<DateTime?>(lastActivity),
      'preview': serializer.toJson<String?>(preview),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'pinned': serializer.toJson<bool>(pinned),
      'pinnedGateway': serializer.toJson<bool>(pinnedGateway),
      'groupRoomId': serializer.toJson<String?>(groupRoomId),
      'groupSyncRevision': serializer.toJson<int>(groupSyncRevision),
      'groupSyncName': serializer.toJson<String?>(groupSyncName),
    };
  }

  Conversation copyWith({
    String? id,
    String? connectionId,
    String? kind,
    String? gatewayId,
    String? title,
    Value<String?> subtitle = const Value.absent(),
    Value<String?> avatarSeed = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
    Value<String?> botAvatarMeta = const Value.absent(),
    Value<String?> canonicalSession = const Value.absent(),
    bool? isGroup,
    Value<String?> gatewayLabel = const Value.absent(),
    Value<DateTime?> lastActivity = const Value.absent(),
    Value<String?> preview = const Value.absent(),
    int? unreadCount,
    int? sortOrder,
    bool? pinned,
    bool? pinnedGateway,
    Value<String?> groupRoomId = const Value.absent(),
    int? groupSyncRevision,
    Value<String?> groupSyncName = const Value.absent(),
  }) => Conversation(
    id: id ?? this.id,
    connectionId: connectionId ?? this.connectionId,
    kind: kind ?? this.kind,
    gatewayId: gatewayId ?? this.gatewayId,
    title: title ?? this.title,
    subtitle: subtitle.present ? subtitle.value : this.subtitle,
    avatarSeed: avatarSeed.present ? avatarSeed.value : this.avatarSeed,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
    botAvatarMeta: botAvatarMeta.present
        ? botAvatarMeta.value
        : this.botAvatarMeta,
    canonicalSession: canonicalSession.present
        ? canonicalSession.value
        : this.canonicalSession,
    isGroup: isGroup ?? this.isGroup,
    gatewayLabel: gatewayLabel.present ? gatewayLabel.value : this.gatewayLabel,
    lastActivity: lastActivity.present ? lastActivity.value : this.lastActivity,
    preview: preview.present ? preview.value : this.preview,
    unreadCount: unreadCount ?? this.unreadCount,
    sortOrder: sortOrder ?? this.sortOrder,
    pinned: pinned ?? this.pinned,
    pinnedGateway: pinnedGateway ?? this.pinnedGateway,
    groupRoomId: groupRoomId.present ? groupRoomId.value : this.groupRoomId,
    groupSyncRevision: groupSyncRevision ?? this.groupSyncRevision,
    groupSyncName: groupSyncName.present
        ? groupSyncName.value
        : this.groupSyncName,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      connectionId: data.connectionId.present
          ? data.connectionId.value
          : this.connectionId,
      kind: data.kind.present ? data.kind.value : this.kind,
      gatewayId: data.gatewayId.present ? data.gatewayId.value : this.gatewayId,
      title: data.title.present ? data.title.value : this.title,
      subtitle: data.subtitle.present ? data.subtitle.value : this.subtitle,
      avatarSeed: data.avatarSeed.present
          ? data.avatarSeed.value
          : this.avatarSeed,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      botAvatarMeta: data.botAvatarMeta.present
          ? data.botAvatarMeta.value
          : this.botAvatarMeta,
      canonicalSession: data.canonicalSession.present
          ? data.canonicalSession.value
          : this.canonicalSession,
      isGroup: data.isGroup.present ? data.isGroup.value : this.isGroup,
      gatewayLabel: data.gatewayLabel.present
          ? data.gatewayLabel.value
          : this.gatewayLabel,
      lastActivity: data.lastActivity.present
          ? data.lastActivity.value
          : this.lastActivity,
      preview: data.preview.present ? data.preview.value : this.preview,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      pinned: data.pinned.present ? data.pinned.value : this.pinned,
      pinnedGateway: data.pinnedGateway.present
          ? data.pinnedGateway.value
          : this.pinnedGateway,
      groupRoomId: data.groupRoomId.present
          ? data.groupRoomId.value
          : this.groupRoomId,
      groupSyncRevision: data.groupSyncRevision.present
          ? data.groupSyncRevision.value
          : this.groupSyncRevision,
      groupSyncName: data.groupSyncName.present
          ? data.groupSyncName.value
          : this.groupSyncName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('connectionId: $connectionId, ')
          ..write('kind: $kind, ')
          ..write('gatewayId: $gatewayId, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('avatarSeed: $avatarSeed, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('botAvatarMeta: $botAvatarMeta, ')
          ..write('canonicalSession: $canonicalSession, ')
          ..write('isGroup: $isGroup, ')
          ..write('gatewayLabel: $gatewayLabel, ')
          ..write('lastActivity: $lastActivity, ')
          ..write('preview: $preview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('pinned: $pinned, ')
          ..write('pinnedGateway: $pinnedGateway, ')
          ..write('groupRoomId: $groupRoomId, ')
          ..write('groupSyncRevision: $groupSyncRevision, ')
          ..write('groupSyncName: $groupSyncName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    connectionId,
    kind,
    gatewayId,
    title,
    subtitle,
    avatarSeed,
    avatarUrl,
    botAvatarMeta,
    canonicalSession,
    isGroup,
    gatewayLabel,
    lastActivity,
    preview,
    unreadCount,
    sortOrder,
    pinned,
    pinnedGateway,
    groupRoomId,
    groupSyncRevision,
    groupSyncName,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.connectionId == this.connectionId &&
          other.kind == this.kind &&
          other.gatewayId == this.gatewayId &&
          other.title == this.title &&
          other.subtitle == this.subtitle &&
          other.avatarSeed == this.avatarSeed &&
          other.avatarUrl == this.avatarUrl &&
          other.botAvatarMeta == this.botAvatarMeta &&
          other.canonicalSession == this.canonicalSession &&
          other.isGroup == this.isGroup &&
          other.gatewayLabel == this.gatewayLabel &&
          other.lastActivity == this.lastActivity &&
          other.preview == this.preview &&
          other.unreadCount == this.unreadCount &&
          other.sortOrder == this.sortOrder &&
          other.pinned == this.pinned &&
          other.pinnedGateway == this.pinnedGateway &&
          other.groupRoomId == this.groupRoomId &&
          other.groupSyncRevision == this.groupSyncRevision &&
          other.groupSyncName == this.groupSyncName);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> connectionId;
  final Value<String> kind;
  final Value<String> gatewayId;
  final Value<String> title;
  final Value<String?> subtitle;
  final Value<String?> avatarSeed;
  final Value<String?> avatarUrl;
  final Value<String?> botAvatarMeta;
  final Value<String?> canonicalSession;
  final Value<bool> isGroup;
  final Value<String?> gatewayLabel;
  final Value<DateTime?> lastActivity;
  final Value<String?> preview;
  final Value<int> unreadCount;
  final Value<int> sortOrder;
  final Value<bool> pinned;
  final Value<bool> pinnedGateway;
  final Value<String?> groupRoomId;
  final Value<int> groupSyncRevision;
  final Value<String?> groupSyncName;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.connectionId = const Value.absent(),
    this.kind = const Value.absent(),
    this.gatewayId = const Value.absent(),
    this.title = const Value.absent(),
    this.subtitle = const Value.absent(),
    this.avatarSeed = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.botAvatarMeta = const Value.absent(),
    this.canonicalSession = const Value.absent(),
    this.isGroup = const Value.absent(),
    this.gatewayLabel = const Value.absent(),
    this.lastActivity = const Value.absent(),
    this.preview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.pinned = const Value.absent(),
    this.pinnedGateway = const Value.absent(),
    this.groupRoomId = const Value.absent(),
    this.groupSyncRevision = const Value.absent(),
    this.groupSyncName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    required String connectionId,
    required String kind,
    required String gatewayId,
    required String title,
    this.subtitle = const Value.absent(),
    this.avatarSeed = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.botAvatarMeta = const Value.absent(),
    this.canonicalSession = const Value.absent(),
    this.isGroup = const Value.absent(),
    this.gatewayLabel = const Value.absent(),
    this.lastActivity = const Value.absent(),
    this.preview = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.pinned = const Value.absent(),
    this.pinnedGateway = const Value.absent(),
    this.groupRoomId = const Value.absent(),
    this.groupSyncRevision = const Value.absent(),
    this.groupSyncName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       connectionId = Value(connectionId),
       kind = Value(kind),
       gatewayId = Value(gatewayId),
       title = Value(title);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? connectionId,
    Expression<String>? kind,
    Expression<String>? gatewayId,
    Expression<String>? title,
    Expression<String>? subtitle,
    Expression<String>? avatarSeed,
    Expression<String>? avatarUrl,
    Expression<String>? botAvatarMeta,
    Expression<String>? canonicalSession,
    Expression<bool>? isGroup,
    Expression<String>? gatewayLabel,
    Expression<DateTime>? lastActivity,
    Expression<String>? preview,
    Expression<int>? unreadCount,
    Expression<int>? sortOrder,
    Expression<bool>? pinned,
    Expression<bool>? pinnedGateway,
    Expression<String>? groupRoomId,
    Expression<int>? groupSyncRevision,
    Expression<String>? groupSyncName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (connectionId != null) 'connection_id': connectionId,
      if (kind != null) 'kind': kind,
      if (gatewayId != null) 'gateway_id': gatewayId,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (avatarSeed != null) 'avatar_seed': avatarSeed,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (botAvatarMeta != null) 'bot_avatar_meta': botAvatarMeta,
      if (canonicalSession != null) 'canonical_session': canonicalSession,
      if (isGroup != null) 'is_group': isGroup,
      if (gatewayLabel != null) 'gateway_label': gatewayLabel,
      if (lastActivity != null) 'last_activity': lastActivity,
      if (preview != null) 'preview': preview,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (pinned != null) 'pinned': pinned,
      if (pinnedGateway != null) 'pinned_gateway': pinnedGateway,
      if (groupRoomId != null) 'group_room_id': groupRoomId,
      if (groupSyncRevision != null) 'group_sync_revision': groupSyncRevision,
      if (groupSyncName != null) 'group_sync_name': groupSyncName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? connectionId,
    Value<String>? kind,
    Value<String>? gatewayId,
    Value<String>? title,
    Value<String?>? subtitle,
    Value<String?>? avatarSeed,
    Value<String?>? avatarUrl,
    Value<String?>? botAvatarMeta,
    Value<String?>? canonicalSession,
    Value<bool>? isGroup,
    Value<String?>? gatewayLabel,
    Value<DateTime?>? lastActivity,
    Value<String?>? preview,
    Value<int>? unreadCount,
    Value<int>? sortOrder,
    Value<bool>? pinned,
    Value<bool>? pinnedGateway,
    Value<String?>? groupRoomId,
    Value<int>? groupSyncRevision,
    Value<String?>? groupSyncName,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      connectionId: connectionId ?? this.connectionId,
      kind: kind ?? this.kind,
      gatewayId: gatewayId ?? this.gatewayId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      avatarSeed: avatarSeed ?? this.avatarSeed,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      botAvatarMeta: botAvatarMeta ?? this.botAvatarMeta,
      canonicalSession: canonicalSession ?? this.canonicalSession,
      isGroup: isGroup ?? this.isGroup,
      gatewayLabel: gatewayLabel ?? this.gatewayLabel,
      lastActivity: lastActivity ?? this.lastActivity,
      preview: preview ?? this.preview,
      unreadCount: unreadCount ?? this.unreadCount,
      sortOrder: sortOrder ?? this.sortOrder,
      pinned: pinned ?? this.pinned,
      pinnedGateway: pinnedGateway ?? this.pinnedGateway,
      groupRoomId: groupRoomId ?? this.groupRoomId,
      groupSyncRevision: groupSyncRevision ?? this.groupSyncRevision,
      groupSyncName: groupSyncName ?? this.groupSyncName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (connectionId.present) {
      map['connection_id'] = Variable<String>(connectionId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (gatewayId.present) {
      map['gateway_id'] = Variable<String>(gatewayId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subtitle.present) {
      map['subtitle'] = Variable<String>(subtitle.value);
    }
    if (avatarSeed.present) {
      map['avatar_seed'] = Variable<String>(avatarSeed.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (botAvatarMeta.present) {
      map['bot_avatar_meta'] = Variable<String>(botAvatarMeta.value);
    }
    if (canonicalSession.present) {
      map['canonical_session'] = Variable<String>(canonicalSession.value);
    }
    if (isGroup.present) {
      map['is_group'] = Variable<bool>(isGroup.value);
    }
    if (gatewayLabel.present) {
      map['gateway_label'] = Variable<String>(gatewayLabel.value);
    }
    if (lastActivity.present) {
      map['last_activity'] = Variable<DateTime>(lastActivity.value);
    }
    if (preview.present) {
      map['preview'] = Variable<String>(preview.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (pinned.present) {
      map['pinned'] = Variable<bool>(pinned.value);
    }
    if (pinnedGateway.present) {
      map['pinned_gateway'] = Variable<bool>(pinnedGateway.value);
    }
    if (groupRoomId.present) {
      map['group_room_id'] = Variable<String>(groupRoomId.value);
    }
    if (groupSyncRevision.present) {
      map['group_sync_revision'] = Variable<int>(groupSyncRevision.value);
    }
    if (groupSyncName.present) {
      map['group_sync_name'] = Variable<String>(groupSyncName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('connectionId: $connectionId, ')
          ..write('kind: $kind, ')
          ..write('gatewayId: $gatewayId, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('avatarSeed: $avatarSeed, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('botAvatarMeta: $botAvatarMeta, ')
          ..write('canonicalSession: $canonicalSession, ')
          ..write('isGroup: $isGroup, ')
          ..write('gatewayLabel: $gatewayLabel, ')
          ..write('lastActivity: $lastActivity, ')
          ..write('preview: $preview, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('pinned: $pinned, ')
          ..write('pinnedGateway: $pinnedGateway, ')
          ..write('groupRoomId: $groupRoomId, ')
          ..write('groupSyncRevision: $groupSyncRevision, ')
          ..write('groupSyncName: $groupSyncName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionIdMeta = const VerificationMeta(
    'connectionId',
  );
  @override
  late final GeneratedColumn<String> connectionId = GeneratedColumn<String>(
    'connection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authorNameMeta = const VerificationMeta(
    'authorName',
  );
  @override
  late final GeneratedColumn<String> authorName = GeneratedColumn<String>(
    'author_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorConnectionIdMeta =
      const VerificationMeta('authorConnectionId');
  @override
  late final GeneratedColumn<String> authorConnectionId =
      GeneratedColumn<String>(
        'author_connection_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _text_Meta = const VerificationMeta('text_');
  @override
  late final GeneratedColumn<String> text_ = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sendStateMeta = const VerificationMeta(
    'sendState',
  );
  @override
  late final GeneratedColumn<String> sendState = GeneratedColumn<String>(
    'send_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('sent'),
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('history'),
  );
  static const VerificationMeta _toolsJsonMeta = const VerificationMeta(
    'toolsJson',
  );
  @override
  late final GeneratedColumn<String> toolsJson = GeneratedColumn<String>(
    'tools_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _gatewayRowIdMeta = const VerificationMeta(
    'gatewayRowId',
  );
  @override
  late final GeneratedColumn<int> gatewayRowId = GeneratedColumn<int>(
    'gateway_row_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attachmentsJsonMeta = const VerificationMeta(
    'attachmentsJson',
  );
  @override
  late final GeneratedColumn<String> attachmentsJson = GeneratedColumn<String>(
    'attachments_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    connectionId,
    role,
    authorName,
    authorConnectionId,
    text_,
    timestamp,
    sendState,
    origin,
    toolsJson,
    gatewayRowId,
    seq,
    attachmentsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('connection_id')) {
      context.handle(
        _connectionIdMeta,
        connectionId.isAcceptableOrUnknown(
          data['connection_id']!,
          _connectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('author_name')) {
      context.handle(
        _authorNameMeta,
        authorName.isAcceptableOrUnknown(data['author_name']!, _authorNameMeta),
      );
    }
    if (data.containsKey('author_connection_id')) {
      context.handle(
        _authorConnectionIdMeta,
        authorConnectionId.isAcceptableOrUnknown(
          data['author_connection_id']!,
          _authorConnectionIdMeta,
        ),
      );
    }
    if (data.containsKey('text')) {
      context.handle(
        _text_Meta,
        text_.isAcceptableOrUnknown(data['text']!, _text_Meta),
      );
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    }
    if (data.containsKey('send_state')) {
      context.handle(
        _sendStateMeta,
        sendState.isAcceptableOrUnknown(data['send_state']!, _sendStateMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('tools_json')) {
      context.handle(
        _toolsJsonMeta,
        toolsJson.isAcceptableOrUnknown(data['tools_json']!, _toolsJsonMeta),
      );
    }
    if (data.containsKey('gateway_row_id')) {
      context.handle(
        _gatewayRowIdMeta,
        gatewayRowId.isAcceptableOrUnknown(
          data['gateway_row_id']!,
          _gatewayRowIdMeta,
        ),
      );
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('attachments_json')) {
      context.handle(
        _attachmentsJsonMeta,
        attachmentsJson.isAcceptableOrUnknown(
          data['attachments_json']!,
          _attachmentsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {conversationId, gatewayRowId},
  ];
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      connectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      authorName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_name'],
      ),
      authorConnectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_connection_id'],
      ),
      text_: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      ),
      sendState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}send_state'],
      )!,
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      )!,
      toolsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tools_json'],
      ),
      gatewayRowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}gateway_row_id'],
      ),
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      ),
      attachmentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attachments_json'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String conversationId;
  final String connectionId;
  final String role;
  final String? authorName;
  final String? authorConnectionId;
  final String text_;
  final DateTime? timestamp;
  final String sendState;
  final String origin;
  final String? toolsJson;
  final int? gatewayRowId;
  final int? seq;
  final String? attachmentsJson;
  const Message({
    required this.id,
    required this.conversationId,
    required this.connectionId,
    required this.role,
    this.authorName,
    this.authorConnectionId,
    required this.text_,
    this.timestamp,
    required this.sendState,
    required this.origin,
    this.toolsJson,
    this.gatewayRowId,
    this.seq,
    this.attachmentsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['connection_id'] = Variable<String>(connectionId);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || authorName != null) {
      map['author_name'] = Variable<String>(authorName);
    }
    if (!nullToAbsent || authorConnectionId != null) {
      map['author_connection_id'] = Variable<String>(authorConnectionId);
    }
    map['text'] = Variable<String>(text_);
    if (!nullToAbsent || timestamp != null) {
      map['timestamp'] = Variable<DateTime>(timestamp);
    }
    map['send_state'] = Variable<String>(sendState);
    map['origin'] = Variable<String>(origin);
    if (!nullToAbsent || toolsJson != null) {
      map['tools_json'] = Variable<String>(toolsJson);
    }
    if (!nullToAbsent || gatewayRowId != null) {
      map['gateway_row_id'] = Variable<int>(gatewayRowId);
    }
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    if (!nullToAbsent || attachmentsJson != null) {
      map['attachments_json'] = Variable<String>(attachmentsJson);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      connectionId: Value(connectionId),
      role: Value(role),
      authorName: authorName == null && nullToAbsent
          ? const Value.absent()
          : Value(authorName),
      authorConnectionId: authorConnectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(authorConnectionId),
      text_: Value(text_),
      timestamp: timestamp == null && nullToAbsent
          ? const Value.absent()
          : Value(timestamp),
      sendState: Value(sendState),
      origin: Value(origin),
      toolsJson: toolsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(toolsJson),
      gatewayRowId: gatewayRowId == null && nullToAbsent
          ? const Value.absent()
          : Value(gatewayRowId),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      attachmentsJson: attachmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(attachmentsJson),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      connectionId: serializer.fromJson<String>(json['connectionId']),
      role: serializer.fromJson<String>(json['role']),
      authorName: serializer.fromJson<String?>(json['authorName']),
      authorConnectionId: serializer.fromJson<String?>(
        json['authorConnectionId'],
      ),
      text_: serializer.fromJson<String>(json['text_']),
      timestamp: serializer.fromJson<DateTime?>(json['timestamp']),
      sendState: serializer.fromJson<String>(json['sendState']),
      origin: serializer.fromJson<String>(json['origin']),
      toolsJson: serializer.fromJson<String?>(json['toolsJson']),
      gatewayRowId: serializer.fromJson<int?>(json['gatewayRowId']),
      seq: serializer.fromJson<int?>(json['seq']),
      attachmentsJson: serializer.fromJson<String?>(json['attachmentsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'connectionId': serializer.toJson<String>(connectionId),
      'role': serializer.toJson<String>(role),
      'authorName': serializer.toJson<String?>(authorName),
      'authorConnectionId': serializer.toJson<String?>(authorConnectionId),
      'text_': serializer.toJson<String>(text_),
      'timestamp': serializer.toJson<DateTime?>(timestamp),
      'sendState': serializer.toJson<String>(sendState),
      'origin': serializer.toJson<String>(origin),
      'toolsJson': serializer.toJson<String?>(toolsJson),
      'gatewayRowId': serializer.toJson<int?>(gatewayRowId),
      'seq': serializer.toJson<int?>(seq),
      'attachmentsJson': serializer.toJson<String?>(attachmentsJson),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? connectionId,
    String? role,
    Value<String?> authorName = const Value.absent(),
    Value<String?> authorConnectionId = const Value.absent(),
    String? text_,
    Value<DateTime?> timestamp = const Value.absent(),
    String? sendState,
    String? origin,
    Value<String?> toolsJson = const Value.absent(),
    Value<int?> gatewayRowId = const Value.absent(),
    Value<int?> seq = const Value.absent(),
    Value<String?> attachmentsJson = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    connectionId: connectionId ?? this.connectionId,
    role: role ?? this.role,
    authorName: authorName.present ? authorName.value : this.authorName,
    authorConnectionId: authorConnectionId.present
        ? authorConnectionId.value
        : this.authorConnectionId,
    text_: text_ ?? this.text_,
    timestamp: timestamp.present ? timestamp.value : this.timestamp,
    sendState: sendState ?? this.sendState,
    origin: origin ?? this.origin,
    toolsJson: toolsJson.present ? toolsJson.value : this.toolsJson,
    gatewayRowId: gatewayRowId.present ? gatewayRowId.value : this.gatewayRowId,
    seq: seq.present ? seq.value : this.seq,
    attachmentsJson: attachmentsJson.present
        ? attachmentsJson.value
        : this.attachmentsJson,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      connectionId: data.connectionId.present
          ? data.connectionId.value
          : this.connectionId,
      role: data.role.present ? data.role.value : this.role,
      authorName: data.authorName.present
          ? data.authorName.value
          : this.authorName,
      authorConnectionId: data.authorConnectionId.present
          ? data.authorConnectionId.value
          : this.authorConnectionId,
      text_: data.text_.present ? data.text_.value : this.text_,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      sendState: data.sendState.present ? data.sendState.value : this.sendState,
      origin: data.origin.present ? data.origin.value : this.origin,
      toolsJson: data.toolsJson.present ? data.toolsJson.value : this.toolsJson,
      gatewayRowId: data.gatewayRowId.present
          ? data.gatewayRowId.value
          : this.gatewayRowId,
      seq: data.seq.present ? data.seq.value : this.seq,
      attachmentsJson: data.attachmentsJson.present
          ? data.attachmentsJson.value
          : this.attachmentsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('connectionId: $connectionId, ')
          ..write('role: $role, ')
          ..write('authorName: $authorName, ')
          ..write('authorConnectionId: $authorConnectionId, ')
          ..write('text_: $text_, ')
          ..write('timestamp: $timestamp, ')
          ..write('sendState: $sendState, ')
          ..write('origin: $origin, ')
          ..write('toolsJson: $toolsJson, ')
          ..write('gatewayRowId: $gatewayRowId, ')
          ..write('seq: $seq, ')
          ..write('attachmentsJson: $attachmentsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    connectionId,
    role,
    authorName,
    authorConnectionId,
    text_,
    timestamp,
    sendState,
    origin,
    toolsJson,
    gatewayRowId,
    seq,
    attachmentsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.connectionId == this.connectionId &&
          other.role == this.role &&
          other.authorName == this.authorName &&
          other.authorConnectionId == this.authorConnectionId &&
          other.text_ == this.text_ &&
          other.timestamp == this.timestamp &&
          other.sendState == this.sendState &&
          other.origin == this.origin &&
          other.toolsJson == this.toolsJson &&
          other.gatewayRowId == this.gatewayRowId &&
          other.seq == this.seq &&
          other.attachmentsJson == this.attachmentsJson);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> connectionId;
  final Value<String> role;
  final Value<String?> authorName;
  final Value<String?> authorConnectionId;
  final Value<String> text_;
  final Value<DateTime?> timestamp;
  final Value<String> sendState;
  final Value<String> origin;
  final Value<String?> toolsJson;
  final Value<int?> gatewayRowId;
  final Value<int?> seq;
  final Value<String?> attachmentsJson;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.connectionId = const Value.absent(),
    this.role = const Value.absent(),
    this.authorName = const Value.absent(),
    this.authorConnectionId = const Value.absent(),
    this.text_ = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.sendState = const Value.absent(),
    this.origin = const Value.absent(),
    this.toolsJson = const Value.absent(),
    this.gatewayRowId = const Value.absent(),
    this.seq = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String connectionId,
    required String role,
    this.authorName = const Value.absent(),
    this.authorConnectionId = const Value.absent(),
    this.text_ = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.sendState = const Value.absent(),
    this.origin = const Value.absent(),
    this.toolsJson = const Value.absent(),
    this.gatewayRowId = const Value.absent(),
    this.seq = const Value.absent(),
    this.attachmentsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       connectionId = Value(connectionId),
       role = Value(role);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? connectionId,
    Expression<String>? role,
    Expression<String>? authorName,
    Expression<String>? authorConnectionId,
    Expression<String>? text_,
    Expression<DateTime>? timestamp,
    Expression<String>? sendState,
    Expression<String>? origin,
    Expression<String>? toolsJson,
    Expression<int>? gatewayRowId,
    Expression<int>? seq,
    Expression<String>? attachmentsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (connectionId != null) 'connection_id': connectionId,
      if (role != null) 'role': role,
      if (authorName != null) 'author_name': authorName,
      if (authorConnectionId != null)
        'author_connection_id': authorConnectionId,
      if (text_ != null) 'text': text_,
      if (timestamp != null) 'timestamp': timestamp,
      if (sendState != null) 'send_state': sendState,
      if (origin != null) 'origin': origin,
      if (toolsJson != null) 'tools_json': toolsJson,
      if (gatewayRowId != null) 'gateway_row_id': gatewayRowId,
      if (seq != null) 'seq': seq,
      if (attachmentsJson != null) 'attachments_json': attachmentsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? connectionId,
    Value<String>? role,
    Value<String?>? authorName,
    Value<String?>? authorConnectionId,
    Value<String>? text_,
    Value<DateTime?>? timestamp,
    Value<String>? sendState,
    Value<String>? origin,
    Value<String?>? toolsJson,
    Value<int?>? gatewayRowId,
    Value<int?>? seq,
    Value<String?>? attachmentsJson,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      connectionId: connectionId ?? this.connectionId,
      role: role ?? this.role,
      authorName: authorName ?? this.authorName,
      authorConnectionId: authorConnectionId ?? this.authorConnectionId,
      text_: text_ ?? this.text_,
      timestamp: timestamp ?? this.timestamp,
      sendState: sendState ?? this.sendState,
      origin: origin ?? this.origin,
      toolsJson: toolsJson ?? this.toolsJson,
      gatewayRowId: gatewayRowId ?? this.gatewayRowId,
      seq: seq ?? this.seq,
      attachmentsJson: attachmentsJson ?? this.attachmentsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (connectionId.present) {
      map['connection_id'] = Variable<String>(connectionId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (authorName.present) {
      map['author_name'] = Variable<String>(authorName.value);
    }
    if (authorConnectionId.present) {
      map['author_connection_id'] = Variable<String>(authorConnectionId.value);
    }
    if (text_.present) {
      map['text'] = Variable<String>(text_.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (sendState.present) {
      map['send_state'] = Variable<String>(sendState.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (toolsJson.present) {
      map['tools_json'] = Variable<String>(toolsJson.value);
    }
    if (gatewayRowId.present) {
      map['gateway_row_id'] = Variable<int>(gatewayRowId.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (attachmentsJson.present) {
      map['attachments_json'] = Variable<String>(attachmentsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('connectionId: $connectionId, ')
          ..write('role: $role, ')
          ..write('authorName: $authorName, ')
          ..write('authorConnectionId: $authorConnectionId, ')
          ..write('text_: $text_, ')
          ..write('timestamp: $timestamp, ')
          ..write('sendState: $sendState, ')
          ..write('origin: $origin, ')
          ..write('toolsJson: $toolsJson, ')
          ..write('gatewayRowId: $gatewayRowId, ')
          ..write('seq: $seq, ')
          ..write('attachmentsJson: $attachmentsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DraftsTable extends Drafts with TableInfo<$DraftsTable, Draft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _text_Meta = const VerificationMeta('text_');
  @override
  late final GeneratedColumn<String> text_ = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  List<GeneratedColumn> get $columns => [conversationId, text_, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<Draft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('text')) {
      context.handle(
        _text_Meta,
        text_.isAcceptableOrUnknown(data['text']!, _text_Meta),
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
  Set<GeneratedColumn> get $primaryKey => {conversationId};
  @override
  Draft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Draft(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      text_: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DraftsTable createAlias(String alias) {
    return $DraftsTable(attachedDatabase, alias);
  }
}

class Draft extends DataClass implements Insertable<Draft> {
  final String conversationId;
  final String text_;
  final DateTime updatedAt;
  const Draft({
    required this.conversationId,
    required this.text_,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['text'] = Variable<String>(text_);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DraftsCompanion toCompanion(bool nullToAbsent) {
    return DraftsCompanion(
      conversationId: Value(conversationId),
      text_: Value(text_),
      updatedAt: Value(updatedAt),
    );
  }

  factory Draft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Draft(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      text_: serializer.fromJson<String>(json['text_']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'text_': serializer.toJson<String>(text_),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Draft copyWith({
    String? conversationId,
    String? text_,
    DateTime? updatedAt,
  }) => Draft(
    conversationId: conversationId ?? this.conversationId,
    text_: text_ ?? this.text_,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Draft copyWithCompanion(DraftsCompanion data) {
    return Draft(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      text_: data.text_.present ? data.text_.value : this.text_,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Draft(')
          ..write('conversationId: $conversationId, ')
          ..write('text_: $text_, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(conversationId, text_, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Draft &&
          other.conversationId == this.conversationId &&
          other.text_ == this.text_ &&
          other.updatedAt == this.updatedAt);
}

class DraftsCompanion extends UpdateCompanion<Draft> {
  final Value<String> conversationId;
  final Value<String> text_;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DraftsCompanion({
    this.conversationId = const Value.absent(),
    this.text_ = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DraftsCompanion.insert({
    required String conversationId,
    this.text_ = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId);
  static Insertable<Draft> custom({
    Expression<String>? conversationId,
    Expression<String>? text_,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (text_ != null) 'text': text_,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DraftsCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? text_,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DraftsCompanion(
      conversationId: conversationId ?? this.conversationId,
      text_: text_ ?? this.text_,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (text_.present) {
      map['text'] = Variable<String>(text_.value);
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
    return (StringBuffer('DraftsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('text_: $text_, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SshHostsTable extends SshHosts with TableInfo<$SshHostsTable, SshHost> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SshHostsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(22),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _authKindMeta = const VerificationMeta(
    'authKind',
  );
  @override
  late final GeneratedColumn<String> authKind = GeneratedColumn<String>(
    'auth_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _knownFingerprintMeta = const VerificationMeta(
    'knownFingerprint',
  );
  @override
  late final GeneratedColumn<String> knownFingerprint = GeneratedColumn<String>(
    'known_fingerprint',
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    host,
    port,
    username,
    authKind,
    knownFingerprint,
    enabled,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ssh_hosts';
  @override
  VerificationContext validateIntegrity(
    Insertable<SshHost> instance, {
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
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('auth_kind')) {
      context.handle(
        _authKindMeta,
        authKind.isAcceptableOrUnknown(data['auth_kind']!, _authKindMeta),
      );
    } else if (isInserting) {
      context.missing(_authKindMeta);
    }
    if (data.containsKey('known_fingerprint')) {
      context.handle(
        _knownFingerprintMeta,
        knownFingerprint.isAcceptableOrUnknown(
          data['known_fingerprint']!,
          _knownFingerprintMeta,
        ),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SshHost map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SshHost(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      authKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}auth_kind'],
      )!,
      knownFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}known_fingerprint'],
      ),
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SshHostsTable createAlias(String alias) {
    return $SshHostsTable(attachedDatabase, alias);
  }
}

class SshHost extends DataClass implements Insertable<SshHost> {
  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String authKind;
  final String? knownFingerprint;
  final bool enabled;
  final DateTime createdAt;
  const SshHost({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authKind,
    this.knownFingerprint,
    required this.enabled,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['username'] = Variable<String>(username);
    map['auth_kind'] = Variable<String>(authKind);
    if (!nullToAbsent || knownFingerprint != null) {
      map['known_fingerprint'] = Variable<String>(knownFingerprint);
    }
    map['enabled'] = Variable<bool>(enabled);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SshHostsCompanion toCompanion(bool nullToAbsent) {
    return SshHostsCompanion(
      id: Value(id),
      name: Value(name),
      host: Value(host),
      port: Value(port),
      username: Value(username),
      authKind: Value(authKind),
      knownFingerprint: knownFingerprint == null && nullToAbsent
          ? const Value.absent()
          : Value(knownFingerprint),
      enabled: Value(enabled),
      createdAt: Value(createdAt),
    );
  }

  factory SshHost.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SshHost(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      username: serializer.fromJson<String>(json['username']),
      authKind: serializer.fromJson<String>(json['authKind']),
      knownFingerprint: serializer.fromJson<String?>(json['knownFingerprint']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'username': serializer.toJson<String>(username),
      'authKind': serializer.toJson<String>(authKind),
      'knownFingerprint': serializer.toJson<String?>(knownFingerprint),
      'enabled': serializer.toJson<bool>(enabled),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  SshHost copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? authKind,
    Value<String?> knownFingerprint = const Value.absent(),
    bool? enabled,
    DateTime? createdAt,
  }) => SshHost(
    id: id ?? this.id,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    username: username ?? this.username,
    authKind: authKind ?? this.authKind,
    knownFingerprint: knownFingerprint.present
        ? knownFingerprint.value
        : this.knownFingerprint,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt ?? this.createdAt,
  );
  SshHost copyWithCompanion(SshHostsCompanion data) {
    return SshHost(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      username: data.username.present ? data.username.value : this.username,
      authKind: data.authKind.present ? data.authKind.value : this.authKind,
      knownFingerprint: data.knownFingerprint.present
          ? data.knownFingerprint.value
          : this.knownFingerprint,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SshHost(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('authKind: $authKind, ')
          ..write('knownFingerprint: $knownFingerprint, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    host,
    port,
    username,
    authKind,
    knownFingerprint,
    enabled,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SshHost &&
          other.id == this.id &&
          other.name == this.name &&
          other.host == this.host &&
          other.port == this.port &&
          other.username == this.username &&
          other.authKind == this.authKind &&
          other.knownFingerprint == this.knownFingerprint &&
          other.enabled == this.enabled &&
          other.createdAt == this.createdAt);
}

class SshHostsCompanion extends UpdateCompanion<SshHost> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> host;
  final Value<int> port;
  final Value<String> username;
  final Value<String> authKind;
  final Value<String?> knownFingerprint;
  final Value<bool> enabled;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SshHostsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.username = const Value.absent(),
    this.authKind = const Value.absent(),
    this.knownFingerprint = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SshHostsCompanion.insert({
    required String id,
    required String name,
    required String host,
    this.port = const Value.absent(),
    required String username,
    required String authKind,
    this.knownFingerprint = const Value.absent(),
    this.enabled = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       host = Value(host),
       username = Value(username),
       authKind = Value(authKind);
  static Insertable<SshHost> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? username,
    Expression<String>? authKind,
    Expression<String>? knownFingerprint,
    Expression<bool>? enabled,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (username != null) 'username': username,
      if (authKind != null) 'auth_kind': authKind,
      if (knownFingerprint != null) 'known_fingerprint': knownFingerprint,
      if (enabled != null) 'enabled': enabled,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SshHostsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? host,
    Value<int>? port,
    Value<String>? username,
    Value<String>? authKind,
    Value<String?>? knownFingerprint,
    Value<bool>? enabled,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return SshHostsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authKind: authKind ?? this.authKind,
      knownFingerprint: knownFingerprint ?? this.knownFingerprint,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
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
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (authKind.present) {
      map['auth_kind'] = Variable<String>(authKind.value);
    }
    if (knownFingerprint.present) {
      map['known_fingerprint'] = Variable<String>(knownFingerprint.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SshHostsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('username: $username, ')
          ..write('authKind: $authKind, ')
          ..write('knownFingerprint: $knownFingerprint, ')
          ..write('enabled: $enabled, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConnectionsTable connections = $ConnectionsTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $DraftsTable drafts = $DraftsTable(this);
  late final $SshHostsTable sshHosts = $SshHostsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    connections,
    conversations,
    messages,
    drafts,
    sshHosts,
  ];
}

typedef $$ConnectionsTableCreateCompanionBuilder =
    ConnectionsCompanion Function({
      required String id,
      required String name,
      required String scheme,
      required String host,
      required int port,
      Value<String> basePath,
      required String authKind,
      Value<String> username,
      Value<bool> allowInsecureTls,
      Value<bool> enabled,
      Value<int> displayOrder,
      Value<String?> installId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ConnectionsTableUpdateCompanionBuilder =
    ConnectionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> scheme,
      Value<String> host,
      Value<int> port,
      Value<String> basePath,
      Value<String> authKind,
      Value<String> username,
      Value<bool> allowInsecureTls,
      Value<bool> enabled,
      Value<int> displayOrder,
      Value<String?> installId,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$ConnectionsTableFilterComposer
    extends Composer<_$AppDatabase, $ConnectionsTable> {
  $$ConnectionsTableFilterComposer({
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

  ColumnFilters<String> get scheme => $composableBuilder(
    column: $table.scheme,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get basePath => $composableBuilder(
    column: $table.basePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authKind => $composableBuilder(
    column: $table.authKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowInsecureTls => $composableBuilder(
    column: $table.allowInsecureTls,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get installId => $composableBuilder(
    column: $table.installId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConnectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConnectionsTable> {
  $$ConnectionsTableOrderingComposer({
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

  ColumnOrderings<String> get scheme => $composableBuilder(
    column: $table.scheme,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get basePath => $composableBuilder(
    column: $table.basePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authKind => $composableBuilder(
    column: $table.authKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowInsecureTls => $composableBuilder(
    column: $table.allowInsecureTls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get installId => $composableBuilder(
    column: $table.installId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConnectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConnectionsTable> {
  $$ConnectionsTableAnnotationComposer({
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

  GeneratedColumn<String> get scheme =>
      $composableBuilder(column: $table.scheme, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get basePath =>
      $composableBuilder(column: $table.basePath, builder: (column) => column);

  GeneratedColumn<String> get authKind =>
      $composableBuilder(column: $table.authKind, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<bool> get allowInsecureTls => $composableBuilder(
    column: $table.allowInsecureTls,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<String> get installId =>
      $composableBuilder(column: $table.installId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ConnectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConnectionsTable,
          Connection,
          $$ConnectionsTableFilterComposer,
          $$ConnectionsTableOrderingComposer,
          $$ConnectionsTableAnnotationComposer,
          $$ConnectionsTableCreateCompanionBuilder,
          $$ConnectionsTableUpdateCompanionBuilder,
          (
            Connection,
            BaseReferences<_$AppDatabase, $ConnectionsTable, Connection>,
          ),
          Connection,
          PrefetchHooks Function()
        > {
  $$ConnectionsTableTableManager(_$AppDatabase db, $ConnectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConnectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConnectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConnectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> scheme = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> basePath = const Value.absent(),
                Value<String> authKind = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<bool> allowInsecureTls = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> installId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionsCompanion(
                id: id,
                name: name,
                scheme: scheme,
                host: host,
                port: port,
                basePath: basePath,
                authKind: authKind,
                username: username,
                allowInsecureTls: allowInsecureTls,
                enabled: enabled,
                displayOrder: displayOrder,
                installId: installId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String scheme,
                required String host,
                required int port,
                Value<String> basePath = const Value.absent(),
                required String authKind,
                Value<String> username = const Value.absent(),
                Value<bool> allowInsecureTls = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<String?> installId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionsCompanion.insert(
                id: id,
                name: name,
                scheme: scheme,
                host: host,
                port: port,
                basePath: basePath,
                authKind: authKind,
                username: username,
                allowInsecureTls: allowInsecureTls,
                enabled: enabled,
                displayOrder: displayOrder,
                installId: installId,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConnectionsTable, Connection>(table),
                  BaseReferences<_$AppDatabase, $ConnectionsTable, Connection>(
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

typedef $$ConnectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConnectionsTable,
      Connection,
      $$ConnectionsTableFilterComposer,
      $$ConnectionsTableOrderingComposer,
      $$ConnectionsTableAnnotationComposer,
      $$ConnectionsTableCreateCompanionBuilder,
      $$ConnectionsTableUpdateCompanionBuilder,
      (
        Connection,
        BaseReferences<_$AppDatabase, $ConnectionsTable, Connection>,
      ),
      Connection,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      required String connectionId,
      required String kind,
      required String gatewayId,
      required String title,
      Value<String?> subtitle,
      Value<String?> avatarSeed,
      Value<String?> avatarUrl,
      Value<String?> botAvatarMeta,
      Value<String?> canonicalSession,
      Value<bool> isGroup,
      Value<String?> gatewayLabel,
      Value<DateTime?> lastActivity,
      Value<String?> preview,
      Value<int> unreadCount,
      Value<int> sortOrder,
      Value<bool> pinned,
      Value<bool> pinnedGateway,
      Value<String?> groupRoomId,
      Value<int> groupSyncRevision,
      Value<String?> groupSyncName,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<String> connectionId,
      Value<String> kind,
      Value<String> gatewayId,
      Value<String> title,
      Value<String?> subtitle,
      Value<String?> avatarSeed,
      Value<String?> avatarUrl,
      Value<String?> botAvatarMeta,
      Value<String?> canonicalSession,
      Value<bool> isGroup,
      Value<String?> gatewayLabel,
      Value<DateTime?> lastActivity,
      Value<String?> preview,
      Value<int> unreadCount,
      Value<int> sortOrder,
      Value<bool> pinned,
      Value<bool> pinnedGateway,
      Value<String?> groupRoomId,
      Value<int> groupSyncRevision,
      Value<String?> groupSyncName,
      Value<int> rowid,
    });

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
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

  ColumnFilters<String> get connectionId => $composableBuilder(
    column: $table.connectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitle => $composableBuilder(
    column: $table.subtitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarSeed => $composableBuilder(
    column: $table.avatarSeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get botAvatarMeta => $composableBuilder(
    column: $table.botAvatarMeta,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalSession => $composableBuilder(
    column: $table.canonicalSession,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isGroup => $composableBuilder(
    column: $table.isGroup,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gatewayLabel => $composableBuilder(
    column: $table.gatewayLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastActivity => $composableBuilder(
    column: $table.lastActivity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pinnedGateway => $composableBuilder(
    column: $table.pinnedGateway,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupRoomId => $composableBuilder(
    column: $table.groupRoomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get groupSyncRevision => $composableBuilder(
    column: $table.groupSyncRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupSyncName => $composableBuilder(
    column: $table.groupSyncName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
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

  ColumnOrderings<String> get connectionId => $composableBuilder(
    column: $table.connectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gatewayId => $composableBuilder(
    column: $table.gatewayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitle => $composableBuilder(
    column: $table.subtitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarSeed => $composableBuilder(
    column: $table.avatarSeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
    column: $table.avatarUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get botAvatarMeta => $composableBuilder(
    column: $table.botAvatarMeta,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalSession => $composableBuilder(
    column: $table.canonicalSession,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isGroup => $composableBuilder(
    column: $table.isGroup,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gatewayLabel => $composableBuilder(
    column: $table.gatewayLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastActivity => $composableBuilder(
    column: $table.lastActivity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get preview => $composableBuilder(
    column: $table.preview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinned => $composableBuilder(
    column: $table.pinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pinnedGateway => $composableBuilder(
    column: $table.pinnedGateway,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupRoomId => $composableBuilder(
    column: $table.groupRoomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get groupSyncRevision => $composableBuilder(
    column: $table.groupSyncRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupSyncName => $composableBuilder(
    column: $table.groupSyncName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get connectionId => $composableBuilder(
    column: $table.connectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get gatewayId =>
      $composableBuilder(column: $table.gatewayId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subtitle =>
      $composableBuilder(column: $table.subtitle, builder: (column) => column);

  GeneratedColumn<String> get avatarSeed => $composableBuilder(
    column: $table.avatarSeed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get botAvatarMeta => $composableBuilder(
    column: $table.botAvatarMeta,
    builder: (column) => column,
  );

  GeneratedColumn<String> get canonicalSession => $composableBuilder(
    column: $table.canonicalSession,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isGroup =>
      $composableBuilder(column: $table.isGroup, builder: (column) => column);

  GeneratedColumn<String> get gatewayLabel => $composableBuilder(
    column: $table.gatewayLabel,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastActivity => $composableBuilder(
    column: $table.lastActivity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get preview =>
      $composableBuilder(column: $table.preview, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get pinned =>
      $composableBuilder(column: $table.pinned, builder: (column) => column);

  GeneratedColumn<bool> get pinnedGateway => $composableBuilder(
    column: $table.pinnedGateway,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupRoomId => $composableBuilder(
    column: $table.groupRoomId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get groupSyncRevision => $composableBuilder(
    column: $table.groupSyncRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupSyncName => $composableBuilder(
    column: $table.groupSyncName,
    builder: (column) => column,
  );
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (
            Conversation,
            BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>,
          ),
          Conversation,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> connectionId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> gatewayId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> subtitle = const Value.absent(),
                Value<String?> avatarSeed = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> botAvatarMeta = const Value.absent(),
                Value<String?> canonicalSession = const Value.absent(),
                Value<bool> isGroup = const Value.absent(),
                Value<String?> gatewayLabel = const Value.absent(),
                Value<DateTime?> lastActivity = const Value.absent(),
                Value<String?> preview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> pinnedGateway = const Value.absent(),
                Value<String?> groupRoomId = const Value.absent(),
                Value<int> groupSyncRevision = const Value.absent(),
                Value<String?> groupSyncName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                connectionId: connectionId,
                kind: kind,
                gatewayId: gatewayId,
                title: title,
                subtitle: subtitle,
                avatarSeed: avatarSeed,
                avatarUrl: avatarUrl,
                botAvatarMeta: botAvatarMeta,
                canonicalSession: canonicalSession,
                isGroup: isGroup,
                gatewayLabel: gatewayLabel,
                lastActivity: lastActivity,
                preview: preview,
                unreadCount: unreadCount,
                sortOrder: sortOrder,
                pinned: pinned,
                pinnedGateway: pinnedGateway,
                groupRoomId: groupRoomId,
                groupSyncRevision: groupSyncRevision,
                groupSyncName: groupSyncName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String connectionId,
                required String kind,
                required String gatewayId,
                required String title,
                Value<String?> subtitle = const Value.absent(),
                Value<String?> avatarSeed = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<String?> botAvatarMeta = const Value.absent(),
                Value<String?> canonicalSession = const Value.absent(),
                Value<bool> isGroup = const Value.absent(),
                Value<String?> gatewayLabel = const Value.absent(),
                Value<DateTime?> lastActivity = const Value.absent(),
                Value<String?> preview = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> pinned = const Value.absent(),
                Value<bool> pinnedGateway = const Value.absent(),
                Value<String?> groupRoomId = const Value.absent(),
                Value<int> groupSyncRevision = const Value.absent(),
                Value<String?> groupSyncName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                connectionId: connectionId,
                kind: kind,
                gatewayId: gatewayId,
                title: title,
                subtitle: subtitle,
                avatarSeed: avatarSeed,
                avatarUrl: avatarUrl,
                botAvatarMeta: botAvatarMeta,
                canonicalSession: canonicalSession,
                isGroup: isGroup,
                gatewayLabel: gatewayLabel,
                lastActivity: lastActivity,
                preview: preview,
                unreadCount: unreadCount,
                sortOrder: sortOrder,
                pinned: pinned,
                pinnedGateway: pinnedGateway,
                groupRoomId: groupRoomId,
                groupSyncRevision: groupSyncRevision,
                groupSyncName: groupSyncName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationsTable, Conversation>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ConversationsTable,
                    Conversation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (
        Conversation,
        BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>,
      ),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String conversationId,
      required String connectionId,
      required String role,
      Value<String?> authorName,
      Value<String?> authorConnectionId,
      Value<String> text_,
      Value<DateTime?> timestamp,
      Value<String> sendState,
      Value<String> origin,
      Value<String?> toolsJson,
      Value<int?> gatewayRowId,
      Value<int?> seq,
      Value<String?> attachmentsJson,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<String> connectionId,
      Value<String> role,
      Value<String?> authorName,
      Value<String?> authorConnectionId,
      Value<String> text_,
      Value<DateTime?> timestamp,
      Value<String> sendState,
      Value<String> origin,
      Value<String?> toolsJson,
      Value<int?> gatewayRowId,
      Value<int?> seq,
      Value<String?> attachmentsJson,
      Value<int> rowid,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
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

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionId => $composableBuilder(
    column: $table.connectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authorConnectionId => $composableBuilder(
    column: $table.authorConnectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sendState => $composableBuilder(
    column: $table.sendState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toolsJson => $composableBuilder(
    column: $table.toolsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get gatewayRowId => $composableBuilder(
    column: $table.gatewayRowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
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

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionId => $composableBuilder(
    column: $table.connectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authorConnectionId => $composableBuilder(
    column: $table.authorConnectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sendState => $composableBuilder(
    column: $table.sendState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toolsJson => $composableBuilder(
    column: $table.toolsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get gatewayRowId => $composableBuilder(
    column: $table.gatewayRowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get connectionId => $composableBuilder(
    column: $table.connectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get authorName => $composableBuilder(
    column: $table.authorName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get authorConnectionId => $composableBuilder(
    column: $table.authorConnectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get text_ =>
      $composableBuilder(column: $table.text_, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get sendState =>
      $composableBuilder(column: $table.sendState, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get toolsJson =>
      $composableBuilder(column: $table.toolsJson, builder: (column) => column);

  GeneratedColumn<int> get gatewayRowId => $composableBuilder(
    column: $table.gatewayRowId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get attachmentsJson => $composableBuilder(
    column: $table.attachmentsJson,
    builder: (column) => column,
  );
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> connectionId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String?> authorName = const Value.absent(),
                Value<String?> authorConnectionId = const Value.absent(),
                Value<String> text_ = const Value.absent(),
                Value<DateTime?> timestamp = const Value.absent(),
                Value<String> sendState = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> toolsJson = const Value.absent(),
                Value<int?> gatewayRowId = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                conversationId: conversationId,
                connectionId: connectionId,
                role: role,
                authorName: authorName,
                authorConnectionId: authorConnectionId,
                text_: text_,
                timestamp: timestamp,
                sendState: sendState,
                origin: origin,
                toolsJson: toolsJson,
                gatewayRowId: gatewayRowId,
                seq: seq,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String connectionId,
                required String role,
                Value<String?> authorName = const Value.absent(),
                Value<String?> authorConnectionId = const Value.absent(),
                Value<String> text_ = const Value.absent(),
                Value<DateTime?> timestamp = const Value.absent(),
                Value<String> sendState = const Value.absent(),
                Value<String> origin = const Value.absent(),
                Value<String?> toolsJson = const Value.absent(),
                Value<int?> gatewayRowId = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<String?> attachmentsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                connectionId: connectionId,
                role: role,
                authorName: authorName,
                authorConnectionId: authorConnectionId,
                text_: text_,
                timestamp: timestamp,
                sendState: sendState,
                origin: origin,
                toolsJson: toolsJson,
                gatewayRowId: gatewayRowId,
                seq: seq,
                attachmentsJson: attachmentsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  BaseReferences<_$AppDatabase, $MessagesTable, Message>(
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

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $$DraftsTableCreateCompanionBuilder =
    DraftsCompanion Function({
      required String conversationId,
      Value<String> text_,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$DraftsTableUpdateCompanionBuilder =
    DraftsCompanion Function({
      Value<String> conversationId,
      Value<String> text_,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DraftsTableFilterComposer
    extends Composer<_$AppDatabase, $DraftsTable> {
  $$DraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DraftsTableOrderingComposer
    extends Composer<_$AppDatabase, $DraftsTable> {
  $$DraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get text_ => $composableBuilder(
    column: $table.text_,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DraftsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DraftsTable> {
  $$DraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get text_ =>
      $composableBuilder(column: $table.text_, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DraftsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DraftsTable,
          Draft,
          $$DraftsTableFilterComposer,
          $$DraftsTableOrderingComposer,
          $$DraftsTableAnnotationComposer,
          $$DraftsTableCreateCompanionBuilder,
          $$DraftsTableUpdateCompanionBuilder,
          (Draft, BaseReferences<_$AppDatabase, $DraftsTable, Draft>),
          Draft,
          PrefetchHooks Function()
        > {
  $$DraftsTableTableManager(_$AppDatabase db, $DraftsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> text_ = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion(
                conversationId: conversationId,
                text_: text_,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                Value<String> text_ = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DraftsCompanion.insert(
                conversationId: conversationId,
                text_: text_,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DraftsTable, Draft>(table),
                  BaseReferences<_$AppDatabase, $DraftsTable, Draft>(
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

typedef $$DraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DraftsTable,
      Draft,
      $$DraftsTableFilterComposer,
      $$DraftsTableOrderingComposer,
      $$DraftsTableAnnotationComposer,
      $$DraftsTableCreateCompanionBuilder,
      $$DraftsTableUpdateCompanionBuilder,
      (Draft, BaseReferences<_$AppDatabase, $DraftsTable, Draft>),
      Draft,
      PrefetchHooks Function()
    >;
typedef $$SshHostsTableCreateCompanionBuilder =
    SshHostsCompanion Function({
      required String id,
      required String name,
      required String host,
      Value<int> port,
      required String username,
      required String authKind,
      Value<String?> knownFingerprint,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$SshHostsTableUpdateCompanionBuilder =
    SshHostsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> host,
      Value<int> port,
      Value<String> username,
      Value<String> authKind,
      Value<String?> knownFingerprint,
      Value<bool> enabled,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$SshHostsTableFilterComposer
    extends Composer<_$AppDatabase, $SshHostsTable> {
  $$SshHostsTableFilterComposer({
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

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get authKind => $composableBuilder(
    column: $table.authKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get knownFingerprint => $composableBuilder(
    column: $table.knownFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SshHostsTableOrderingComposer
    extends Composer<_$AppDatabase, $SshHostsTable> {
  $$SshHostsTableOrderingComposer({
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

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get authKind => $composableBuilder(
    column: $table.authKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get knownFingerprint => $composableBuilder(
    column: $table.knownFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SshHostsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SshHostsTable> {
  $$SshHostsTableAnnotationComposer({
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

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get authKind =>
      $composableBuilder(column: $table.authKind, builder: (column) => column);

  GeneratedColumn<String> get knownFingerprint => $composableBuilder(
    column: $table.knownFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SshHostsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SshHostsTable,
          SshHost,
          $$SshHostsTableFilterComposer,
          $$SshHostsTableOrderingComposer,
          $$SshHostsTableAnnotationComposer,
          $$SshHostsTableCreateCompanionBuilder,
          $$SshHostsTableUpdateCompanionBuilder,
          (SshHost, BaseReferences<_$AppDatabase, $SshHostsTable, SshHost>),
          SshHost,
          PrefetchHooks Function()
        > {
  $$SshHostsTableTableManager(_$AppDatabase db, $SshHostsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SshHostsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SshHostsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SshHostsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> authKind = const Value.absent(),
                Value<String?> knownFingerprint = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SshHostsCompanion(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                authKind: authKind,
                knownFingerprint: knownFingerprint,
                enabled: enabled,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String host,
                Value<int> port = const Value.absent(),
                required String username,
                required String authKind,
                Value<String?> knownFingerprint = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SshHostsCompanion.insert(
                id: id,
                name: name,
                host: host,
                port: port,
                username: username,
                authKind: authKind,
                knownFingerprint: knownFingerprint,
                enabled: enabled,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SshHostsTable, SshHost>(table),
                  BaseReferences<_$AppDatabase, $SshHostsTable, SshHost>(
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

typedef $$SshHostsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SshHostsTable,
      SshHost,
      $$SshHostsTableFilterComposer,
      $$SshHostsTableOrderingComposer,
      $$SshHostsTableAnnotationComposer,
      $$SshHostsTableCreateCompanionBuilder,
      $$SshHostsTableUpdateCompanionBuilder,
      (SshHost, BaseReferences<_$AppDatabase, $SshHostsTable, SshHost>),
      SshHost,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConnectionsTableTableManager get connections =>
      $$ConnectionsTableTableManager(_db, _db.connections);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$DraftsTableTableManager get drafts =>
      $$DraftsTableTableManager(_db, _db.drafts);
  $$SshHostsTableTableManager get sshHosts =>
      $$SshHostsTableTableManager(_db, _db.sshHosts);
}
