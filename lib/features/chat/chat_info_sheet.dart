import 'package:flutter/material.dart';

import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/gateway_client.dart';
import '../../clients/hermes/rooms_client.dart';
import '../../core/app_services.dart';
import '../../data/database/app_database.dart' as db;
import '../../design/tokens.dart';
import '../app_shell.dart' show BotAvatar;

/// Sheet de "info de contacto" (estilo WhatsApp): tocar la cabecera del chat
/// abre esta vista con la identidad del bot o del grupo y sus ajustes.
///
/// - Bot: descripción, estado y **modelo** — lectura por RPC `model.options`
///   (contrato tui_gateway/contracts/config_free_tier_control.py:213-281) y
///   escritura por `PUT /api/profiles/{name}/model`
///   (hermes_cli/web_routers/profiles.py:1040-1051, el mismo camino validado
///   que `/api/model/set` del dashboard; Desktop no lo consume pero el
///   endpoint es del gateway real de la versión objetivo e408d36).
/// - Grupo: miembros reales de la sala por `groups.state`
///   (rooms_client.dart:166-181), cada uno con su icono resuelto de la tabla
///   de bots (identity: perfil del backend, no el nombre visible).
class ChatInfoSheet extends StatefulWidget {
  final db.Conversation conversation;
  final ConnectionRuntime? runtime;

  const ChatInfoSheet({
    super.key,
    required this.conversation,
    required this.runtime,
  });

  @override
  State<ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends State<ChatInfoSheet> {
  late Future<_InfoData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InfoData> _load() async {
    final conv = widget.conversation;
    if (!conv.isGroup) return const _InfoData();
    final runtime = widget.runtime;
    final roomId = conv.groupRoomId;
    if (runtime == null || roomId == null) return const _InfoData();
    // Iconos por perfil del backend: la identidad del miembro es el nombre de
    // perfil (`RoomMember.profile`), NO el display name — dos bots llamados
    // igual en gateways distintos son bots distintos (encargo §5).
    final rows = await (AppServices.db.select(AppServices.db.conversations)
          ..where((c) => c.kind.equals('bot')))
        .get();
    final avatars = <String, db.Conversation>{
      for (final r in rows) r.gatewayId: r,
    };
    final room = await RoomsClient(runtime.gateway).roomState(roomId);
    return _InfoData(
      members: room?.members ?? const <RoomMember>[],
      botRows: avatars,
    );
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: Hp.s3),
                BotAvatar(
                  seed: conv.avatarSeed ?? conv.id,
                  label: conv.title,
                  size: 84,
                  isGroup: conv.isGroup,
                  imageUrl: conv.avatarUrl,
                  avatarMetaJson: conv.botAvatarMeta,
                ),
                const SizedBox(height: Hp.s3),
                Text(
                  _titleOverride ?? conv.title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                if ((conv.subtitle ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Hp.s1),
                    child: Text(
                      conv.subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
          ),
          if (conv.isGroup) _groupMembers(scroll, cs) else _botModel(cs),
          const SliverToBoxAdapter(child: SizedBox(height: Hp.s6)),
        ],
      ),
    );
  }

  String? get _titleOverride => null;

  Widget _groupMembers(ScrollController scroll, ColorScheme cs) {
    return FutureBuilder<_InfoData>(
      future: _future,
      builder: (context, snap) {
        final members = snap.data?.members;
        if (members == null) {
          return const SliverToBoxAdapter(
            child: Center(child: Padding(
              padding: EdgeInsets.all(Hp.s4),
              child: CircularProgressIndicator(),
            )),
          );
        }
        return SliverList.builder(
          itemCount: members.length,
          itemBuilder: (context, i) {
            final m = members[i];
            final profile = m.profile ?? m.handle ?? '?';
            final row = snap.data?.botRows[profile];
            final shown = row?.title ?? m.displayName ?? profile;
            return ListTile(
              leading: row == null
                  ? BotAvatar(seed: profile, label: shown, size: 40)
                  : BotAvatar(
                      seed: row.avatarSeed ?? row.id,
                      label: row.title,
                      size: 40,
                      imageUrl: row.avatarUrl,
                      avatarMetaJson: row.botAvatarMeta,
                    ),
              title: Text(shown),
              subtitle: row == null
                  ? Text(profile, maxLines: 1, overflow: TextOverflow.ellipsis)
                  : Text(
                      row.gatewayLabel ?? profile,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            );
          },
        );
      },
    );
  }

  Widget _botModel(ColorScheme cs) {
    final runtime = widget.runtime;
    final conv = widget.conversation;
    final profile = conv.gatewayId; // identidad: nombre del perfil del bot
    if (runtime == null || profile.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: _ModelSection(runtime: runtime, profile: profile),
    );
  }
}

