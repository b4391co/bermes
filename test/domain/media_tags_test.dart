import 'package:hermes_pocket/domain/message/media_tags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitAssistantMedia (puerto de parts.ts)', () {
    test('línea dedicada MEDIA: se elimina y produce adjunto', () {
      final r = splitAssistantMedia(
        'Aquí tienes la captura:\nMEDIA: /home/user/out/screenshot.png\n',
      );
      expect(r.text, 'Aquí tienes la captura:');
      expect(r.media, hasLength(1));
      expect(r.media.first.path, '/home/user/out/screenshot.png');
      expect(r.media.first.name, 'screenshot.png');
    });

    test('tag en prosa con ruta anclada y extensión conocida', () {
      final r = splitAssistantMedia('mira MEDIA:/tmp/informe.pdf ahora');
      expect(r.media.first.path, '/tmp/informe.pdf');
      expect(r.text, isNot(contains('MEDIA:')));
    });

    test('puntuación de frase NO entra en la ruta bare', () {
      final r = splitAssistantMedia('abierto MEDIA:/tmp/a.pdf.');
      expect(r.media.first.path, '/tmp/a.pdf');
    });

    test('ruta entrecomillada conserva puntuación interior', () {
      final r = splitAssistantMedia("MEDIA: '/tmp/stop!.md'");
      expect(r.media.first.path, '/tmp/stop!.md');
    });

    test('ruta con espacios (anchor + extensión conocida)', () {
      final r = splitAssistantMedia('MEDIA: /tmp/My Photo 2026.png');
      expect(r.media.first.path, '/tmp/My Photo 2026.png');
    });

    test('ruta Windows', () {
      final r = splitAssistantMedia(r'MEDIA: C:\Users\me\doc.pdf');
      expect(r.media.first.path, r'C:\Users\me\doc.pdf');
    });

    test('degenerate MEDIA:... es prosa, no adjunto (#84361)', () {
      final r = splitAssistantMedia('cosas MEDIA:... otras');
      expect(r.media, isEmpty);
      expect(r.text, contains('MEDIA:...'));
    });

    test('backticks y comillas dobles como escaparate', () {
      expect(splitAssistantMedia('MEDIA: `/tmp/x.png`').media.single.path,
          '/tmp/x.png');
      expect(splitAssistantMedia('MEDIA: "/tmp/x.png"').media.single.path,
          '/tmp/x.png');
    });

    test('multi-entrega en un turno', () {
      final r = splitAssistantMedia(
        'video listo\nMEDIA: /v/a.mp4\ny foto\nMEDIA: /v/b.png\n',
      );
      expect(r.media.map((m) => m.path), ['/v/a.mp4', '/v/b.png']);
      expect(r.text, 'video listo\ny foto');
    });

    test('texto sin tags: invariante', () {
      const t = 'Hola, ¿qué tal?';
      final r = splitAssistantMedia(t);
      expect(r.text, t);
      expect(r.media, isEmpty);
    });
  });

  group('mediaKindOf', () {
    test('clasifica por extensión', () {
      expect(mediaKindOf('/a/b.PNG'), 'image');
      expect(mediaKindOf('/a/b.mp4'), 'video');
      expect(mediaKindOf('/a/b.mp3'), 'audio');
      // PDF: visor propio integrado (flutter_pdfview); md/markdown siguen
      // como 'doc'. El kind decide la ruta de openBotMedia.
      expect(mediaKindOf('/a/b.pdf'), 'pdf');
      expect(mediaKindOf('/a/b.zip'), 'file');
    });
  });
}
