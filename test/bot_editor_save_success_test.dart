// Regresión del bug 0.1.24: el editor de icono se cerraba "como guardado"
// cuando `configureBot` devolvía false (conflicto CAS / gateway antiguo),
// porque `imageOk` arrancaba en `true` y el gate era `ok || imageOk`.
// El gate real vive en _save(); este test fija la tabla de decisión tri-state
// exacta que ahora implementa (misma fórmula, sin widget/gateway).
import 'package:flutter_test/flutter_test.dart';

/// Espejo del gate de `_save()` (bot_editor_sheet.dart). Cualquier cambio en
/// la fórmula del sheet DEBE reflejarse aquí.
bool savedGate({
  required bool ok,
  required bool imageOk,
  required bool touched,
}) => ok || (touched && imageOk);

String notice({
  required bool ok,
  required bool imageOk,
  required bool touched,
  required bool saved,
}) {
  if (saved && touched && !imageOk && ok) return 'icono-salvado-imagen-no';
  if (saved && touched && !ok && imageOk) return 'imagen-salvada-meta-no';
  if (saved) return 'exito';
  return 'fallo';
}

void main() {
  group('gate de guardado del editor de ficha', () {
    test('edición sólo de icono con configure rechazado NO es guardado', () {
      // El bug: antes caía en `ok || imageOk` con imageOk=true por defecto.
      expect(savedGate(ok: false, imageOk: false, touched: false), isFalse);
      expect(
        notice(ok: false, imageOk: false, touched: false, saved: false),
        'fallo',
      );
    });

    test('edición sólo de icono con configure ok → guardado limpio', () {
      expect(savedGate(ok: true, imageOk: false, touched: false), isTrue);
      expect(
        notice(ok: true, imageOk: false, touched: false, saved: true),
        'exito',
      );
    });

    test('imagen aplicada con meta rechazada: guardado parcial con aviso', () {
      expect(savedGate(ok: false, imageOk: true, touched: true), isTrue);
      expect(
        notice(ok: false, imageOk: true, touched: true, saved: true),
        'imagen-salvada-meta-no',
      );
    });

    test('meta aplicada con imagen rechazada: guardado parcial con aviso', () {
      expect(savedGate(ok: true, imageOk: false, touched: true), isTrue);
      expect(
        notice(ok: true, imageOk: false, touched: true, saved: true),
        'icono-salvado-imagen-no',
      );
    });

    test('ambos canales fallidos → fallo', () {
      expect(savedGate(ok: false, imageOk: false, touched: true), isFalse);
      expect(
        notice(ok: false, imageOk: false, touched: true, saved: false),
        'fallo',
      );
    });
  });
}
