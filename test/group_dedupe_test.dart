import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/features/conversations/group_create.dart';
import 'package:hermes_pocket/data/database/app_database.dart'
    show Conversation;

void main() {
  Conversation conv(String id, String connId, String gatewayId) => Conversation(
    id: id,
    connectionId: connId,
    kind: 'bot',
    gatewayId: gatewayId,
    title: gatewayId,
    isGroup: false,
    unreadCount: 0,
    pinned: false,
    pinnedGateway: false,
    sortOrder: 0,
    groupSyncRevision: 0,
    groupHosted: false,
  );

  test('mismo perfil en dos gateways: una sola entrada (primer gateway)', () {
    final raw = [
      GroupCandidate(
        conv: conv('c1/bot/default', 'c1', 'default'),
        connectionId: 'c1',
        connectionLabel: 'Casa',
        installId: 'inst-1',
      ),
      GroupCandidate(
        conv: conv('c2/bot/default', 'c2', 'default'),
        connectionId: 'c2',
        connectionLabel: 'TokenGW',
        installId: 'inst-2',
      ),
      GroupCandidate(
        conv: conv('c2/bot/researcher', 'c2', 'researcher'),
        connectionId: 'c2',
        connectionLabel: 'TokenGW',
        installId: 'inst-2',
      ),
    ];
    final out = dedupeCandidates(raw, ['c1', 'c2']);
    // default duplicado entre gateways → una sola entrada; researcher queda.
    expect(out.length, 2);
    expect(out.first.connectionId, 'c1'); // gana el primero en el orden
    expect(out.map((c) => c.conv.gatewayId), ['default', 'researcher']);
  });

  test('bots distintos en cada gateway: todos entran', () {
    final raw = [
      GroupCandidate(
        conv: conv('c1/bot/compi', 'c1', 'compi'),
        connectionId: 'c1',
        connectionLabel: 'Casa',
        installId: 'inst-1',
      ),
      GroupCandidate(
        conv: conv('c2/bot/assistant', 'c2', 'assistant'),
        connectionId: 'c2',
        connectionLabel: 'TokenGW',
        installId: 'inst-2',
      ),
    ];
    final out = dedupeCandidates(raw, ['c1', 'c2']);
    expect(out.length, 2);
  });
}
