import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/logger.dart';

/// Cliente RFB (VNC) sobre WebSocket binario del Screen de Hermes.
///
/// Contrato verificado (commit 3be17b1d):
/// - display.observe {viewer_id} → {ticket, path:"/api/display/ws"} (ticket 30 s).
/// - WS binario en frames: el gateway spliced RFB crudo. NO es MJPEG.
/// - Desktop usa noVNC; este cliente implementa el subconjunto RFB necesario:
///   handshake 3.8, seguridad None, SetPixelFormat RGB32/BGRX client-side,
///   SetEncodings Raw + CopyRect, FramebufferUpdate incremental.
/// - Close codes: 4000 control-taken (vuelve a Watch), 4001 desktop gone,
///   4401 ticket, 4403 permiso.
class HermesRfbClient {
  final _log = Logger('Rfb');

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;

  int _width = 0;
  int _height = 0;
  String _name = '';
  final _pixelFormatSent = Completer<void>();
  bool _connected = false;

  final _frame = StreamController<RfbFrame>.broadcast();
  final _state = StreamController<RfbState>.broadcast();

  int get width => _width;
  int get height => _height;
  String get name => _name;
  bool get connected => _connected;

  Stream<RfbFrame> get frames => _frame.stream;
  Stream<RfbState> get states => _state.stream;

  /// Conectar con ticket de display.observe.
  Future<void> connect({
    required String wsUrl, // wss://host:9119/api/display/ws
    required String ticket,
  }) async {
    final uri = Uri.parse(
      '$wsUrl?display_ticket=${Uri.encodeQueryComponent(ticket)}',
    );
    _state.add(RfbState.connecting);
    final ws = WebSocketChannel.connect(uri);
    _ws = ws;

    await ws.ready.timeout(const Duration(seconds: 15));

    _sub = ws.stream.listen(
      _onData,
      onError: (Object e) {
        _log.warning('ws error: $e');
        _state.add(RfbState.error);
      },
      onDone: () {
        _connected = false;
        _state.add(RfbState.disconnected);
      },
    );

    // Enviar versión RFB 3.8 (12 bytes).
    _sendRaw(Uint8List.fromList(utf8.encode('RFB 003.008\n')));

    // Esperar número de security types y elegir None (1).
    // El handshake continúa en _onData según fase.
    _state.add(RfbState.handshaking);
  }

  // ── Fases del handshake ───────────────────────────────────────────────
  static const _phaseVersion = 0;
  static const _phaseSecurityTypes = 1;
  static const _phaseSecurityResult = 2;
  static const _phaseServerInit = 3;
  static const _phaseNormal = 4;

  int _phase = _phaseVersion;
  Uint8List _acc = Uint8List(0);

  void _onData(dynamic data) {
    if (data is! List<int>) return;
    final chunk = data is Uint8List ? data : Uint8List.fromList(data);
    _acc = Uint8List.fromList([..._acc, ...chunk]);
    _consume();
  }

