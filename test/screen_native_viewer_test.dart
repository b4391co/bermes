import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/features/screen/screen_view.dart';

void main() {
  test('URL del WS: sin credenciales, ticket codificado, query única', () {
    final url = buildDisplayWsUrl(
      'http://10.20.20.67:9119',
      '/api/display/ws',
      'a/b+c=d',
    );
    expect(url, 'ws://10.20.20.67:9119/api/display/ws?display_ticket=a%2Fb%2Bc%3Dd');
    // El visor NATIVO (0.1.61) NO usa esta URL con ticket: HermesRfbClient lo
    // añade al conectar. La firma queda para el futuro pane de Windows y
    // porque la prueba de codificación sigue siendo válida.
  });

  test('https → wss', () {
    expect(
      buildDisplayWsUrl('https://gw.example', '/api/display/ws', 't')
          .startsWith('wss://gw.example/api/display/ws?display_ticket=t'),
      isTrue,
    );
  });
}
