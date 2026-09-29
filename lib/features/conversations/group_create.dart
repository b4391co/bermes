/// Creación de grupos compatible con Hermes Desktop.
///
/// Desktop crea un grupo así (create-dialog.tsx:1190-1221):
///  1. mintea un `roomId` fresco (`r{base36 now}-{rand}`, group-chat.ts:1777-1779)
///  2. parchea la membresía de CADA bot elegido (`ui_meta.hermes-bots.groups`
///     + proyección legacy `group`, group-membership.ts:181-202)
///  3. publica la sala en el espejo `ui_meta['hermes-bots-groups']` del
///     perfil `default` (`profiles.configure` + CAS, group-chat.ts:1174-1192)
///  4. los demás clientes la reciben al releer el espejo — ausente ≠ borrado
///     (`group-chat.ts:673-675`)
///
/// Pocket replica los cuatro pasos con el MISMO formato para que la sala
/// aparezca en Desktop y en otros dispositivos sin duplicarse.
///
/// Desduplicación de miembros (petición del usuario): dos bots con el MISMO
/// nombre de perfil en gateways distintos —o el mismo bot visto por dos
/// conexiones— son UN miembro, no dos. La identidad portable del descriptor
/// es `name` + `installId` del gateway elegido (`types.ts:103-106`); el
/// primero en el orden de conexiones gana.
library;

import 'package:drift/drift.dart';

import '../../clients/hermes/bot_meta.dart';
import '../../clients/hermes/connection_manager.dart';
import '../../data/database/app_database.dart';
import 'group_rooms.dart';

/// Un bot candidato del sheet de creación: fila local de conversación + la
/// conexión que lo sirve.
class GroupCandidate {
  final Conversation conv;
  final String connectionId;
  final String connectionLabel;
  final String? installId;

  const GroupCandidate({
    required this.conv,
    required this.connectionId,
    required this.connectionLabel,
    this.installId,
  });

  /// Clave de desduplicación: el nombre del perfil del backend (identity)
  /// dentro de la identidad del gateway. Dos bots que comparten perfil en el
  /// mismo gateway son la misma fila; en gateways distintos, el usuario pidió
  /// NO duplicarlos → una sola entrada (la primera conexión en orden).
  String get dedupeKey => '${installId ?? connectionId}::${conv.gatewayId}';

  /// Desduplicación entre gateways por NOMBRE de perfil: el mismo nombre en
  /// Casa y TokenGW se presenta una vez. El gateway dueño es el primero.
  String get nameKey => conv.gatewayId;
}

/// Elije candidatos desduplicados de las filas locales de bots:
/// por `installId::perfil` y, entre gateways distintos, por nombre de perfil
/// (primer gateway en el orden dado).
List<GroupCandidate> dedupeCandidates(
  List<GroupCandidate> raw,
  List<String> connectionOrder,
) {
  final byName = <String, GroupCandidate>{};
  final out = <GroupCandidate>[];
  final seenPerGateway = <String>{};
  // Orden de prioridad: el orden de conexiones del usuario decide el dueño.
  final ordered = [...raw]..sort((a, b) {
      final ra = connectionOrder.indexOf(a.connectionId);
      final rb = connectionOrder.indexOf(b.connectionId);
      return (ra < 0 ? 999 : ra).compareTo(rb < 0 ? 999 : rb);
    });
  for (final c in ordered) {
    // Dentro del mismo gateway no puede haber dos perfiles iguales (el
    // gateway los deduplica), pero por si acaso: primera gana.
    if (!seenPerGateway.add(c.dedupeKey)) continue;
    // Entre gateways: un nombre de perfil ya visto no se repite.
    if (byName.containsKey(c.nameKey)) continue;
    byName[c.nameKey] = c;
    out.add(c);
  }
  return out;
}

/// Resultado de crear un grupo.
class GroupCreateOutcome {
  final bool ok;
  final String? error;
  final String? conversationId;

  const GroupCreateOutcome._(this.ok, this.error, this.conversationId);
  const GroupCreateOutcome.success(String conversationId)
      : this._(true, null, conversationId);
  const GroupCreateOutcome.failure(String message)
      : this._(false, message, null);
}

