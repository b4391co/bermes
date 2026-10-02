import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_pocket/clients/hermes/bot_meta.dart';

/// El avatar del bot tiene DOS canales en el gateway real: la sección
/// `ui_meta['hermes-bots']` (shape/color/icon, fusionada por clave en el
/// servidor) y el almacén de assets (`profiles.set_asset`, la imagen).
/// Estos tests fijan lo que Pocket ENVÍA por cada uno: es la parte que puede
/// romper el filing de Hermes Desktop si se manda mal.
void main() {
  group('BotRosterMeta.toUiMetaSection', () {
    test('conserva las claves que Pocket no modela (pinned, sectionId, …)', () {
      final meta = BotRosterMeta.fromProfile({
        'ui_meta': {
          'hermes-bots': {
            'pinned': true,
            'sectionId': 'sec-7',
            'sectionName': 'Faena',
            'screenAutoOpen': true,
            'created': 1700000000000,
            'title': 'Viejo',
            'avatar': {'shape': 'circle', 'color': '#1a7f5a'},
          },
        },
      });
      expect(meta, isNotNull);
      final out = meta!.toUiMetaSection();
      expect(out['pinned'], true);
      expect(out['sectionId'], 'sec-7');
      expect(out['sectionName'], 'Faena');
      expect(out['screenAutoOpen'], true);
      expect(out['created'], 1700000000000);
    });

    test('los campos editados mandan sobre el raw', () {
      final meta = BotRosterMeta(
        title: 'Compi',
        description: 'new',
        avatar: const BotAvatarMeta(shape: 'square', color: '#c94f7c'),
        groups: const ['Equipo'],
        raw: const {'title': 'Viejo', 'description': 'old', 'pinned': false},
      ).toUiMetaSection();
      expect(meta['title'], 'Compi');
      expect(meta['description'], 'new');
      expect(meta['avatar'], {'shape': 'square', 'color': '#c94f7c'});
      expect(meta['groups'], ['Equipo']);
      expect(meta['pinned'], false, reason: 'no se pierde el filing ajeno');
    });

    test('expulsa la proyección legacy `group` (la regenera Desktop)', () {
      final out = BotRosterMeta(
        title: 'x',
        raw: const {'group': 'Equipo'},
      ).toUiMetaSection();
      expect(out.containsKey('group'), false);
    });

    test('title vacío elimina la clave en vez de escribir ""', () {
      final out = BotRosterMeta(
        title: '',
        raw: const {'title': 'Viejo'},
      ).toUiMetaSection();
      expect(out.containsKey('title'), false);
    });
  });

  group('BotRosterMeta.imageDataUrl (avatar del almacén de assets)', () {
    test('con imagen: se proyecta en avatar.image_url para no romper la '
        'referencia que leen otros clientes', () {
      const url = 'data:image/png;base64,AAAA';
      final base = BotRosterMeta(
        title: 'Compi',
        avatar: const BotAvatarMeta(shape: 'circle', color: '#1a7f5a'),
        raw: const {'title': 'Compi'},
      );
      final out = base.withImage(url).toUiMetaSection();
      final avatar = out['avatar'] as Map;
      expect(avatar['image_url'], url);
      expect(avatar['shape'], 'circle', reason: 'el resto del meta intacto');
    });

    test('sin imagen: no inventa la clave image_url', () {
      final out = BotRosterMeta(
        title: 'Compi',
        avatar: const BotAvatarMeta(shape: 'circle'),
        raw: const {},
      ).toUiMetaSection();
      expect((out['avatar'] as Map).containsKey('image_url'), false);
    });

    test('withImage conserva groups/raw/hidden', () {
      final base = BotRosterMeta(
        hidden: true,
        groups: const ['Equipo'],
        raw: const {'sectionId': 'sec-1'},
      );
      final out = base.withImage('data:image/png;base64,BB').toUiMetaSection();
      expect(out['hidden'], true);
      expect(out['groups'], ['Equipo']);
      expect(out['sectionId'], 'sec-1');
    });
  });

  group('BotAvatarMeta', () {
    test(
      'icon y color viajan; nulls se expulsan (el gateway fusiona por clave)',
      () {
        const meta = BotAvatarMeta(shape: 'rounded', icon: 'bolt');
        expect(meta.toJson(), {'shape': 'rounded', 'icon': 'bolt'});
      },
    );

    test('fromJson ignora cadenas vacías (gateways reales las escriben)', () {
      final m = BotAvatarMeta.fromJson({'shape': '', 'icon': 'code'});
      expect(m?.shape, isNull);
      expect(m?.icon, 'code');
    });

    test('meta totalmente vacío → null (no se escribe avatar:{})', () {
      expect(BotAvatarMeta.fromJson({'shape': '', 'color': ''}), isNull);
    });
  });
}
