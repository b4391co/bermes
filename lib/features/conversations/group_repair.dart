import 'dart:convert';

import 'package:drift/drift.dart' as drift show Value;


import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/rooms_client.dart';
import '../../data/database/app_database.dart' as db;

/// Reparación EN SITIO de grupos zombis: salas creadas por 0.1.48–0.1.50
/// cuya fila existe (espejo + fila local) pero NUNCA quedó hosted en ningún
/// gateway (faltaba `member_id` → 5111 → 4112 en cada `groups.send`).
///
/// Contrato verificado por sonda (2026-10-07/08, gateway 0.21.5 real):
/// `groups.create` con el MISMO `room_id` + mismo nombre + mismos miembros
/// devuelve LA MISMA sala (idempotente); con otro contenido → 4110. O sea:
/// re-crear con el roomId guardado y el roster correcto repara la sala SIN
/// duplicarla y sin perder el historial del espejo.
///
/// Los miembros deben ser del MISMO gateway (los pares cross-gateway exigen
/// registro HTTPS; en LAN http:// no hay ruta). La reparación usa el gateway
/// que tenga ≥2 bots del grupo; el resto quedan en el espejo.
class GroupRepairResult {
  final bool repaired;
  final String? hostConnectionId;
  final String? error;

  const GroupRepairResult({
    required this.repaired,
    this.hostConnectionId,
    this.error,
  });
}

Future<GroupRepairResult> repairGroupRoom({
  required db.AppDatabase database,
  required Map<String, ConnectionRuntime> runtimes,
  required db.Conversation conv,
  required String roomId,
  required String name,
}) async {
  // Roster del espejo persistido en la fila (groupMembersJson).
  final raw = conv.groupMembersJson;
  if (raw == null || raw.isEmpty) {
    return const GroupRepairResult(
      repaired: false,
      error: 'sin miembros persistidos',
    );
  }
  List<Map<String, Object?>> members;
  try {
    members = [
      for (final m in (jsonDecode(raw) as List).whereType<Map>())
        m.cast<String, Object?>(),
    ];
  } catch (_) {
    return const GroupRepairResult(
      repaired: false,
      error: 'miembros persistidos ilegibles',
    );
  }
  if (members.length < 2) {
    return const GroupRepairResult(
      repaired: false,
      error: 'el grupo tiene menos de 2 bots',
    );
  }

  // Probar cada gateway implicado: el primero con ≥2 bots del grupo hostea.
  final candidates = <String>{conv.connectionId, for (final m in members) ...[
    (m['connectionId'] as String?) ?? '',
    (m['installId'] as String?) ?? '',
  ]};
  String? lastError;
  for (final connId in candidates) {
    if (connId.isEmpty) continue;
    final runtime = runtimes[connId];
    if (runtime == null) continue;

    // ¿Qué perfiles existen en ESTE gateway? Los miembros del grupo cuyo
    // perfil esté aquí van SIN target; los demás se quedan fuera de la sala
    // hosted (cross-gateway = pares HTTPS-only) pero siguen en el espejo.
    Set<String> localProfiles;
    try {
      final profiles = await runtime.gateway.listProfiles();
      localProfiles = {for (final p in profiles) p['name'] as String? ?? ''}
        ..remove('');
    } catch (e) {
      lastError = 'gateway ${runtime.profile.name}: $e';
      continue;
    }
    // Locales = miembros cuyo descriptor apunta a ESTE gateway (o no apunta a
    // ninguno → legacies del mismo host). El mismo PERFIL puede aparecer
    // varias veces en el espejo (`default` en This Webapp y en
    // Z03_Bernardino): la sala hosted sólo admite un miembro por perfil del
    // anfitrión (5111 «member profiles must be unique»), así que se DEDUPEA
    // por perfil — el descriptor de este gateway manda; sin dedupe, la
    // reparación fallaba siempre y el grupo fantasma quedaba muerto
    // («no deja escribir»).
    final connIsLocal = connId == conv.connectionId;
    final localsByProfile = <String, Map<String, Object?>>{};
    for (final m in members) {
      final profile = m['name'] as String?;
      if (profile == null || !localProfiles.contains(profile)) continue;
      final desc = ((m['connectionId'] ?? m['connectionLabel'] ?? '') as String)
          .toLowerCase();
      final own = desc.isEmpty ||
          desc == connId.toLowerCase() ||
          desc == 'local' ||
          desc == runtime.profile.name.toLowerCase() ||
          (connIsLocal && (desc == 'local' || desc.isEmpty));
      final prior = localsByProfile[profile];
      if (own || prior == null) {
        // preferir el propio de este gateway: si ya había uno propio y llega
        // un ajeno, no se pisa.
        if (prior != null && !own) continue;
        localsByProfile[profile] = m;
      }
    }
    final locals = localsByProfile.values.toList();
    if (locals.length < 2) continue;

    final rows = [
      for (final (i, m) in locals.indexed)
        {
          'member_id': 'm$i-${roomId.substring(0, roomId.length.clamp(0, 8))}',
          'profile': m['name'],
          'handle': m['handle'] ?? m['name'],
          if (m['display_name'] != null) 'display_name': m['display_name'],
        },
    ];
    final invalid = validateRosterWire(rows, localProfiles);
    if (invalid != null) {
      lastError = '${invalid.code}: ${invalid.message}';
      continue;
    }
    try {
      final room = await RoomsClient(
        runtime.gateway,
      ).create(name, rows, roomId: roomId);
      if (room != null) {
        await (database.update(
          database.conversations,
        )..where((t) => t.id.equals(conv.id))).write(
          db.ConversationsCompanion(groupHosted: const drift.Value(true)),
        );
        return GroupRepairResult(
          repaired: true,
          hostConnectionId: connId,
        );
      }
      lastError = 'gateway ${runtime.profile.name}: respuesta vacía';
    } catch (e) {
      lastError = 'gateway ${runtime.profile.name}: $e';
    }
  }
  return GroupRepairResult(
    repaired: false,
    error: lastError ?? 'ningún gateway con los bots del grupo está disponible',
  );
}
