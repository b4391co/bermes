import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/clients/hermes/rfb_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FramebufferCanvas', () {
    test('rasterize produce ui.Image tras applyRaw', () async {
      final canvas = FramebufferCanvas();
      canvas.ensureSize(2, 2);
      // 2×2 BGRX: azul, verde, rojo, blanco.
      final pixels = Uint8List.fromList([
        255, 0, 0, 0, // B
        0, 255, 0, 0, // G
        0, 0, 255, 0, // R
        255, 255, 255, 0, // white
      ]);
      canvas.applyRaw(0, 0, 2, 2, pixels);
      expect(canvas.image, isNull, reason: 'sin rasterize aún');
      final img = await canvas.rasterize();
      expect(img, isNotNull);
      expect(img!.width, 2);
      expect(img.height, 2);
      expect(canvas.image, same(img));
      // Segundo rasterize sin dirty: misma imagen.
      final again = await canvas.rasterize();
      expect(again, same(img));
    });

    test('applyCopy mueve píxeles y marca dirty', () async {
      final canvas = FramebufferCanvas();
      canvas.ensureSize(4, 2);
      final blue = Uint8List.fromList([255, 0, 0, 0]);
      canvas.applyRaw(0, 0, 1, 1, blue);
      await canvas.rasterize();
      canvas.applyCopy(2, 0, 1, 1, 0, 0);
      final img = await canvas.rasterize();
      expect(img, isNotNull);
      expect(img!.width, 4);
    });
  });
}
