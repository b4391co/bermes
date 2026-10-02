import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../clients/hermes/bot_meta.dart';
import '../../core/app_services.dart';
import '../../design/tokens.dart';
import '../app_shell.dart';
import 'avatar_image.dart';

/// Edición de un bot: nombre visible, descripción, forma, color, **icono** e
/// **imagen** del avatar. Equivalente a `EditProfileDialog` de Hermes Desktop
/// (`plugins/hermes-bots/edit-profile-dialog.tsx`), con sus dos canales de
/// guardado:
///
///  - `profiles.configure` con la sección `hermes-bots` completa + CAS →
///    title/description/avatar{shape,color,icon}.
///  - `profiles.set_asset {asset:'avatar', data}` → la IMAGEN (los data-URL
///    no caben en ui_meta: tope de 64 KB por clave y viajarían en cada
///    `profiles.list`; Desktop hace exactamente lo mismo, `data.ts:380-408`).
class BotEditorSheet extends StatefulWidget {
  final String connectionId;
  final String profileName; // identidad estable (name del perfil)
  final String currentTitle;
  final String? currentDescription;
  final BotAvatarMeta? currentAvatar;

  const BotEditorSheet({
    super.key,
    required this.connectionId,
    required this.profileName,
    required this.currentTitle,
    this.currentDescription,
    this.currentAvatar,
  });

  static Future<bool> show(
    BuildContext context, {
    required String connectionId,
    required String profileName,
    required String currentTitle,
    String? currentDescription,
    BotAvatarMeta? currentAvatar,
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BotEditorSheet(
        connectionId: connectionId,
        profileName: profileName,
        currentTitle: currentTitle,
        currentDescription: currentDescription,
        currentAvatar: currentAvatar,
      ),
    );
    return ok == true;
  }

  @override
  State<BotEditorSheet> createState() => _BotEditorSheetState();
}

