import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/herdr/herdr_client.dart';

// Muestra REAL de `herdr api snapshot` (herdr 0.9.1, host del usuario):
// sin 'name' ni 'title'; identidad por pane_id y etiqueta legible en
// terminal_title_stripped.
const _realSample = "{\"id\": \"cli:api:snapshot\", \"result\": {\"snapshot\": {\"agents\": [{\"agent\": \"omp\", \"agent_session\": {\"agent\": \"omp\", \"kind\": \"path\", \"source\": \"herdr:omp\", \"value\": \"/root/.omp/agent/sessions/-agents-memecoin/2026-09-23T16-54-15-046Z_01a0cf30-7706-77d7-8204-62f9f78b4421.jsonl\"}, \"agent_status\": \"idle\", \"cwd\": \"/root\", \"focused\": false, \"foreground_cwd\": \"/root/agents/memecoin\", \"pane_id\": \"w6:pH\", \"revision\": 1, \"screen_detection_skipped\": true, \"state_change_seq\": 5, \"tab_id\": \"w6:tG\", \"terminal_id\": \"term_65c871367d1841\", \"terminal_title\": \"\\u03c0 > Fix Strat02 rounding and Strat01 calibration\", \"terminal_title_stripped\": \"\\u03c0 > Fix Strat02 rounding and Strat01 calibration\", \"workspace_id\": \"w6\"}, {\"agent\": \"omp\", \"agent_session\": {\"agent\": \"omp\", \"kind\": \"path\", \"source\": \"herdr:omp\", \"value\": \"/root/.omp/agent/sessions/-trading-strategies-strat01-polymarket/2026-09-23T18-00-04-936Z_01a0cf6c-bc47-73b0-b45a-88b2c9b68fe7.jsonl\"}, \"agent_status\": \"idle\", \"cwd\": \"/root/trading/strategies/strat01-polymarket\", \"focused\": false, \"foreground_cwd\": \"/root/trading/strategies/strat01-polymarket\", \"interactive_ready\": true, \"name\": \"strat01-polymarket\", \"pane_id\": \"w6:pK\", \"revision\": 1, \"screen_detection_skipped\": true, \"state_change_seq\": 6, \"tab_id\": \"w6:tJ\", \"terminal_id\": \"term_65c871367d1db2\", \"terminal_title\": \"\\u03c0 > Why no trades executed\", \"terminal_title_stripped\": \"\\u03c0 > Why no trades executed\", \"workspace_id\": \"w6\"}]}}}";

void main() {
  test('snapshot real v0.9.1: title legible + pane_id + estado', () {
    final agents = HerdrClient.parseSnapshot(_realSample);
    expect(agents.length, 2);
    for (final a in agents) {
      expect(a.paneId, isNotNull);
      expect(a.name, isNotEmpty);
    }
    expect(agents.map((a) => a.title), everyElement('omp'));
  });
}