  void _consume() {
    switch (_phase) {
      case _phaseVersion:
        if (_acc.length < 12) return;
        final version = utf8.decode(_acc.sublist(0, 12));
        _acc = _acc.sublist(12);
        _log.info('RFB server version: ${version.trim()}');
        _phase = _phaseSecurityTypes;
        _consume();
        break;

      case _phaseSecurityTypes:
        if (_acc.isEmpty) return;
        final nTypes = _acc[0];
        if (_acc.length < 1 + nTypes) return;
        final types = _acc.sublist(1, 1 + nTypes);
        _acc = _acc.sublist(1 + nTypes);
        // Elegir None (1) si está; si no, fallar (no implementar VNC Auth).
        if (!types.contains(1)) {
          _log.error('servidor no ofrece None security; tipos: $types');
          _state.add(RfbState.unsupported);
          disconnect();
          return;
        }
        _sendRaw(Uint8List.fromList([1]));
        _phase = _phaseSecurityResult;
        _consume();
        break;

      case _phaseSecurityResult:
        if (_acc.length < 4) return;
        final result = ByteData.view(
          _acc.buffer,
          _acc.offsetInBytes,
          4,
        ).getUint32(0);
        _acc = _acc.sublist(4);
        if (result != 0) {
          _log.error('security handshake falló: $result');
          _state.add(RfbState.unauthorized);
          disconnect();
          return;
        }
        // Cliente envía ClientInit(shared=1).
        _sendRaw(Uint8List.fromList([1]));
        _phase = _phaseServerInit;
        _consume();
        break;

      case _phaseServerInit:
        if (_acc.length < 24) return;
        final bd = ByteData.view(_acc.buffer, _acc.offsetInBytes, 24);
        _width = bd.getUint16(0);
        _height = bd.getUint16(2);
        // pixel format en offset 4..16; name length en 16.
        final nameLen = bd.getUint32(16);
        if (_acc.length < 24 + nameLen) return;
        _name = utf8.decode(_acc.sublist(24, 24 + nameLen));
        _acc = _acc.sublist(24 + nameLen);
        _log.info('RFB init: ${_width}x$_height "$_name"');
        _sendSetPixelFormat();
        _sendSetEncodings();
        _sendFramebufferRequest(incremental: false);
        _connected = true;
        _phase = _phaseNormal;
        _state.add(RfbState.ready);
        _consume();
        break;

      case _phaseNormal:
        _consumeRects();
        break;
    }
  }

  void _consumeRects() {
    // FramebufferUpdate: msg-type(1)=0 + padding(1) + numRects(2) + rects.
    while (_acc.length >= 4) {
      final msgType = _acc[0];
      if (msgType == 0) {
        final numRects = (_acc[2] << 8) | _acc[3];
        var offset = 4;
        final rects = <RfbRect>[];
        var ok = true;
        for (var i = 0; i < numRects; i++) {
          if (_acc.length < offset + 12) {
            ok = false;
            break;
          }
          final bd = ByteData.view(
            _acc.buffer,
            _acc.offsetInBytes + offset,
            12,
          );
          final x = bd.getUint16(0);
          final y = bd.getUint16(2);
          final w = bd.getUint16(4);
          final h = bd.getUint16(6);
          final encoding = bd.getInt32(8);
          offset += 12;

          if (encoding == -1) {
            // pseudo-encoding cursor: tamaño variable, se ignora (no dibujamos cursor).
            continue;
          }
          if (encoding == 0) {
            // Raw: w*h*4 bytes (BGRX 32bpp).
            final bytes = w * h * 4;
            if (_acc.length < offset + bytes) {
              ok = false;
              break;
            }
            rects.add(
              RfbRect.raw(
                x: x,
                y: y,
                w: w,
                h: h,
                pixels: _acc.sublist(offset, offset + bytes),
              ),
            );
            offset += bytes;
          } else if (encoding == 1) {
            // CopyRect: src-x(2) src-y(2).
            if (_acc.length < offset + 4) {
              ok = false;
              break;
            }
            final sxd = ByteData.view(
              _acc.buffer,
              _acc.offsetInBytes + offset,
              4,
            );
            rects.add(
              RfbRect.copy(
                x: x,
                y: y,
                w: w,
                h: h,
                srcX: sxd.getUint16(0),
                srcY: sxd.getUint16(2),
              ),
            );
            offset += 4;
          } else {
            // Encoding no soportado: no se puede saltar sin conocer tamaño → error.
            _log.error('encoding no soportado: $encoding');
            _state.add(RfbState.unsupported);
            disconnect();
            return;
          }
        }
        if (!ok) return; // esperar más datos
        _acc = _acc.sublist(offset);
        _frame.add(RfbFrame(rects: rects, width: _width, height: _height));
      } else if (msgType == 1) {
        // SetColourMapEntries — ignorar (true-color).
        if (_acc.length < 6) return;
        final n = (_acc[4] << 8) | _acc[5];
        final need = 6 + n * 6;
        if (_acc.length < need) return;
        _acc = _acc.sublist(need);
      } else if (msgType == 2) {
        // Bell — ignorar.
        _acc = _acc.sublist(1);
      } else if (msgType == 3) {
        // ServerCutText — ignorar por seguridad (no loggear contenido).
        if (_acc.length < 8) return;
        final len = _acc.sublist(4, 8);
        final n = ByteData.view(len.buffer).getUint32(0);
        final need = 8 + n;
        if (_acc.length < need) return;
        _acc = _acc.sublist(need);
      } else {
        _log.warning('mensaje RFB desconocido tipo $msgType');
        _acc = Uint8List(0);
        return;
      }
    }
  }

