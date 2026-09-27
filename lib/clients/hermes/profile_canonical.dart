/// Extrae la sesión canónica "Bot Chat" de un perfil de `profiles.list`.
///
/// Formas reales observadas (docs/protocol/hermes-map.md §3 + hermes-mobile
/// Profile.kt::CanonicalSessionInfo):
/// - objeto {id, resolved_id, title, …} — versión actual del gateway;
///   resolved_id es la sesión viva y tiene prioridad.
/// - string suelto — versiones antiguas.
/// null = el gateway no la expone (el llamador decide el fallback resume/create).
String? canonicalFromProfile(Map<String, Object?> p) {
  final raw = p['canonical_session'];
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is Map) {
    final id = (raw['resolved_id'] ?? raw['id'] ?? raw['session_id'])
        ?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }
  return null;
}
