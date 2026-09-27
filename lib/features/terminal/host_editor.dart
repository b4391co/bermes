import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_services.dart';
import 'ssh_secrets.dart';
import '../../core/logger.dart';
import '../../data/database/app_database.dart';
import '../../design/tokens.dart';

/// Editor de host SSH a pantalla completa: alta y edición reales.
///
/// - password/passphrase/private key SOLO en SecureStore, nunca en la DB.
/// - Guardar escribe la fila en drift (tabla SshHosts).
class HostEditor extends StatefulWidget {
  /// Fila existente (edición) o null (alta).
  final SshHost? existing;

  /// Valores iniciales para ALTA (p.ej. host derivado de una conexión
  /// Hermes): prellena el formulario sin tocar la lógica de guardado.
  final ({String name, String host, int port, String username})? preset;

  const HostEditor({super.key, this.existing, this.preset});

  @override
  State<HostEditor> createState() => _HostEditorState();
}

class _HostEditorState extends State<HostEditor> {
  final _log = Logger('HostEditor');
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _passphrase;
  late final TextEditingController _privateKey;
  late String _authKind; // password | key
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final p = widget.preset;
    _name = TextEditingController(text: e?.name ?? p?.name ?? '');
    _host = TextEditingController(text: e?.host ?? p?.host ?? '');
    _port = TextEditingController(
      text: (e?.port ?? p?.port ?? 22).toString(),
    );
    _username = TextEditingController(text: e?.username ?? p?.username ?? '');
    _authKind = e?.authKind ?? 'password';
    _password = TextEditingController();
    _passphrase = TextEditingController();
    _privateKey = TextEditingController();
    _loadSecrets();
  }

  Future<void> _loadSecrets() async {
    if (!_isEdit) return;
    final pw = await sshSecrets.readPassword(widget.existing!.id);
    final key = await sshSecrets.readPrivateKey(widget.existing!.id);
    final ph = await sshSecrets.readPassphrase(widget.existing!.id);
    if (!mounted) return;
    setState(() {
      _password.text = pw ?? '';
      _privateKey.text = key ?? '';
      _passphrase.text = ph ?? '';
    });
  }

  @override
  void dispose() {
    // Los controllers con secretos se limpian al salir del editor.
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _passphrase.dispose();
    _privateKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final id = widget.existing?.id ?? const Uuid().v4();
      final row = SshHostsCompanion.insert(
        id: id,
        name: _name.text.trim(),
        host: _host.text.trim(),
        port: Value(int.tryParse(_port.text.trim()) ?? 22),
        username: _username.text.trim(),
        authKind: _authKind,
        knownFingerprint: Value(widget.existing?.knownFingerprint),
      );
      final db = AppServices.db;
      await db.into(db.sshHosts).insertOnConflictUpdate(row);

      // Secretos: solo si el usuario escribió algo nuevo; borrar si vacío.
      if (_authKind == 'password') {
        if (_password.text.isNotEmpty) {
          await sshSecrets.writePassword(id, _password.text);
        }
      } else {
        if (_privateKey.text.isNotEmpty) {
          await sshSecrets.writePrivateKey(id, _privateKey.text);
        }
        if (_passphrase.text.isNotEmpty) {
          await sshSecrets.writePassphrase(id, _passphrase.text);
        }
      }
      _log.info('host guardado ${_name.text.trim()}');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _log.error('guardar host falló', e);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar host SSH' : 'Nuevo host SSH'),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(Hp.s4),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                hintText: 'Mi servidor',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Ponle un nombre' : null,
            ),
            const SizedBox(height: Hp.s3),
            TextFormField(
              controller: _host,
              decoration: const InputDecoration(
                labelText: 'Host',
                hintText: '192.168.1.10 o mimaquina.local',
              ),
              keyboardType: TextInputType.url,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Host requerido' : null,
            ),
            const SizedBox(height: Hp.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _port,
                    decoration: const InputDecoration(labelText: 'Puerto'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final p = int.tryParse(v ?? '');
                      if (p == null || p < 1 || p > 65535) {
                        return '1–65535';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: Hp.s3),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      hintText: 'usuario',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Usuario requerido'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Hp.s4),
            const Text('Autenticación'),
            const SizedBox(height: Hp.s1),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'password', label: Text('Contraseña')),
                ButtonSegment(value: 'key', label: Text('Clave privada')),
              ],
              selected: {_authKind},
              onSelectionChanged: (s) => setState(() => _authKind = s.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: Hp.s3),
            if (_authKind == 'password')
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'Contraseña (déjalo vacío para mantener)'
                      : 'Contraseña',
                ),
                obscureText: true,
                validator: _isEdit
                    ? null
                    : (v) => (v == null || v.isEmpty)
                          ? 'Contraseña requerida'
                          : null,
              )
            else ...[
              TextFormField(
                controller: _privateKey,
                decoration: InputDecoration(
                  labelText: _isEdit
                      ? 'Clave privada PEM (vacío = mantener)'
                      : 'Clave privada PEM',
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                ),
                maxLines: 5,
                minLines: 3,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                validator: _isEdit
                    ? null
                    : (v) => (v == null || v.trim().isEmpty)
                          ? 'Clave requerida'
                          : null,
              ),
              const SizedBox(height: Hp.s3),
              TextFormField(
                controller: _passphrase,
                decoration: const InputDecoration(
                  labelText: 'Passphrase (opcional)',
                ),
                obscureText: true,
              ),
            ],
            const SizedBox(height: Hp.s6),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guardar'),
            ),
            const SizedBox(height: Hp.s8),
          ],
        ),
      ),
    );
  }
}
