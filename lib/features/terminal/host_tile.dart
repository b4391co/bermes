import 'package:flutter/material.dart';

import '../../data/database/app_database.dart';
import '../../design/tokens.dart';

/// Fila de la lista de hosts SSH: identidad, estado y acciones.
class HostTile extends StatelessWidget {
  final SshHost host;
  final bool connected;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const HostTile({
    super.key,
    required this.host,
    required this.connected,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onConnect,
      contentPadding: const EdgeInsets.symmetric(horizontal: Hp.s4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Hp.avatarColor(host.name).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Hp.rSm),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.dns_rounded,
          size: 20,
          color: Hp.avatarColor(host.name),
        ),
      ),
      title: Text(
        host.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subtitle: Text(
        '${host.username}@${host.host}:${host.port}'
        '  ·  ${host.authKind == 'key' ? 'clave' : 'contraseña'}'
        '  ·  ${connected ? 'conectado' : 'disponible'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: cs.error),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
