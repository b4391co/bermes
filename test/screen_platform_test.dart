import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_pocket/features/screen/screen_view.dart';

/// La URL del WS de pantalla es la superficie donde más fácil se cuela un bug
/// silencioso (scheme mal sustituido, ticket sin escapar → 4401). Contrato
/// real: web_routers/display.py — ticket en QUERY, ws(s) sobre la base HTTP.
void main() {
  test('http -> ws conservando host, puerto y prefijo de ruta', () {
    expect(
      buildDisplayWsUrl('http://10.0.2.2:9120', '/api/display/ws', 'abc123'),
      'ws://10.0.2.2:9120/api/display/ws?display_ticket=abc123',
    );
    expect(
      buildDisplayWsUrl('https://gw.example/hermes', '/api/display/ws', 'abc123'),
      'wss://gw.example/hermes/api/display/ws?display_ticket=abc123',
    );
  });

  test('el ticket se escapa en la query (single-use 30 s: no debe corromperse)', () {
    expect(
      buildDisplayWsUrl('http://h:1', '/api/display/ws', 'a/b+c=d'),
      'ws://h:1/api/display/ws?display_ticket=a%2Fb%2Bc%3Dd',
    );
  });
}
