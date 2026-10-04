import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/clients/hermes/bot_meta.dart';
import 'package:hermes_pocket/features/conversations/group_rooms.dart';
import 'package:hermes_pocket/features/conversations/group_sync.dart';
import 'package:drift/native.dart';

List<Map<String,Object?>> _parse(List raw) => raw.cast<Map<String,Object?>>();

void main() {
  test('payloads reales de los dos fakes → subtítulo 2 miembros', () async {
    final db = AppDatabase(NativeDatabase.memory());
    Future<List> profiles(String url) async {
      final c = await HttpClient().getUrl(Uri.parse('$url/api/profiles'));
      c.headers.set('X-Hermes-Session-Token', 'loopback-session-token-1');
      final r = await c.close();
      final body = await r.transform(const Utf8Decoder()).join();
      return (jsonDecode(body) as Map)['profiles'];
    }
    final a = await profiles('http://127.0.0.1:9120');
    final b = await profiles('http://127.0.0.1:9121');
    List<GatewayProfileSnapshot> snaps(List raw) => [
      for (final p in _parse(raw))
        GatewayProfileSnapshot(
          name: p['name'] as String,
          groups: GroupSyncSnapshot.tryParse(
            (p['ui_meta'] is Map) ? (p['ui_meta'] as Map)['hermes-bots-groups'] : null,
          ) ?? GroupSyncSnapshot.empty,
          membershipNames: {...?BotRosterMeta.fromProfile(p)?.groups},
        ),
    ];
    await syncGroupMirrors(db: db, connections: [
      ConnectionGroupState(id: 'A', label: 'FakeA', profiles: snaps(a), titles: const {}, createdAt: DateTime(2026,1,1), displayOrder: 0, installId: 'fake-install-a'),
      ConnectionGroupState(id: 'B', label: 'FakeB', profiles: snaps(b), titles: const {}, createdAt: DateTime(2026,2,1), displayOrder: 1, installId: 'fake-install-b'),
    ]);
    final rows = await (db.select(db.conversations)..where((c) => c.kind.equals('group'))).get();
    for (final r in rows) {
      // ignore: avoid_print
      print('ROW ${r.id} room=${r.groupRoomId} title=${r.title} subtitle=${r.subtitle}');
    }
    // Con espejo: 'Conjunta' 2 miembros; sin espejo (nomirror): legacy 'comun' 2 miembros.
    if (rows.any((r) => r.groupRoomId == 'room-3')) {
      expect(rows.firstWhere((r) => r.groupRoomId == 'room-3').subtitle, '2 miembros · FakeA');
    } else {
      final comun = rows.where((r) => r.gatewayId == 'comun').toList();
      expect(comun, hasLength(1), reason: 'canal legacy: UNA fila comun');
      expect(comun.single.subtitle, '2 miembros · FakeA');
      expect(comun.single.title, 'default, default (B)');
    }
  });
}