  void _sendSetPixelFormat() {
    // SetPixelFormat (msg 0): BGRX 32bpp little-endian client-side.
    final b = BytesBuilder();
    b.addByte(0);
    b.add(Uint8List(3)); // padding
    final bd = ByteData(16);
    bd.setUint8(0, 32); // bits per pixel
    bd.setUint8(1, 24); // depth
    bd.setUint8(2, 0); // big-endian flag
    bd.setUint8(3, 1); // true-color
    bd.setUint16(4, 255); // red max
    bd.setUint16(6, 255); // green max
    bd.setUint16(8, 255); // blue max
    bd.setUint8(10, 16); // red shift (BGRX layout)
    bd.setUint8(11, 8); // green shift
    bd.setUint8(12, 0); // blue shift
    b.add(bd.buffer.asUint8List());
    _sendRaw(b.toBytes());
    _pixelFormatSent.complete();
  }

  void _sendSetEncodings() {
    final b = BytesBuilder();
    b.addByte(2);
    b.addByte(0); // padding
    final bd = ByteData(2);
    bd.setUint16(0, 2); // Raw + CopyRect
    b.add(bd.buffer.asUint8List());
    final e1 = ByteData(4)..setInt32(0, 0); // Raw
    final e2 = ByteData(4)..setInt32(0, 1); // CopyRect
    b.add(e1.buffer.asUint8List());
    b.add(e2.buffer.asUint8List());
    _sendRaw(b.toBytes());
  }

  void requestRefresh() => _sendFramebufferRequest(incremental: false);

  void _sendFramebufferRequest({required bool incremental}) {
    final b = BytesBuilder();
    b.addByte(3);
    b.addByte(incremental ? 1 : 0);
    final bd = ByteData(8);
    bd.setUint16(0, 0);
    bd.setUint16(2, 0);
    bd.setUint16(4, _width);
    bd.setUint16(6, _height);
    b.add(bd.buffer.asUint8List());
    _sendRaw(b.toBytes());
  }

  // ── Input (gateado por el lease en el servidor) ──────────────────────

  /// KeyEvent (msg 4). down=true para pulsar.
  void sendKey(int keysym, {required bool down}) {
    final b = BytesBuilder();
    b.addByte(4);
    b.addByte(down ? 1 : 0);
    b.add(Uint8List(2));
    final bd = ByteData(4)..setUint32(0, keysym);
    b.add(bd.buffer.asUint8List());
    _sendRaw(b.toBytes());
  }

  /// PointerEvent (msg 5). x,y en coords del framebuffer; buttonMask bits:
  /// 1=left 2=middle 4=right 8=scroll-up 16=scroll-down.
  void sendPointer(int x, int y, {int buttonMask = 0}) {
    final b = BytesBuilder();
    b.addByte(5);
    b.addByte(buttonMask);
    final bd = ByteData(4);
    bd.setUint16(0, min(x, _width - 1));
    bd.setUint16(2, min(y, _height - 1));
    b.add(bd.buffer.asUint8List());
    _sendRaw(b.toBytes());
  }