class _InfoData {
  final List<RoomMember> members;
  final Map<String, db.Conversation> botRows;
  const _InfoData({this.members = const [], this.botRows = const {}});
}

class _ModelSection extends StatefulWidget {
  final ConnectionRuntime runtime;
  final String profile;

  const _ModelSection({required this.runtime, required this.profile});

  @override
  State<_ModelSection> createState() => _ModelSectionState();
}

class _ModelSectionState extends State<_ModelSection> {
  late Future<ModelOptions?> _options;
  String? _provider;
  String? _model;
  bool _saving = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _options = widget.runtime.gateway
        .modelOptions(widget.profile)
        .then((o) {
      if (o != null && mounted) {
        setState(() {
          _provider = o.provider.isEmpty ? null : o.provider;
          _model = o.model.isEmpty ? null : o.model;
        });
      }
      return o;
    });
  }

  Future<void> _reload() async {
    setState(() => _options = widget.runtime.gateway
        .modelOptions(widget.profile, refresh: true));
    final o = await _options;
    if (o != null && mounted) {
      setState(() {
        _provider = o.provider.isEmpty ? null : o.provider;
        _model = o.model.isEmpty ? null : o.model;
      });
    }
  }

  Future<void> _save() async {
    final provider = _provider;
    final model = _model;
    if (provider == null || provider.isEmpty || model == null || model.isEmpty) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    try {
      await widget.runtime.gateway
          .setProfileModel(widget.profile, provider: provider, model: model);
      if (mounted) setState(() => _saved = '$provider · $model');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s5, Hp.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.memory_rounded, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: Hp.s2),
              Text(
                'Modelo',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Recargar lista',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: _reload,
              ),
            ],
          ),
          const SizedBox(height: Hp.s3),
          FutureBuilder<ModelOptions?>(
            future: _options,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(Hp.s4),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final options = snap.data;
              if (options == null || options.providers.isEmpty) {
                return Text(
                  'El gateway no expone la lista de modelos para este bot.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                );
              }
              return _picker(options);
            },
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: Hp.s2),
              child: Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Hp.error),
              ),
            ),
          if (_saved != null)
            Padding(
              padding: const EdgeInsets.only(top: Hp.s2),
              child: Text(
                'Modelo aplicado: $_saved',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                    ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _picker(ModelOptions options) {
    final configured = options.providers
        .where((p) => p.authenticated != false && p.models.isNotEmpty)
        .toList();
    final currentProvider = configured.any((p) => p.slug == _provider)
        ? _provider
        : (configured.isNotEmpty ? configured.first.slug : null);
    final currentModels = currentProvider == null
        ? const <String>[]
        : configured
                .firstWhere((p) => p.slug == currentProvider,
                    orElse: () => configured.first)
                .models;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: currentProvider,
          decoration: const InputDecoration(
            labelText: 'Proveedor',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final p in configured)
              DropdownMenuItem(value: p.slug, child: Text(p.name)),
          ],
          onChanged: (v) => setState(() {
            _provider = v;
            final models = configured
                .firstWhere((p) => p.slug == v, orElse: () => configured.first)
                .models;
            _model = models.contains(_model) ? _model : models.firstOrNull;
          }),
        ),
        const SizedBox(height: Hp.s3),
        DropdownButtonFormField<String>(
          initialValue: _model != null && currentModels.contains(_model)
              ? _model
              : currentModels.firstOrNull,
          decoration: const InputDecoration(
            labelText: 'Modelo',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final m in currentModels)
              DropdownMenuItem(value: m, child: Text(m)),
          ],
          onChanged: (v) => setState(() => _model = v),
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
              : const Icon(Icons.check_rounded, size: 18),
          label: const Text('Aplicar modelo'),
        ),
      ],
    );
  }
}
