import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_services.dart';
import '../../data/database/app_database.dart';
import '../../design/tokens.dart';
import '../app_shell.dart' show BotAvatar;
import 'bot_editor_sheet.dart';
import '../../clients/hermes/bot_meta.dart';
import '../chat/chat_screen.dart';
import '../connections/connection_editor.dart';

/// Lista unificada de conversaciones: bots y grupos de todos los gateways,
/// desde la tabla Conversations (drift) — nada simulado.
///
/// - Búsqueda por nombre/último mensaje.
/// - Chip del gateway cuando hay más de una conexión.
/// - FAB + para crear una conversación eligiendo bot/conexión disponible.
/// - Empty state con acceso directo a ConnectionEditor.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _search = TextEditingController();
  Timer? _tick;
  int _connectionCount = 0;
  String? _openId; // two-pane: conversación abierta en el panel derecho

  @override
  void initState() {
    super.initState();
    // Refresco de horas relativas cada minuto.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // Chip de gateway solo cuando hay más de una conexión.
    AppServices.db.select(AppServices.db.connections).get().then((rows) {
      if (!mounted) return;
      setState(() => _connectionCount = rows.length);
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppServices.db;
    final query = db.select(db.conversations)
      ..where((c) => c.kind.equals('group-hidden').not())
      ..orderBy([
        (c) => OrderingTerm.desc(c.lastActivity),
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.title),
      ]);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            tooltip: 'Añadir conexión',
            icon: const Icon(Icons.add_rounded),
            onPressed: _openConnectionEditor,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'newChatFab',
        tooltip: 'Nueva conversación',
        onPressed: _newConversation,
        child: const Icon(Icons.add_comment_outlined),
      ),
      body: _twoPane(context, Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Hp.s4, Hp.s2, Hp.s4, Hp.s2),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar chats',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Conversation>>(
              stream: query.watch(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data ?? const <Conversation>[];
                final filtered = _filter(rows);
                if (rows.isEmpty) return _emptyState(context);
                if (filtered.isEmpty) return _noResults(context);
                return FutureBuilder<List<Connection>>(
                  future: _connections(),
                  builder: (context, cs) {
                    final sections = _sections(
                      filtered,
                      cs.data ?? const <Connection>[],
                    );
                    return ListView.builder(
                      itemCount: sections.length,
                      itemBuilder: (context, index) => switch (sections[index]) {
                        _Header(:final label, :final reorderable) =>
                          _sectionHeader(context, label, reorderable),
                        _Row(:final conv) => _tile(context, conv),
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }

  Future<List<Connection>> _connections() =>
      AppServices.db.select(AppServices.db.connections).get();

  /// Orden de la lista unificada:
  /// 1) grupos (encabezado "Grupos"), 2) fijados globales ("Fijados"),
  /// 3) una sección por gateway en el orden elegido por el usuario.
  /// Dentro de CADA sección —"Grupos" incluida—: fijados al gateway primero,
  /// luego actividad. Es la regla de Desktop, donde `room.pinned` forma la
  /// banda exterior del orden de salas ANTES del `rosterOrder`
  /// (`group-order.ts:19-24`) y el pin es puramente local, fuera del espejo
  /// (`group-pin.ts:4-8`, `types.ts:222-225`).
  /// Al buscar, la agrupación desaparece (resultado plano por actividad).
  List<_Line> _sections(List<Conversation> rows, List<Connection> conns) {
    if (_search.text.trim().isNotEmpty) {
      return rows.map((c) => _Line.row(c)).toList(growable: false);
    }
    int cmp(Conversation a, Conversation b) {
      final byPinned = (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0);
      if (byPinned != 0) return byPinned;
      final byActivity = (b.lastActivity ?? DateTime(0)).compareTo(
        a.lastActivity ?? DateTime(0),
      );
      if (byActivity != 0) return byActivity;
      return a.title.compareTo(b.title);
    }

    final sorted = [...rows]..sort(cmp);
    // Orden dentro de una sección: pin de gateway como banda exterior y luego
    // actividad (`group-order.ts:19-24`).
    int withinSection(Conversation a, Conversation b) {
      final gp = (b.pinnedGateway ? 1 : 0) - (a.pinnedGateway ? 1 : 0);
      if (gp != 0) return gp;
      return cmp(a, b);
    }

    final groups = sorted.where((c) => c.isGroup).toList(growable: false);
    final pinnedGlobal = sorted
        .where((c) => !c.isGroup && c.pinned)
        .toList(growable: false);
    final rest = sorted
        .where((c) => !c.isGroup && !c.pinned)
        .toList(growable: false);
    final byConn = <String, List<Conversation>>{};
    for (final c in rest) {
      byConn.putIfAbsent(c.connectionId, () => []).add(c);
    }
    for (final l in byConn.values) {
      l.sort(withinSection);
    }
    // Las salas también se agrupan por gateway: la identidad de un grupo es
    // su roomId del espejo y es el MISMO token en todos los clientes
    // (`group-chat.ts:216-223`), así que un grupo multi-gateway se materializa
    // una fila por gateway (`group_sync.dart`) y debe poder vivir en la
    // sección de cada uno.
    final groupsByConn = <String, List<Conversation>>{};
    for (final c in groups) {
      groupsByConn.putIfAbsent(c.connectionId, () => []).add(c);
    }
    for (final l in groupsByConn.values) {
      l.sort(withinSection);
    }
    // Secciones en el orden guardado de conexiones; conexiones inexistentes
    // (p. ej. borradas) al final.
    final connOrder = [...conns]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final out = <_Line>[];
    if (groups.isNotEmpty) {
      out.add(const _Line.header('Grupos', false));
      // Subsecciones por gateway (mismo orden de secciones que los bots), para
      // que un grupo multi-gateway aparezca junto a sus miembros.
      for (final conn in connOrder) {
        final list = groupsByConn.remove(conn.id);
        if (list == null || list.isEmpty) continue;
        if (conns.length > 1) {
          out.add(_Line.header(conn.name, false));
        }
        out.addAll(list.map((c) => _Line.row(c)));
      }
      for (final entry in groupsByConn.entries) {
        if (entry.value.isEmpty) continue;
        if (conns.length > 1) {
          out.add(_Line.header(entry.value.first.gatewayLabel ?? 'Otro gateway', false));
        }
        out.addAll(entry.value.map((c) => _Line.row(c)));
      }
    }
    if (pinnedGlobal.isNotEmpty) {
      out.add(const _Line.header('Fijados', false));
      out.addAll(pinnedGlobal.map((c) => _Line.row(c)));
    }
    for (final conn in connOrder) {
      final list = byConn.remove(conn.id);
      if (list == null || list.isEmpty) continue;
      out.add(_Line.header(conn.name, conns.length > 1));
      out.addAll(list.map((c) => _Line.row(c)));
    }
    for (final entry in byConn.entries) {
      if (entry.value.isEmpty) continue;
      final label = entry.value.first.gatewayLabel ?? 'Otro gateway';
      out.add(_Line.header(label, conns.length > 1));
      out.addAll(entry.value.map((c) => _Line.row(c)));
    }
    return out;
  }

  Widget _sectionHeader(BuildContext context, String label, bool reorderable) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -2),
      contentPadding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      leading: Icon(Icons.folder_outlined, size: 18, color: cs.onSurfaceVariant),
      title: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: reorderable
          ? IconButton(
              tooltip: 'Subir / mover gateway',
              icon: const Icon(Icons.swap_vert_rounded, size: 20),
              onPressed: () => _reorderGateway(label),
            )
          : null,
    );
  }

  /// Mueve la sección de gateway [label] un puesto hacia arriba.
  Future<void> _reorderGateway(String label) async {
    final db = AppServices.db;
    final conns = (await db.select(db.connections).get())
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final idx = conns.indexWhere((c) => c.name == label);
    if (idx <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ese gateway ya está primero')),
        );
      }
      return;
    }
    final ids = conns.map((c) => c.id).toList();
    ids[idx - 1] = conns[idx].id;
    ids[idx] = conns[idx - 1].id;
    await db.setConnectionOrders(ids);
  }

  /// Fold 6 desplegado / tablet: lista a la izquierda, chat a la derecha.
  Widget _twoPane(BuildContext context, Widget list) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    if (!wide || _openId == null) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 360, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(_openId),
            child: ChatScreen(conversationId: _openId!),
          ),
        ),
      ],
    );
  }

  List<Conversation> _filter(List<Conversation> rows) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where(
          (c) =>
              c.title.toLowerCase().contains(q) ||
              (c.preview ?? '').toLowerCase().contains(q),
        )
        .toList(growable: false);
  }

  /// Quita una conversación de ESTA app (fila, mensajes y borrador).
  ///
  /// No escribe nada en el gateway. Para un bot es inocuo: el re-sync la
  /// volverá a descubrir desde `profiles.list`. Para un GRUPO del espejo de
  /// Desktop no — la sala sigue viva en `ui_meta['hermes-bots-groups']` y
  /// reaparecería en el siguiente ciclo, así que la fila queda como marcador
  /// oculto (`kind='group-hidden'`): es la forma local del tombstone de
  /// Desktop (`group-chat.ts:99-104`), que el sync respeta mientras la sala
  /// siga viva. El pin de Desktop tampoco es una orden de borrado remoto
  /// (`group-pin.ts:4-8`).
  Future<void> _confirmDelete(BuildContext context, Conversation c) async {
    final database = AppServices.db;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${c.isGroup ? 'Ocultar' : 'Eliminar'} "${c.title}"'),
        content: Text(
          c.isGroup
              ? 'Se oculta de esta app (chat y borrador). El grupo del gateway '
                    'y su historial NO se tocan: lo crea y lo disuelve '
                    'Hermes Desktop.'
              : 'Se elimina de esta app (chat y borrador). '
                    'El bot y su historial en el gateway no se tocan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(c.isGroup ? 'Ocultar' : 'Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await database.batch((b) {
      b.deleteWhere<$MessagesTable, Message>(
        database.messages,
        (m) => m.conversationId.equals(c.id),
      );
      b.deleteWhere<$DraftsTable, Draft>(
        database.drafts,
        (d) => d.conversationId.equals(c.id),
      );
    });
    if (c.isGroup) {
      // Marcador oculto: conserva la identidad durable (roomId) y la revisión
      // sincronizada para que el sync no la re-materialice ni la re-titre.
      await (database.update(database.conversations)
            ..where((x) => x.id.equals(c.id)))
          .write(
        const ConversationsCompanion(kind: Value('group-hidden')),
      );
      return;
    }
    await (database.delete(database.conversations)
          ..where((x) => x.id.equals(c.id)))
        .go();
  }

  Widget _tile(BuildContext context, Conversation c) {
    final cs = Theme.of(context).colorScheme;
    final showGateway = _connectionCount > 1 && c.gatewayLabel != null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      leading: BotAvatar(
        seed: c.avatarSeed ?? c.id,
        label: c.title,
        size: 46,
        isGroup: c.isGroup,
        imageUrl: c.avatarUrl,
        avatarMetaJson: c.botAvatarMeta,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              c.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            relativeTime(c.lastActivity),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c.unreadCount > 0 ? cs.primary : cs.onSurfaceVariant,
              fontWeight: c.unreadCount > 0 ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              c.preview ?? c.subtitle ?? 'Sin mensajes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (showGateway)
            Container(
              margin: const EdgeInsets.only(left: Hp.s2),
              padding: const EdgeInsets.symmetric(
                horizontal: Hp.s2,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(Hp.rSm),
              ),
              child: Text(
                c.gatewayLabel!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10.5,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (c.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: Hp.s2),
              padding: const EdgeInsets.symmetric(
                horizontal: 6.5,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 19),
              child: Text(
                c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        if (MediaQuery.sizeOf(context).width >= 840) {
          setState(() => _openId = c.id);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(conversationId: c.id),
            ),
          );
        }
      },
      onLongPress: () => _rowActions(context, c),
    );
  }
  /// Acciones de fila: editar bot (perfil) o eliminar conversación local.
  /// Editar solo para kind='bot': requiere el name del perfil + conexión.
  Future<void> _rowActions(BuildContext context, Conversation c) async {
    // El menú lee SIEMPRE la fila viva de la BD (no el objeto que el tile
    // tenía en memoria: el upsert de sync puede entregar copias viejas).
    final live = await (AppServices.db.select(AppServices.db.conversations)
          ..where((x) => x.id.equals(c.id)))
        .getSingle();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                live.pinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                live.pinned ? 'Quitar de Fijados' : 'Fijar arriba de todo',
              ),
              onTap: () => Navigator.of(context).pop('pin'),
            ),
            // El pin de gateway siempre disponible: fijar un bot ARRIBA DE
            // TODO y fijarlo en su gateway no son mutuamente excluyentes
            // (la sección 'Fijados' no lo oculta; en su gateway también
            // queda destacado). El gate !pinned era un error de diseño.
            ListTile(
              leading: Icon(
                live.pinnedGateway
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                live.pinnedGateway
                    ? 'Quitar de "${live.gatewayLabel ?? 'su gateway'}"'
                    : 'Fijar en "${live.gatewayLabel ?? 'su gateway'}"',
              ),
              onTap: () => Navigator.of(context).pop('pinGateway'),
            ),
            if (live.kind == 'bot')
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Editar bot'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Eliminar'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        await AppServices.db.setPinned(
          c.id,
          pinned: !live.pinned,
          pinnedGateway: live.pinnedGateway,
        );
      case 'pinGateway':
        await AppServices.db.setPinned(
          c.id,
          pinned: live.pinned,
          pinnedGateway: !live.pinnedGateway,
        );
      case 'edit':
        await BotEditorSheet.show(
          context,
          connectionId: c.connectionId,
          profileName: c.gatewayId,
          currentTitle: c.title,
          currentDescription: c.subtitle,
          currentAvatar: _avatarMetaOf(c),
        );
      case 'delete':
        await _confirmDelete(context, c);
    }
  }

  BotAvatarMeta? _avatarMetaOf(Conversation c) {
    final j = c.botAvatarMeta;
    if (j == null || j.isEmpty) return null;
    try {
      return BotAvatarMeta.fromJson(
        const JsonDecoder().convert(j) as Map,
      );
    } catch (_) {
      return null;
    }
  }


  Widget _emptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(Hp.s8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, size: 56, color: cs.onSurfaceVariant),
              const SizedBox(height: Hp.s5),
              Text(
                'Sin conversaciones todavía',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Hp.s2),
              Text(
                'Conecta un gateway Hermes para descubrir\n tus bots y grupos.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Hp.s5),
              FilledButton.icon(
                onPressed: _openConnectionEditor,
                icon: const Icon(Icons.add_link_rounded, size: 18),
                label: const Text('Conectar un gateway'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _noResults(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 44, color: cs.onSurfaceVariant),
          const SizedBox(height: Hp.s3),
          Text(
            'Sin resultados para "${_search.text}"',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }


  Future<void> _openConnectionEditor() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ConnectionEditor()),
    );
    if (!mounted) return;
    final rows = await AppServices.db.select(AppServices.db.connections).get();
    setState(() => _connectionCount = rows.length);
  }

  /// Crea una conversación nueva eligiendo bot/conexión disponible.
  ///
  /// Si el bot ya existe en la DB reabre esa fila; si no, crea la fila del
  /// bot canónico (sesión con título exacto Bot Chat, según hermes-map §4).
  Future<void> _newConversation() async {
    final db = AppServices.db;
    final connections = await (db.select(db.connections)
          ..where((c) => c.enabled.equals(true)))
        .get();
    if (!mounted) return;

    if (connections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Añade primero una conexión en Ajustes.'),
        ),
      );
      await _openConnectionEditor();
      return;
    }

    // Bots ya conocidos de esos gateways.
    final connIds = connections.map((c) => c.id).toSet();
    final known = await (db.select(db.conversations)
          ..where((c) => c.kind.equals('bot')))
        .get();
    final byConnection = {
      for (final id in connIds) id: known.where((c) => c.connectionId == id),
    };

    if (!mounted) return;
    final picked = await showModalBottomSheet<_NewChatPick>(
      context: context,
      builder: (context) => _NewChatSheet(
        connections: connections,
        knownByConnection: byConnection,
      ),
    );
    if (picked == null || !mounted) return;

    if (picked.existingId != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(conversationId: picked.existingId!),
        ),
      );
      return;
    }

    // Alta canónica de bot: sesión "Bot Chat" del perfil elegido.
    final conv = ConversationsCompanion.insert(
      id: '${picked.connectionId}/bot/${picked.gatewayId}',
      connectionId: picked.connectionId,
      kind: 'bot',
      gatewayId: picked.gatewayId,
      title: picked.title,
      avatarSeed: Value(picked.gatewayId),
      isGroup: const Value(false),
      gatewayLabel: Value(picked.gatewayLabel),
      lastActivity: Value(DateTime.now()),
    );
    try {
      await db.into(db.conversations).insertOnConflictUpdate(conv);
    } catch (e) {
      // Colisión benigna: ya existía, abrir directamente.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          conversationId: '${picked.connectionId}/bot/${picked.gatewayId}',
        ),
      ),
    );
  }
}

