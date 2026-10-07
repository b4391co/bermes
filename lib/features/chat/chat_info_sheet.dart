import 'dart:convert';

import 'package:flutter/material.dart';

import '../../clients/hermes/connection_manager.dart';
import '../../clients/hermes/gateway_client.dart';
import '../../clients/hermes/rooms_client.dart';
import '../../core/app_services.dart';
import '../../data/database/app_database.dart' as db;
import '../../design/tokens.dart';
import '../app_shell.dart' show BotAvatar;
import '../conversations/group_rooms.dart';

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
  Map<String, String> _installIdToConn = const {};

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_InfoData> _load() async {
    // Fila FRESCA: tras editar miembros, resyncOne actualiza
    // groupMembersJson en la BD y el sheet debe releerla (widget.conversation
    // es una instantánea previa a la edición).
    final fresh = await (AppServices.db.select(
      AppServices.db.conversations,
    )..where((c) => c.id.equals(widget.conversation.id))).getSingleOrNull();
    final conv = fresh ?? widget.conversation;
    if (!conv.isGroup) return const _InfoData();
    final runtime = widget.runtime;
    final roomId = conv.groupRoomId;
    // Iconos indexados por las claves con las que un miembro puede nombrar
    // su conexión: id local, installId del backend y etiqueta del gateway
    // (la que Desktop usa en `connectionLabel`). Dos bots homónimos en
    // gateways distintos NO comparten clave: el mapa viejo indexaba sólo
    // por perfil y aplastaba la cara del segundo.
    final rows = await (AppServices.db.select(
      AppServices.db.conversations,
    )..where((c) => c.kind.equals('bot'))).get();
    final conns = await AppServices.db.select(AppServices.db.connections).get();
    final installIdToConn = {
      for (final c in conns)
        if (c.installId != null) c.installId!: c.id,
    };
    _installIdToConn = installIdToConn;
    final avatars = <String, db.Conversation>{
      for (final r in rows) ...{
        r.connectionId: r,
        for (final iid in installIdToConn.entries
            .where((e) => e.value == r.connectionId)
            .map((e) => e.key))
          iid: r,
        if (r.gatewayLabel != null) r.gatewayLabel!: r,
      },
      // Fallback sin conexión conocida: sólo si el perfil es único.
      for (final r in rows)
        if (rows.where((o) => o.gatewayId == r.gatewayId).length == 1)
          r.gatewayId: r,
    };
    // Miembros del espejo: `target` del RoomMember no existe en el mirror
    // (es clave de roster); `connectionLabel` nombra el origen.
    // sirven para salas sin roomId Y para salas cuyo roomId no hospeda ESTE
    // gateway (groups.state → 4112: la autoridad vive en otro gateway o en
    // Desktop). Primero se intenta groups.state en vivo; si falla o no hay
    // runtime, el espejo persistido es la fuente (y la editable).
    List<RoomMember> fromJson() => [
      for (final m in (jsonDecode(conv.groupMembersJson ?? '[]') as List)
          .whereType<Map>())
        // GroupMember del espejo usa `name` (perfil) + `connectionId`/
        // `installId` (identidad del backend); RoomMember del gateway llama
        // `member_id` a esa identidad. `target` en el espejo nombra el
        // gateway de origen (connectionLabel), no un dict.
        RoomMember.fromJson({
          ...m.cast<String, Object?>(),
          'profile': m['name'],
          'member_id': m['connectionId'] ?? m['installId'],
          'target': m['connectionLabel'],
          'display_name':
              m['display_name'] ?? m['title'] ?? m['connectionLabel'],
        }),
    ];
    // El origen de caras por conexión necesita el mapa dentro del estado:
    _installIdToConn = installIdToConn;
    if (roomId == null) return _InfoData(members: fromJson(), botRows: avatars);
    if (runtime != null) {
      try {
        final room = await RoomsClient(runtime.gateway).roomState(roomId);
        if (room != null && room.members.isNotEmpty) {
          return _InfoData(members: room.members, botRows: avatars);
        }
      } catch (_) {
        // 4112 (no hospedada aquí) u otro fallo: espejo persistido.
      }
    }
    return _InfoData(members: fromJson(), botRows: avatars);
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
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(Hp.s4),
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverList.builder(
              itemCount: members.length,
              itemBuilder: (context, i) {
                final m = members[i];
                final profile = m.profile ?? m.handle ?? '?';
                // La cara se resuelve POR CONEXIÓN: `member_id` del espejo
                // lleva el installId del backend; `RoomMember.target` del
                // gateway es el nombre de origen. Sin conexión clara y con
                // homónimos, mejor el avatar genérico del perfil que la cara
                // equivocada del otro gateway.
                final connId = m.memberId == null
                    ? null
                    : _installIdToConn[m.memberId!];
                final row = connId != null
                    ? snap.data?.botRows['$connId/bot/$profile']
                    : snap.data?.botRows[profile];
                // Homónimos entre gateways (default en Claudio y en Boneca):
                // el handle los distingue (default-boneca / default-claudio)
                // y el connectionLabel nombra el gateway de origen.
                final duplicated =
                    members
                        .where((o) => (o.profile ?? o.handle) == profile)
                        .length >
                    1;
                final shown = row?.title ?? m.displayName ?? profile;
                final title =
                    duplicated && m.handle != null && m.handle != shown
                    ? '$shown · ${m.handle}'
                    : shown;
                final origin = row?.gatewayLabel ?? m.target ?? profile;
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
                  title: Text(title),
                  subtitle: Text(
                    origin,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined),
                    tooltip: 'Quitar del grupo',
                    onPressed: () => _removeMember(m, shown),
                  ),
                );
              },
            ),
            SliverToBoxAdapter(child: _addMemberTile(cs)),
          ],
        );
      },
    );
  }

  Widget _addMemberTile(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Hp.s3, vertical: Hp.s2),
      child: OutlinedButton.icon(
        onPressed: _addMember,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Añadir miembro'),
      ),
    );
  }

  Future<void> _addMember() async {
    final data = await _future;
    if (!mounted) return;
    final candidates =
        data.botRows.values
            .where((r) => !data.members.any((m) => m.profile == r.gatewayId))
            .toList()
          ..sort((a, b) => a.title.compareTo(b.title));
    final picked = await showModalBottomSheet<db.Conversation>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in candidates)
              ListTile(
                leading: BotAvatar(
                  seed: r.avatarSeed ?? r.id,
                  label: r.title,
                  size: 36,
                  imageUrl: r.avatarUrl,
                  avatarMetaJson: r.botAvatarMeta,
                ),
                title: Text(r.title),
                subtitle: Text(
                  r.gatewayLabel ?? r.gatewayId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, r),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _applyMemberEdit((current) {
      // Descriptor igual al que publica el espejo (Oficina real):
      // name/handle = perfil; connectionId/Label clonados de un miembro
      // existente del MISMO gateway (Desktop agrupa por
      // connectionId::profile — inventar una conexión rompería el merge).
      final twin = data.members.cast<RoomMember?>().firstWhere((m) {
        final connId = m?.memberId == null
            ? null
            : _installIdToConn[m!.memberId!] ?? m.memberId;
        final row = connId == null
            ? null
            : data.botRows.values
                  .where((r) => r.connectionId == connId)
                  .firstOrNull;
        return row?.gatewayLabel == picked.gatewayLabel;
      }, orElse: () => null);
      return [
        ...current,
        {
          'name': picked.gatewayId,
          'handle': picked.gatewayId,
          'connectionId': twin?.memberId ?? picked.connectionId,
          'connectionLabel': picked.gatewayLabel,
          if (twin != null) 'sourceScoped': true,
        },
      ];
    });
  }

  Future<void> _removeMember(RoomMember m, String shown) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Quitar a $shown'),
        content: Text(
          'Se quitará del grupo «${widget.conversation.title}». '
          'El cambio se publica en el gateway y aparecerá en Desktop.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _applyMemberEdit(
      (current) => [
        for (final c in current)
          if (!((c['profile'] ?? c['name'] ?? c['handle']) ==
              (m.profile ?? m.handle)))
            c,
      ],
    );
  }

  Future<void> _applyMemberEdit(
    List<Map<String, Object?>> Function(List<Map<String, Object?>> current)
    transform,
  ) async {
    final runtime = widget.runtime;
    final conv = widget.conversation;
    if (runtime == null) return;
    final result = await editMirrorMembers(
      gateway: runtime.gateway,
      isTargetRoom: (room) =>
          (conv.groupRoomId != null && room['roomId'] == conv.groupRoomId) ||
          (conv.groupRoomId == null && room['name'] == conv.title),
      transform: transform,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case MirrorEditOk():
        messenger.showSnackBar(
          const SnackBar(content: Text('Miembros actualizados')),
        );
        // Refrescar espejo local + roster (el watch de ready no corre aquí).
        await AppServices.connections.resyncOne(conv.connectionId);
        if (!mounted) return;
        setState(() => _future = _load());
      case MirrorEditConflict():
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Desktop modificó el grupo mientras editabas. '
              'Reabre la ficha y reintenta.',
            ),
          ),
        );
      case MirrorEditUnsupported():
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Este gateway no publica el espejo de grupos'),
          ),
        );
      case MirrorEditError(:final message):
        messenger.showSnackBar(SnackBar(content: Text(message)));
    }
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
    _options = widget.runtime.gateway.modelOptions(widget.profile).then((o) {
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
    setState(
      () => _options = widget.runtime.gateway.modelOptions(
        widget.profile,
        refresh: true,
      ),
    );
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
    if (provider == null ||
        provider.isEmpty ||
        model == null ||
        model.isEmpty) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _saved = null;
    });
    try {
      await widget.runtime.gateway.setProfileModel(
        widget.profile,
        provider: provider,
        model: model,
      );
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Hp.error),
              ),
            ),
          if (_saved != null)
            Padding(
              padding: const EdgeInsets.only(top: Hp.s2),
              child: Text(
                'Modelo aplicado: $_saved',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.primary),
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
              .firstWhere(
                (p) => p.slug == currentProvider,
                orElse: () => configured.first,
              )
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
