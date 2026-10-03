// Regresión del bug 0.1.24: el editor de icono se cerraba "como guardado"
// cuando `configureBot` devolvía false (conflicto CAS / gateway antiguo),
// porque `imageOk` arrancaba en `true` y el gate era `ok || imageOk`.
// El gate real vive en _save(); este test fija la tabla de decisión tri-state
// exacta que ahora implementa (misma fórmula, sin widget/gateway).
import 'package:flutter_test/flutter_test.dart';

/// Espejo EXACTO del gate de `_save()` (bot_editor_sheet.dart): guardado y
/// ramas de aviso. Cualquier cambio en el sheet DEBE reflejarse aquí.
/// Regresión doble: (0.1.24) `imageOk` arrancaba true → CAS rechazado se
/// cantaba como guardado; (0.1.26) el pop exigía `imageOk` SIEMPRE, y como
/// sólo se evalúa tocando la imagen, un guardado meta-only ok nunca cerraba
/// el sheet y mostraba el aviso de fallo.
({bool pop, String notice}) saveOutcome({
  required bool ok,
  required bool imageOk,
  required bool touched,
  required bool saved,
}) {
  if (saved && ok && (touched ? imageOk : true)) return (pop: true, notice: '');
  if (saved && touched && !imageOk && ok) {
    return (pop: false, notice: 'icono-salvado-imagen-no');
  }
  if (saved && touched && !ok && imageOk) {
    return (pop: false, notice: 'imagen-salvada-meta-no');
  }
  return (pop: false, notice: saved ? 'parcial' : 'fallo');
}

void main() {
  group('gate de guardado del editor de ficha', () {
    test('edición sólo de icono con configure rechazado NO es guardado', () {
      final r = saveOutcome(
        ok: false, imageOk: false, touched: false, saved: false,
      );
      expect(r.pop, isFalse);
      expect(r.notice, 'fallo');
    });

    test('edición sólo de icono con configure ok → cierra limpio (bug 0.1.26)',
        () {
      final r = saveOutcome(
        ok: true, imageOk: false, touched: false, saved: true,
      );
      expect(r.pop, isTrue, reason: 'meta-only ok debe cerrar el sheet');
      expect(r.notice, isEmpty);
    });

    test('imagen aplicada con meta rechazada: guardado parcial con aviso', () {
      final r = saveOutcome(
        ok: false, imageOk: true, touched: true, saved: true,
      );
      expect(r.pop, isFalse);
      expect(r.notice, 'imagen-salvada-meta-no');
    });

    test('meta aplicada con imagen rechazada: guardado parcial con aviso', () {
      final r = saveOutcome(
        ok: true, imageOk: false, touched: true, saved: true,
      );
      expect(r.pop, isFalse);
      expect(r.notice, 'icono-salvado-imagen-no');
    });

    test('ambos canales ok con imagen → cierra limpio', () {
      final r = saveOutcome(
        ok: true, imageOk: true, touched: true, saved: true,
      );
      expect(r.pop, isTrue);
      expect(r.notice, isEmpty);
    });

    test('ambos canales fallidos → fallo', () {
      final r = saveOutcome(
        ok: false, imageOk: false, touched: true, saved: false,
      );
      expect(r.pop, isFalse);
      expect(r.notice, 'fallo');
    });
  });
}