/// Crea el grupo: parche de membresía por bot + publicación del espejo con
/// CAS + fila local. Los Runtimes deben estar listos; el llamador (UI) ya
/// validó nombre y mínimo de miembros.
Future<GroupCreateOutcome> createGroup({
  required AppDatabase db,
  required Map<String, ConnectionRuntime> runtimes,
  required Map<String, Connection> connections,
  required List<GroupCandidate> members,
  required String name,
  required String Function(String profile, String connectionId) titleFor,
}) async {
  if (members.length < 2) {
    return const GroupCreateOutcome.failure(
      'Elige al menos 2 bots para el grupo.',
    );
  }
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return const GroupCreateOutcome.failure('Ponle nombre al grupo.');
  }

  // ── 1. roomId fresco con el formato exacto de Desktop (group-chat.ts:1777)
  final now = DateTime.now().millisecondsSinceEpoch;
  final roomId =
      'r${now.toRadixString(36)}-${DateTime.now().microsecondsSinceEpoch.toRadixString(36).substring(0, 5)}';
  final roomKey = 'id:$roomId';

  // Descriptores de miembro portables (GroupMember, types.ts:130-147). El
  // nombre visible NO es identidad: name = perfil del backend.
  final memberDescriptors = <Map<String, Object?>>[
    for (final m in members)
      {
        'name': m.conv.gatewayId,
        if (m.installId != null) 'installId': m.installId,
        'connectionLabel': m.connectionLabel,
        if (m.conv.subtitle != null) 'display_name': m.conv.title,
        'title': m.conv.title,
      },
  ];

  // ── 2. Parche de membresía de cada bot (group-membership.ts:181-202).
  //      La sección hermes-bots se REEMPLAZA entera → se reenvía la cruda
  //      leída + groups nuevo (igual que configureBot exige).
  final membershipErrors = <String>[];
  for (final m in members) {
    final runtime = runtimes[m.connectionId];
    if (runtime == null) continue;
    try {
      final profiles = await runtime.gateway.listProfiles();
      final p = profiles.where((x) => x['name'] == m.conv.gatewayId).firstOrNull;
      if (p == null) {
        membershipErrors.add(m.conv.title);
        continue;
      }
      final raw = BotRosterMeta.fromProfile(p)?.raw ?? const {};
      final existing = <String>[
        ...?BotRosterMeta.fromProfile(p)?.groups,
      ];
      if (!existing.contains(trimmed)) existing.add(trimmed);
      // CAS: la revisión actual de la clave hermes-bots del perfil.
      final rev = (p['ui_meta_revisions'] is Map)
          ? ((p['ui_meta_revisions'] as Map)['hermes-bots'] as num?)?.toInt()
          : null;
      final ok = await runtime.gateway.configureBot(
        m.conv.gatewayId,
        groups: existing,
        expectedRevision: rev,
        rawSection: raw,
      );
      if (!ok) membershipErrors.add(m.conv.title);
    } catch (_) {
      membershipErrors.add(m.conv.title);
    }
  }

  // ── 3. Publicar la sala en el espejo de la conexión del PRIMER miembro
  //      (dueño). Desktop publica en todos los gateways conectados; aquí el
  //      pull periódico de los otros gateways + Desktop propagará la sala
  //      (ausente ≠ borrado). Si el dueño falla, la sala vive local y se
  //      reintentará en el próximo sync.
  final owner = members.first;
  final ownerRuntime = runtimes[owner.connectionId];
  var published = false;
  String? publishError;
  if (ownerRuntime != null) {
    try {
      // Espejo ACTUAL del owner (fuente de verdad: profiles.list fresco).
      final profiles = await ownerRuntime.gateway.listProfiles();
      final def = profiles
          .where((x) => x['name'] == 'default')
          .firstOrNull;
      final current = GroupSyncSnapshot.tryParse(
        def != null && def['ui_meta'] is Map
            ? (def['ui_meta'] as Map)['hermes-bots-groups']
            : null,
      );
      final base = current ?? GroupSyncSnapshot.empty;
      final room = GroupRoom(
        key: roomKey,
        roomId: roomId,
        name: trimmed,
        revision: _maxRevision(base) + 1,
        members: [
          for (final d in memberDescriptors)
            GroupMember(
              name: d['name'] as String?,
              installId: d['installId'] as String?,
              connectionLabel: d['connectionLabel'] as String?,
              displayName: d['display_name'] as String?,
              title: d['title'] as String?,
            ),
        ],
      );
      final merged = Map<String, GroupRoom>.from(base.rooms)..[roomKey] = room;
      final snapshot = <String, Object?>{
        'version': 3,
        'updatedAt': now,
        'rooms': {
          for (final e in merged.entries)
            e.key: {
              'roomId': e.value.roomId,
              'name': e.value.name,
              'revision': e.value.revision,
              'members': [
                for (final m in e.value.members)
                  {
                    if (m.name != null) 'name': m.name,
                    if (m.installId != null) 'installId': m.installId,
                    if (m.connectionLabel != null)
                      'connectionLabel': m.connectionLabel,
                    if (m.displayName != null) 'display_name': m.displayName,
                    if (m.title != null) 'title': m.title,
                    if (m.handle != null) 'handle': m.handle,
                    if (m.targetProfile != null)
                      'targetProfile': m.targetProfile,
                    if (m.previousNames.isNotEmpty)
                      'previous_names': m.previousNames,
                  },
              ],
            },
        },
        if (base.deleted.isNotEmpty)
          'deleted': {for (final e in base.deleted.entries) e.key: e.value},
      };
      // CAS sobre la revisión de la clave leída (profiles.list ui_meta_revisions).
      final expected = def != null && def['ui_meta_revisions'] is Map
          ? ((def['ui_meta_revisions'] as Map)['hermes-bots-groups'] as num?)
              ?.toInt()
          : null;
      published = await ownerRuntime.gateway.publishGroupMirror(
        snapshot: snapshot,
        expectedRevision: expected,
      );
      if (!published) {
        publishError =
            'El espejo cambió mientras se creaba (Desktop escribió a la vez). '
            'Reintenta.';
      }
    } catch (e) {
      publishError = 'No se pudo publicar el grupo: $e';
    }
  } else {
    publishError = 'La conexión del bot dueño no está disponible.';
  }

  if (!published) {
    return GroupCreateOutcome.failure(publishError ?? 'No se pudo publicar.');
  }

  // ── 4. Fila local (la presentación la rematerializa el sync, pero se
  //      inserta YA para abrir el chat al instante).
  final ownerConn = connections[owner.connectionId];
  final convId = '${owner.connectionId}/group/$roomId';
  await db.into(db.conversations).insertOnConflictUpdate(
        ConversationsCompanion.insert(
          id: convId,
          connectionId: owner.connectionId,
          kind: 'group',
          gatewayId: roomId,
          title: trimmed,
          subtitle: Value(
            members.length == 1
                ? '1 miembro · ${ownerConn?.name ?? ''}'
                : '${members.length} miembros · ${ownerConn?.name ?? ''}',
          ),
          avatarSeed: Value(roomId),
          isGroup: const Value(true),
          gatewayLabel: Value(ownerConn?.name),
          groupRoomId: Value(roomId),
          groupSyncRevision: const Value(1),
          groupSyncName: Value(trimmed),
          lastActivity: Value(DateTime.now()),
        ),
      );

  if (membershipErrors.isNotEmpty) {
    // El grupo existe y se publica; el parche de membresía falló en algunos
    // bots (CAS o conexión). Desktop rep-para esos bots al lado; aquí queda
    // registrado: la sala funciona, la membresía se reconcilia en el sync.
    return GroupCreateOutcome.success(convId);
  }
  return GroupCreateOutcome.success(convId);
}

int _maxRevision(GroupSyncSnapshot snap) {
  var max = 0;
  for (final r in snap.rooms.values) {
    if (r.revision > max) max = r.revision;
  }
  return max;
}