class _BotEditorSheetState extends State<BotEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late String _shape;
  late String _color;

  /// Icono Material elegido (null = sin icono → iniciales).
  late String? _icon;

  /// Imagen del bot (asset del gateway). [_imageTouched] distingue
  /// "la quité/puse" de "no la toqué": un `clear` a destiempo puede borrar la
  /// imagen que otra máquina acaba de empujar (así lo motiva Desktop en
  /// `data.ts:377-379`).
  Uint8List? _image;
  bool _imageTouched = false;
  bool _saving = false;
  String? _notice;

  static const _shapes = <(String, String)>[
    ('rounded', 'Redondeado'),
    ('circle', 'Círculo'),
    ('square', 'Cuadrado'),
  ];
  static const _colors = <String>[
    '#1a7f5a', // verde hermes
    '#5b6ee1', // índigo
    '#c94f7c', // rosa
    '#c2842f', // ámbar
    '#3d7dd8', // azul
    '#7a4fd0', // violeta
  ];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.currentTitle);
    _description = TextEditingController(text: widget.currentDescription ?? '');
    _shape = widget.currentAvatar?.shape ?? 'rounded';
    _color = widget.currentAvatar?.color ?? _colors.first;
    _icon = widget.currentAvatar?.icon;
    // El subtítulo local compone descripción + ' · Grupos: …' (syncBots).
    // Editar SOBRE el compuesto duplica el sufijo al guardar. La descripción
    // base real vive en el gateway: se lee y reemplaza en cuanto llega.
    _loadRealMeta();
  }

  Future<void> _loadRealMeta() async {
    final runtime = AppServices.connections.runtimeFor(widget.connectionId);
    if (runtime == null) return;
    try {
      final found = await runtime.gateway.profileRosterMeta(
        widget.profileName,
        withAvatar: true,
      );
      final m = found.meta;
      if (m == null || !mounted) return;
      setState(() {
        final d = m.description;
        if (d != null && d.isNotEmpty) _description.text = d;
        if (m.avatar?.shape != null) _shape = m.avatar!.shape!;
        if (m.avatar?.color != null) _color = m.avatar!.color!;
        _icon = m.avatar?.icon;
        // La imagen real está en el almacén de assets (`imageDataUrl`); el
        // `image_url` del meta es la proyección que reenvían los clientes.
        if (!_imageTouched) {
          final img = m.imageDataUrl ?? m.avatar?.imageUrl;
          if (img != null) _image = AvatarImage.fromDataUrl(img);
        }
      });
    } catch (_) {
      // Gateway no disponible: el fallback local (subtitle) ya está en el campo.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final raw = await AvatarImage.pick();
    if (!mounted) return;
    if (raw == null) return;
    if (raw.lengthInBytes > AvatarImage.maxBytes) {
      setState(
        () => _notice =
            'La imagen supera 2 MB (tope del gateway). Elige una más pequeña.',
      );
      return;
    }
    setState(() => _saving = true);
    // PNG recortado y a 256 px, como Desktop. Si no decodifica (formato que
    // el gateway rechazaría por mágia), no se sube: se avisa.
    final png = await AvatarImage.normalize(raw);
    if (!mounted) return;
    setState(() => _saving = false);
    if (png == null) {
      setState(
        () => _notice =
            'No se pudo procesar la imagen (¿PNG, JPEG o WebP válido?).',
      );
      return;
    }
    setState(() {
      _image = png;
      _imageTouched = true;
      _notice = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _notice = null;
    });
    final runtime = AppServices.connections.runtimeFor(widget.connectionId);
    var ok = false;
    var imageOk = true; // false sólo si el gateway habló y RECHAZÓ
    if (runtime != null) {
      try {
        // profiles.configure reemplaza la sección ui_meta['hermes-bots'] del
        // perfil: sin preservar `groups` se perderían los grupos del Desktop.
        // Con revision CAS: si Desktop escribió desde que abrimos el sheet,
        // el gateway rechaza y avisamos en vez de pisar el cambio ajeno.
        final existing = await runtime.gateway.profileRosterMeta(
          widget.profileName,
          withAvatar: true,
        );
        final hadImage =
            existing.meta?.imageDataUrl ?? existing.meta?.avatar?.imageUrl;
        ok = await runtime.gateway.configureBot(
          widget.profileName,
          title: _title.text.trim(),
          description: _description.text.trim(),
          avatar: BotAvatarMeta(
            shape: _shape,
            color: _color,
            icon: _icon,
            // La imagen NO viaja por ui_meta (su canal es set_asset); sólo se
            // re-proyecta si no se tocó, para no romper la referencia que
            // otros clientes leen del meta.
            imageUrl: _imageTouched ? null : hadImage,
          ),
          expectedRevision: existing.revision,
          rawSection: existing.meta?.raw ?? const {},
        );
        if (_imageTouched) {
          final img = _image;
          imageOk = img == null
              ? await runtime.gateway.setProfileAvatar(
                  widget.profileName,
                  clear: true,
                )
              : await runtime.gateway.setProfileAvatar(
                  widget.profileName,
                  dataUrl: AvatarImage.toDataUrl(img),
                );
        }
        if (ok || imageOk) {
          await AppServices.connections.resyncAll();
        }
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok || imageOk) {
      if (!imageOk) {
        setState(
          () => _notice =
              'Icono guardado, pero la imagen no: este gateway no acepta '
              'profiles.set_asset.',
        );
        return;
      }
      Navigator.of(context).pop(true);
    } else {
      setState(
        () => _notice = runtime == null
            ? 'Sin conexión con el gateway de este bot.'
            : 'No se pudo guardar: gateway antiguo sin profiles.configure/'
                  'set_asset, o el otro cliente cambió el bot a la vez.',
      );
    }
  }

  Widget _preview(ColorScheme cs) {
    final img = _image;
    if (img != null) {
      return ClipOval(
        child: Image.memory(
          img,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _metaPreview(),
        ),
      );
    }
    return _metaPreview();
  }

  Widget _metaPreview() => BotAvatar(
    seed: widget.profileName,
    label: _title.text.trim().isEmpty ? '?' : _title.text.trim(),
    size: 64,
    avatarMetaJson: const JsonEncoder().convert(
      BotAvatarMeta(shape: _shape, color: _color, icon: _icon).toJson(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      // SafeArea bottom: sin ella el botón Guardar queda bajo la gesture-bar
      // del sistema (Android 15 edge-to-edge) y el tap llega al launcher.
      padding: EdgeInsets.fromLTRB(
        Hp.s4,
        Hp.s1,
        Hp.s4,
        Hp.s4 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar bot', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: Hp.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _preview(cs),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Subir imagen',
                          onPressed: _saving ? null : _pickImage,
                          icon: const Icon(Icons.upload_rounded, size: 20),
                        ),
                        if (_image != null)
                          IconButton(
                            tooltip: 'Quitar imagen',
                            onPressed: () => setState(() {
                              _image = null;
                              _imageTouched = true;
                            }),
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(width: Hp.s3),
                Expanded(
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Nombre visible',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Hp.s3),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: Hp.s3),
            SegmentedButton<String>(
              segments: [
                for (final (v, l) in _shapes)
                  ButtonSegment(value: v, label: Text(l)),
              ],
              selected: {_shape},
              onSelectionChanged: (s) => setState(() => _shape = s.first),
            ),
            const SizedBox(height: Hp.s3),
            Wrap(
              spacing: Hp.s2,
              children: [
                for (final hex in _colors)
                  GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _hexColor(hex),
                        shape: BoxShape.circle,
                        border: _color == hex
                            ? Border.all(color: cs.onSurface, width: 2.5)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Hp.s4),
            Text(
              'Icono',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _image == null
                  ? 'Se guarda en el perfil: se ve igual en Hermes Desktop.'
                  : 'Con imagen, el icono sólo asoma si la imagen no carga.',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: Hp.s2),
            Wrap(
              spacing: Hp.s2,
              runSpacing: Hp.s2,
              children: [
                for (final name in BotAvatar.iconChoices)
                  _swatch(
                    context,
                    selected: _icon == name,
                    onTap: () => setState(() {
                      _icon = name;
                      _image = null;
                      _imageTouched = true;
                    }),
                    child: Icon(
                      BotAvatar.iconFor(name) ?? Icons.smart_toy_rounded,
                      size: 22,
                      color: _hexColor(_color) ?? cs.primary,
                    ),
                  ),
                _swatch(
                  context,
                  selected: _icon == null && _image == null,
                  onTap: () => setState(() {
                    _icon = null;
                    _image = null;
                    _imageTouched = true;
                  }),
                  child: Text(
                    _initials(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _hexColor(_color) ?? cs.primary,
                    ),
                  ),
                ),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: Hp.s3),
              Text(_notice!, style: TextStyle(color: cs.error, fontSize: 12.5)),
            ],
            const SizedBox(height: Hp.s4),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  String _initials() {
    final t = _title.text.trim();
    if (t.isEmpty) return '?';
    return t.characters.take(2).toString().toUpperCase();
  }

  Widget _swatch(
    BuildContext context, {
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Hp.rSm),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(Hp.rSm),
          border: selected
              ? Border.all(color: cs.primary, width: 2)
              : Border.all(color: cs.outlineVariant),
        ),
        child: child,
      ),
    );
  }

  Color? _hexColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}
