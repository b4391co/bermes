import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/herdr/herdr_client.dart';

void main() {
  test('nombre = terminal_title_stripped sin prefijo de decoración', () {
    HerdrAgent parse(String t) => HerdrAgent.fromJson({
      'agent': 'omp',
      'pane_id': 'w1:p1',
      'agent_status': 'idle',
      'terminal_title_stripped': t,
    });
    expect(
      parse('π > Fix Strat02 rounding and Strat01 calibration').name,
      'Fix Strat02 rounding and Strat01 calibration',
    );
    expect(
      parse('⠙ Fix bot gateway session and UI').name,
      'Fix bot gateway session and UI',
    );
    expect(parse('strat01-polymarket').name, 'strat01-polymarket');
    expect(
      parse('π > π > Anidado').name,
      'Anidado',
      reason: 'solo recorta el prefijo, no el cuerpo',
    );
    expect(parse('').name, 'omp @ w1:p1');
    expect(parse('π > ').name, 'omp @ w1:p1');
  });
}
