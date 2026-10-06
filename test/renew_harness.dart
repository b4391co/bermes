import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_pocket/clients/hermes/connection_manager.dart';
import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/data/secure/secure_store.dart';
import 'package:hermes_pocket/clients/hermes/http_client.dart';

/// Arnés del test de renovación: BD drift en memoria + SecureStore falso que
/// CUENTA los logins (no toca keystore real). Requiere el fake gateway real
/// en :9120 lanzado con FAKE_WS_REJECT=1 (tools/fake_gateway.py): su WS
/// cierra 4401 antes de gateway.ready, que es exactamente la señal que
/// dispara `authExpired` en producción (chat_ws.py:139-151).
class RenewHarness {
  RenewHarness({required this.connectionPort});

  final int connectionPort;
  late final AppDatabase db;
  late final CountingSecrets secrets;
  late final ConnectionManager manager;
  late final List<Connection> rows;

  Future<void> setUp() async {
    db = AppDatabase(NativeDatabase.memory());
    secrets = CountingSecrets();
    manager = ConnectionManager();
    await db
        .into(db.connections)
        .insert(ConnectionsCompanion.insert(
          id: 'renew-1',
          name: 'FakeA',
          scheme: 'http',
          host: '127.0.0.1',
          port: connectionPort,
          authKind: 'password',
          username: const Value('test'),
          allowInsecureTls: const Value(false),
          enabled: const Value(true),
          displayOrder: const Value(0),
          createdAt: Value(DateTime.now()),
        ));
    rows = await db.select(db.connections).get();
  }

  Future<void> tearDown() async {
    await manager.disposeAll();
    await db.close();
  }
}

class CountingSecrets implements SecureStore {
  int readCount = 0;
  DateTime lastReadAt = DateTime.fromMillisecondsSinceEpoch(0);
  final sessions = <String, StoredSession>{};

  @override
  Future<String?> readRememberedPassword(String connectionId) async {
    readCount++;
    lastReadAt = DateTime.now();
    return 'hermespass';
  }

  @override
  Future<StoredSession?> readSession(String connectionId) async =>
      sessions[connectionId];

  @override
  Future<void> writeSession(String connectionId, StoredSession session) async {
    sessions[connectionId] = session;
  }

  @override
  Future<void> deleteSession(String connectionId) async =>
      sessions.remove(connectionId);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
