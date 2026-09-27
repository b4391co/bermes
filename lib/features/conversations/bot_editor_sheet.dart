import 'package:flutter/material.dart';

import '../../clients/hermes/bot_meta.dart';
import '../../core/app_services.dart';
import '../../design/tokens.dart';

/// Edición de un bot (nombre visible, descripción, forma y color del
/// avatar) — equivalente a EditBotBottomSheet de Hy4ri/hermes-mobile.
///
/// Guarda vía WS `profiles.configure {name, ui_meta:{hermes-bots:{…}}}`;
/// la fila local se refresca a través del resync del roster.
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
  bool _saving = false;

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
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final runtime = AppServices.connections.runtimeFor(widget.connectionId);
    var ok = false;
    if (runtime != null) {
      try {
        ok = await runtime.gateway.configureBot(
          widget.profileName,
          title: _title.text.trim(),
          description: _description.text.trim(),
          avatar: BotAvatarMeta(shape: _shape, color: _color),
        );
        if (ok) {
          await AppServices.connections.resyncAll();
        }
      } catch (_) {
        ok = false;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo guardar (gateway no conectado o versión sin profiles.configure)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Hp.s4,
        Hp.s3,
        Hp.s4,
        Hp.s4 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Editar bot', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Hp.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _hexColor(_color) ?? cs.primary,
                  shape: _shape == 'circle'
                      ? BoxShape.circle
                      : BoxShape.rectangle,
                  borderRadius: _shape == 'circle'
                      ? null
                      : BorderRadius.circular(_shape == 'square' ? 0 : 14),
                ),
                child: Text(
                  _title.text.trim().isEmpty
                      ? '?'
                      : _title.text.trim().characters.take(2).toString().toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
    );
  }

  Color? _hexColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }
}
