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

  const BotRosterMeta({this.title, this.description, this.avatar, this.hidden});

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

    return BotRosterMeta(
      title: s('title'),
      description: s('description'),
      avatar: BotAvatarMeta.fromJson(raw['avatar']),
      hidden: raw['hidden'] == true,
    );
  }

  Map<String, Object?> toUiMetaSection() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (avatar != null) 'avatar': avatar!.toJson(),
        if (hidden != null) 'hidden': hidden,
      };
}
