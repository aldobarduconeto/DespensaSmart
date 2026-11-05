import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../sync/lan_sync.dart';
import '../../sync/sync_journal.dart';
import 'liquid_glass.dart';

class LanSyncSettings extends StatefulWidget {
  const LanSyncSettings({super.key});
  @override
  State<LanSyncSettings> createState() => _LanSyncSettingsState();
}

class _LanSyncSettingsState extends State<LanSyncSettings> {
  final _sync = LanSync.instance;
  final _code = TextEditingController();
  final _peer = TextEditingController();
  bool _ready = false;
  bool _saving = false;
  bool _enabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _sync.initialize();
      if (!mounted) return;
      setState(() {
        _code.text = _sync.code;
        _peer.text = _sync.manualPeer;
        _enabled = _sync.enabled;
        _ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = true;
          _error = 'Não foi possível carregar o compartilhamento.';
        });
      }
    }
  }

  Future<void> _save({bool? forceEnabled}) async {
    final targetEnabled = forceEnabled ?? _enabled;
    setState(() {
      _enabled = targetEnabled;
      _saving = true;
      _error = null;
    });
    try {
      await _sync.configure(
          enabled: targetEnabled, code: _code.text, peer: _peer.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetEnabled
                  ? 'Compartilhamento na rede local salvo e ativado.'
                  : 'Compartilhamento na rede local desativado.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copiado para a área de transferência.')),
      );
    }
  }

  void _generateNewCode() {
    setState(() {
      _code.text = randomSyncId();
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _peer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _sync,
      builder: (context, _) => LiquidGlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering_rounded, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compartilhar com a casa (Rede Local)',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                LiquidGlassPill(
                  label: _sync.enabled ? 'Ativo' : 'Inativo',
                  color: _sync.enabled ? scheme.primary : scheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_sync.supported)
              Text(_sync.status)
            else if (!_ready)
              const LinearProgressIndicator()
            else ...[
              Text(
                'Use o mesmo código em todos os aparelhos conectados ao mesmo Wi-Fi. Despensa e compras serão atualizadas com os aplicativos abertos, sem precisar de internet.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Sincronização na rede local',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(_sync.status),
                value: _enabled,
                onChanged: _saving ? null : (v) => _save(forceEnabled: v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _code,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: 'Código da casa',
                  helperText:
                      'Copie este código para os outros aparelhos (mínimo 16 caracteres).',
                  helperMaxLines: 2,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Copiar código',
                        onPressed: () =>
                            _copyText(_code.text.trim(), 'Código da casa'),
                        icon: const Icon(Icons.copy_rounded, size: 20),
                      ),
                      IconButton(
                        tooltip: 'Gerar novo código seguro',
                        onPressed: _saving ? null : _generateNewCode,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _peer,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Endereço de outro aparelho (opcional)',
                  hintText: '192.168.1.10:45874',
                  helperText:
                      'Use se a descoberta automática UDP não encontrar o aparelho.',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.devices_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(),
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: Text(
                        _saving ? 'Salvando...' : 'Salvar compartilhamento'),
                  ),
                  OutlinedButton.icon(
                    onPressed: !_sync.enabled || _sync.busy || _saving
                        ? null
                        : _sync.syncNow,
                    icon: _sync.busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: Text(
                        _sync.busy ? 'Sincronizando...' : 'Sincronizar agora'),
                  ),
                ],
              ),
              if (_sync.lastSync != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Última sincronização: ${TimeOfDay.fromDateTime(_sync.lastSync!).format(context)}',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
              if (_sync.addresses.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Endereços deste aparelho na rede (toque para copiar):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _sync.addresses
                      .map(
                        (address) => LiquidGlassPill(
                          icon: Icons.copy_rounded,
                          label: address,
                          color: scheme.primary,
                          onTap: () => _copyText(address, 'Endereço $address'),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'No Windows, permita o aplicativo em redes privadas quando o firewall solicitar. Compartilhe o código apenas com as pessoas da casa.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
