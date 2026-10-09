import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/data/database/app_database.dart';
import 'package:hermes_pocket/design/group_avatar.dart';

void main() {
  test('miembros de Desktop sin perfil local resuelven por título', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // (la traducción installId→conn se pasa aparte; aquí se prueba la ruta
    // `title:` del índice)
    final bot = ConversationsCompanion.insert(
      id: 'c1/bot/default',
      connectionId: 'c1',
      kind: 'bot',
      gatewayId: 'default',
      title: 'Bernardino',
      avatarSeed: const Value('c1/default'),
    );
    db.into(db.conversations).insert(bot);
    // index no necesita DB: se construye desde el modelo de fila:
    final face = GroupFace.ofConversation(
      connectionId: 'c1',
      gatewayId: 'default',
      title: 'Bernardino',
    );
    final idx = {'c1/bot/default': face, 'title:Bernardino': face};
    // Miembro del espejo SOLO con display_name (Desktop):
    final m = GroupMember.fromJson({
      'display_name': 'Bernardino',
      'connectionId': 'desktop-uuid',
    });
    expect(
      GroupAvatarStack.faceFor(m, idx, const {}),
      isNotNull,
      reason: 'miembro proyectado sin perfil = iniciales (el bug del logo)',
    );
  });
}
