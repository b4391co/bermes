/// Metadatos de roster de bots — contrato `ui_meta['hermes-bots']`.
///
/// Fuente de verdad: Hermes Desktop (`contracts/profiles_vault_complete_foreign_subagents.py`,
/// `ui_meta.hermes-bots`) y la app de referencia Hy4ri/hermes-mobile
/// (`data/model/Profile.kt`: `BotRosterMeta` / `BotAvatarMeta`).
///
/// - Nombre visible: `botMeta.title` > `display_name` > `name`.
/// - Avatar: `botMeta.avatar {shape, color, icon, image_url}` renderizado nativo
///   (formas y colores propios, `image_url` por HTTP); `profiles.get_asset`
///   (data-url) como último recurso.
/// - `hidden: true` oculta el bot del roster.
library;

class BotAvatarMeta {
  final String? shape; // circle | square | rounded | hexagon
  final String? color; // hex #RRGGBB
  final String? icon; // nombre de Material icon (smart_toy, science, …)
  final String? imageUrl; // URL HTTP directa

  const BotAvatarMeta({this.shape, this.color, this.icon, this.imageUrl});

  static BotAvatarMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? s(String k) {
      final v = raw[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final any = BotAvatarMeta(
      shape: s('shape'),
      color: s('color'),
      icon: s('icon'),
      imageUrl: s('image_url'),
    );
    return (any.shape == null &&
            any.color == null &&
            any.icon == null &&
            any.imageUrl == null)
        ? null
        : any;
  }

  Map<String, Object?> toJson() => {
        if (shape != null) 'shape': shape,
        if (color != null) 'color': color,
        if (icon != null) 'icon': icon,
        if (imageUrl != null) 'image_url': imageUrl,
      };
}

class BotRosterMeta {
  final String? title;
  final String? description;
  final BotAvatarMeta? avatar;
  final bool? hidden;
  final List<String> groups;

  /// Sección `hermes-bots` cruda del gateway: claves que Pocket no modela
  /// (pinned, sectionId, sectionName, screenAutoOpen, created…) y que DEBEN
  /// volver en la escritura porque el gateway reemplaza la sección entera.
  final Map<String, Object?> raw;

  const BotRosterMeta({
    this.title,
    this.description,
    this.avatar,
    this.hidden,
    this.groups = const [],
    this.raw = const {},
  });

  /// `ui_meta['hermes-bots']` de una ProfileRow; null si no hay sección.
  static BotRosterMeta? fromProfile(Map<String, Object?> profile) {
    final uiMeta = profile['ui_meta'];
    if (uiMeta is! Map) return null;
    final raw = uiMeta['hermes-bots'];
    if (raw is! Map) return null;
    String? s(String k) {
      final v = raw[k];
      return v is String && v.isNotEmpty ? v : null;
    }

    final groups = <String>{
      ...?switch (raw['groups']) {
        final List<Object?> l => l.whereType<String>(),
        _ => null,
      },
      if (raw['group'] is String && (raw['group'] as String).isNotEmpty)
        raw['group'] as String,
    }.where((g) => g.trim().isNotEmpty).map((g) => g.trim()).toList();
    return BotRosterMeta(
      title: s('title'),
      description: s('description'),
      avatar: BotAvatarMeta.fromJson(raw['avatar']),
      hidden: raw['hidden'] == true,
      groups: groups,
      // Claves que Pocket no edita pero Desktop SÍ guarda en esta sección
      // (`types.ts:65-88`: pinned, sectionId, sectionName, screenAutoOpen,
      // created, image_url…). El servidor REEMPLAZA la sección entera
      // (methods_profiles.py:600-606): sin reenviarlas, un guardado desde
      // Pocket las borra y Desktop pierde filing/autoraise.
      raw: Map<String, Object?>.from(raw),
    );
  }

  /// Sección `hermes-bots` completa: campos editados + claves ajenas
  /// preservadas. Los campos editados mandan; los que Pocket no toca viajan
  /// tal cual estaban.
  Map<String, Object?> toUiMetaSection() {
    final out = Map<String, Object?>.from(raw);
    out.remove('group'); // proyección legacy: la regenera Desktop si aplica
    if (title != null) {
      out['title'] = title;
    } else {
      out.remove('title');
    }
    if (description != null) {
      out['description'] = description;
    } else {
      out.remove('description');
    }
    if (avatar != null) {
      out['avatar'] = avatar!.toJson();
    }
    if (hidden != null) out['hidden'] = hidden;
    if (groups.isNotEmpty) out['groups'] = groups;
    return out;
  }
}
