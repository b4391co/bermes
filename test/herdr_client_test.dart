import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/herdr/herdr_client.dart';

void main() {
  group('snapshot', () {
    test('envoltorio RPC result.snapshot.agents', () {
      const raw = '''{"id":1,"result":{"snapshot":{"agents":[
        {"name":"backend","agent_status":"working","pane_id":"w1:p2","workspace_id":"w1","title":"API"},
        {"name":"docs","agent_status":"idle"}
      ]}}}''';
      final agents = HerdrClient.parseSnapshot(raw);
      expect(agents, hasLength(2));
      expect(agents[0].name, 'backend');
      expect(agents[0].status, HerdrStatus.working);
      expect(agents[0].paneId, 'w1:p2');
      expect(agents[1].status, HerdrStatus.idle);
    });
    test('sin envoltorio: snapshot directo', () {
      const raw = '{"agents":[{"name":"omp","agent_status":"blocked"}]}';
      final agents = HerdrClient.parseSnapshot(raw);
      expect(agents.single.name, 'omp');
      expect(agents.single.status, HerdrStatus.blocked);
    });
    test('salida no-JSON → lista vacía (nunca lanza)', () {
      expect(HerdrClient.parseSnapshot('usage: herdr ...'), isEmpty);
    });
  });
}
