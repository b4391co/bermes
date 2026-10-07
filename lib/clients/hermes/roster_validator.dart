/// Valida el roster que se MANDA a `groups.create`, espejo del contrato REAL
/// verificado contra un gateway 0.21.5 por sonda WS directa (2026-10-07):
///
/// - 2..6 miembros;
/// - CADA miembro exige `member_id`, `profile` y `handle` (el backend responde
///   5111 «member N is missing fields: member_id» / «…handle, profile»);
/// - miembro local: SIN `target` (el backend rellena
///   `target:{kind:'local', profile:…}`);
/// - miembro remoto: `target:{kind:'peer', peer_id, installation_id,
///   capability_digest, profile}`;
/// - al menos un miembro LOCAL.
///
/// Errores históricos que este validador caza:
/// - 0.1.48: perfil en `name` y `target` string → rechazado;
/// - 0.1.49: `name` de espejo añadido al wire → rechazado;
/// - 0.1.50: sin `member_id` (se creía server-owned) → 5111 SIEMPRE → la sala
///   nunca quedaba hosted → `groups.send` 4112 → «no deja enviar».
({String? code, String? message})? validateRosterWire(
  List<Map<String, Object?>> members,
  Set<String> localProfiles,
) {
  if (members.length < 2 || members.length > 6) {
    return (code: '4000', message: 'members must contain between 2 and 6 entries');
  }
  final ids = <String>{};
  final profiles = <String>{};
  var hasLocal = false;
  for (var i = 0; i < members.length; i++) {
    final m = members[i];
    for (final k in const ['member_id', 'profile', 'handle']) {
      final v = m[k];
      if (v == null || (v is String && v.trim().isEmpty)) {
        return (code: '4000', message: 'member $i is missing fields: $k');
      }
      if (v is! String) {
        return (code: '4000', message: '$k must be a string');
      }
    }
    if (m['display_name'] != null && m['display_name'] is! String) {
      return (code: '4000', message: 'display_name must be a string');
    }
    final profile = m['profile'] as String;
    final isLocal = localProfiles.contains(profile);
    final target = m['target'];
    if (target == null) {
      if (!isLocal) {
        return (code: '4000', message: 'member $i is remote but omits target');
      }
      hasLocal = true;
      ids.add('local:${m['member_id']}');
    } else if (target is! Map) {
      return (code: '4000', message: 'target must be an object');
    } else {
      final kind = target['kind'];
      if (kind != 'peer') {
        return (code: '4000', message: 'member $i target kind must be local or peer');
      }
      for (final k in const ['peer_id', 'installation_id', 'capability_digest', 'profile']) {
        final v = target[k];
        if (v == null || (v is String && v.trim().isEmpty)) {
          return (code: '4000', message: 'member $i peer target is missing fields: $k');
        }
      }
      if (isLocal) {
        return (code: '4000', message: 'member $i is local but sets peer target');
      }
      ids.add('peer:${m['member_id']}');
    }
    if (!profiles.add(profile)) {
      return (code: '4000', message: 'duplicate profile $profile');
    }
  }
  if (ids.length != members.length) {
    return (code: '4000', message: 'duplicate member identity');
  }
  if (!hasLocal) {
    return (code: '4115', message: 'no member profile is local');
  }
  return null;
}
