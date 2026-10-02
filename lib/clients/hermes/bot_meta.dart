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

  /// Imagen de avatar leída del almacén de assets del gateway
  /// (`profiles.get_asset`), cuando el bot la tiene. Null = sin imagen:
  /// mandan icono/shape/colour del meta.
  final String? imageDataUrl;

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
    this.imageDataUrl,
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

  /// Copia con la imagen de avatar leída del almacén de assets del gateway
  /// (`profiles.get_asset`). Null = sin imagen: mandan icono/shape/colour
  /// del meta.
  BotRosterMeta withImage(String? imageDataUrl) => BotRosterMeta(
    title: title,
    description: description,
    avatar: avatar,
    hidden: hidden,
    groups: groups,
    raw: raw,
    imageDataUrl: imageDataUrl,
  );

  /// Sección `hermes-bots` completa: campos editados + claves ajenas
  /// preservadas. Es la forma correcta de reenviar la sección cuando se toca
  /// otra cosa (los campos que Pocket no edita NO se escriben, viajan crudos).
  ///
  /// Un campo con valor vacío significa "el usuario lo borró" → se QUITA la
  /// clave (no se manda `''`: Desktop la trata como ausente, `types.ts:65-88`).
  /// Null significa "no lo tocamos" → se deja el raw tal cual.
  ///
  /// `imageDataUrl` (avatar del almacén de assets) se PROYECTA en
  /// `avatar.image_url` para que este meta pueda volver al gateway sin borrar
  /// la imagen del otro canal — el sync lee `BotAvatarMeta.imageUrl`.
  Map<String, Object?> toUiMetaSection() {
    final out = Map<String, Object?>.from(raw);
    out.remove('group'); // proyección legacy: la regenera Desktop si aplica
    void put(String key, String? value) {
      if (value == null) return; // no tocado: el raw manda
      if (value.isEmpty) {
        out.remove(key);
      } else {
        out[key] = value;
      }
    }

    put('title', title);
    put('description', description);
    if (avatar != null || imageDataUrl != null) {
      final a = (avatar ?? const BotAvatarMeta()).toJson();
      if (imageDataUrl != null) a['image_url'] = imageDataUrl;
      if (a.isEmpty) {
        out.remove('avatar');
      } else {
        out['avatar'] = a;
      }
    }
    if (hidden != null) out['hidden'] = hidden;
    if (groups.isNotEmpty) {
      out['groups'] = groups;
    } else {
      out.remove('groups');
    }
    return out;
  }
}