/// Selección del sheet de nueva conversación.
class _NewChatPick {
  final String? existingId;
  final String connectionId;
  final String gatewayId;
  final String title;
  final String gatewayLabel;

  const _NewChatPick({
    this.existingId,
    required this.connectionId,
    required this.gatewayId,
    required this.title,
    required this.gatewayLabel,
  });
}

class _NewChatSheet extends StatelessWidget {
  final List<Connection> connections;
  final Map<String, Iterable<Conversation>> knownByConnection;

  const _NewChatSheet({
    required this.connections,
    required this.knownByConnection,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: Hp.s4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Hp.s5, Hp.s1, Hp.s5, Hp.s2),
            child: Text(
              'Nueva conversación',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final conn in connections) ...[
            if (connections.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(Hp.s5, Hp.s2, Hp.s5, Hp.s1),
                child: Text(
                  conn.name,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ...knownByConnection[conn.id]!.map(
              (c) => ListTile(
                leading: BotAvatar(
                  seed: c.avatarSeed ?? c.id,
                  label: c.title,
                  size: 38,
                  isGroup: c.isGroup,
                  imageUrl: c.avatarUrl,
                  avatarMetaJson: c.botAvatarMeta,
                ),
                title: Text(c.title),
                subtitle: c.subtitle == null
                    ? null
                    : Text(c.subtitle!, maxLines: 1),
                onTap: () => Navigator.of(context).pop(
                  _NewChatPick(
                    existingId: c.id,
                    connectionId: c.connectionId,
                    gatewayId: c.gatewayId,
                    title: c.title,
                    gatewayLabel: c.gatewayLabel ?? conn.name,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: CircleAvatar(
                radius: 19,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(
                  Icons.add_comment_outlined,
                  size: 18,
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
              title: Text('Bot canónico del gateway ${conn.name}'),
              subtitle: const Text('Sesión Bot Chat del perfil por defecto'),
              onTap: () => Navigator.of(context).pop(
                _NewChatPick(
                  connectionId: conn.id,
                  gatewayId: conn.name,
                  title: conn.name,
                  gatewayLabel: conn.name,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Hora relativa compartida: 5m · 2h · Ayer · 12/03.
String relativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final ref = now ?? DateTime.now();
  final diff = ref.difference(time);
  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  final today = DateTime(ref.year, ref.month, ref.day);
  final day = DateTime(time.year, time.month, time.day);
  if (today.difference(day) == const Duration(days: 1)) return 'Ayer';
  if (time.year == ref.year) return DateFormat('dd/MM').format(time);
  return DateFormat('dd/MM/yy').format(time);
}

/// Línea de la lista: encabezado de sección o fila de conversación.
sealed class _Line {
  const _Line();
  const factory _Line.row(Conversation conv) = _Row;
  const factory _Line.header(String label, bool reorderable) = _Header;
}

final class _Row extends _Line {
  final Conversation conv;
  const _Row(this.conv);
}

final class _Header extends _Line {
  final String label;
  final bool reorderable;
  const _Header(this.label, this.reorderable);
}
