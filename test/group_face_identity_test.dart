import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_pocket/design/group_avatar.dart';

/// Regresión 0.1.49 (queja del usuario: «sigue sin relacionar bien a los
/// bots dentro de los grupos»): los miembros del grupo que crea Pocket se
/// guardan SIN `handle` y los homónimos entre gateways llevan el MISMO
/// `name` de perfil. Con un índice de caras keyed sólo por perfil, la cara
/// del segundo miembro devolvía la del primero. La resolución tiene que
/// distinguir por CONEXIÓN (installId → connId), no por nombre.
void main() {
  GroupFace face(String label) => GroupFace(
    seed: label,
    label: label,
    imageUrl: null,
    avatarMetaJson: null,
  );

  // Índice como lo construye GroupFaceIndex.of: clave `$connId/bot/$perfil`.
  final faces = {
    'conn-a/bot/default': face('Default Casa'),
    'conn-b/bot/default': face('Default Token'),
  };
  final connByInstall = {'inst-a': 'conn-a', 'inst-b': 'conn-b'};

  test('dos miembros con el mismo perfil: cada cara por su conexión', () {
    final mCasa = GroupMember(
      name: 'default',
      installId: 'inst-a',
      connectionId: 'inst-a',
    );
    final mToken = GroupMember(
      name: 'default',
      installId: 'inst-b',
      connectionId: 'inst-b',
    );
    final a = GroupAvatarStack.faceFor(mCasa, faces, connByInstall);
    final b = GroupAvatarStack.faceFor(mToken, faces, connByInstall);
    expect(a?.label, 'Default Casa');
    expect(b?.label, 'Default Token', reason: 'no debe heredar la cara de Casa');
  });

  test('handle del espejo de Desktop (default-claudio) enlaza por conexión',
      () {
    final m = GroupMember(
      name: 'default',
      handle: 'default-claudio',
      connectionId: 'inst-b',
    );
    final f = GroupAvatarStack.faceFor(m, faces, connByInstall);
    expect(f?.label, 'Default Token');
  });

  test('sin conexión y con homónimos: NO se inventa una cara', () {
    final m = GroupMember(name: 'default');
    final f = GroupAvatarStack.faceFor(m, faces, connByInstall);
    expect(
      f,
      isNull,
      reason: 'dos bots "default": repartir el primero sería adivinar',
    );
  });
}