  /// ClientCutText (msg 6) — portapapeles hacia el host (respetando lease).
  void sendCutText(String text) {
    final b = BytesBuilder();
    b.addByte(6);
    b.add(Uint8List(3));
    final bytes = utf8.encode(text);
    final bd = ByteData(4)..setUint32(0, bytes.length);
    b.add(bd.buffer.asUint8List());
    b.add(bytes);
    _sendRaw(b.toBytes());
  }

  void _sendRaw(Uint8List bytes) {
    try {
      _ws?.sink.add(bytes);
    } catch (e) {
      _log.warning('send failed: $e');
    }
  }

  Future<void> disconnect() async {
    _connected = false;
    await _sub?.cancel();
    await _ws?.sink.close();
    _ws = null;
    _state.add(RfbState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _frame.close();
    await _state.close();
  }
}

/// Rectángulo de actualización.
class RfbRect {
  final int x, y, w, h;
  final int? encoding; // 0 raw, 1 copyRect
  final Uint8List? pixels; // BGRX si raw
  final int? srcX, srcY; // si copyRect

  const RfbRect.raw({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.pixels,
  }) : encoding = 0,
       srcX = null,
       srcY = null;

  const RfbRect.copy({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.srcX,
    required this.srcY,
  }) : encoding = 1,
       pixels = null;
}

class RfbFrame {
  final List<RfbRect> rects;
  final int width;
  final int height;

  const RfbFrame({
    required this.rects,
    required this.width,
    required this.height,
  });
}

enum RfbState {
  connecting,
  handshaking,
  ready,
  disconnected,
  unauthorized,
  unsupported,
  error,
}

/// Búfer de framebuffer compartido: mantiene un ui.Image actualizado
/// incrementalmente aplicando rects.
class FramebufferCanvas {
  int width = 0;
  int height = 0;
  Uint8List _pixelsBgra = Uint8List(0);
  bool _dirty = true;
  ui.Image? _image;

  ui.Image? get image => _image;

  void ensureSize(int w, int h) {
    if (w == width && h == height) return;
    width = w;
    height = h;
    _pixelsBgra = Uint8List(w * h * 4);
    _dirty = true;
  }

  /// Aplica un rect raw BGRX al buffer BGRA.
  void applyRaw(int x, int y, int w, int h, Uint8List bgrx) {
    if (x + w > width || y + h > height) return;
    var src = 0;
    for (var row = 0; row < h; row++) {
      final dstStart = ((y + row) * width + x) * 4;
      for (var col = 0; col < w; col++) {
        // BGRX → BGRA (alpha = 255)
        final d = dstStart + col * 4;
        _pixelsBgra[d] = bgrx[src]; // B
        _pixelsBgra[d + 1] = bgrx[src + 1]; // G
        _pixelsBgra[d + 2] = bgrx[src + 2]; // R
        _pixelsBgra[d + 3] = 255; // A
        src += 4;
      }
    }
    _dirty = true;
  }

  void applyCopy(int x, int y, int w, int h, int srcX, int srcY) {
    for (var row = 0; row < h; row++) {
      final srcRow = ((srcY + row) * width + srcX) * 4;
      final dstRow = ((y + row) * width + x) * 4;
      if (srcRow + w * 4 <= _pixelsBgra.length &&
          dstRow + w * 4 <= _pixelsBgra.length) {
        _pixelsBgra.setRange(dstRow, dstRow + w * 4, _pixelsBgra, srcRow);
      }
    }
    _dirty = true;
  }

  /// Rasteriza el framebuffer a ui.Image si hay cambios.
  Future<ui.Image?> rasterize() async {
    if (!_dirty || width == 0 || height == 0) return _image;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _pixelsBgra,
      width,
      height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    final img = await completer.future;
    _image?.dispose();
    _image = img;
    _dirty = false;
    return img;
  }
}
