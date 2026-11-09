import 'package:flutter/material.dart';
import '../../data/pantry_database.dart';
import '../../models/pantry_item.dart';
import '../../models/purchase_line.dart';
import '../../services/app_settings_service.dart';
import '../../services/expiry_notification_service.dart';
import '../../services/pantry_background_service.dart';
import '../recipe_inbox_screen.dart';
import 'liquid_glass.dart';

class PantryNotificationSettings extends StatefulWidget {
  const PantryNotificationSettings({super.key});
  @override
  State<PantryNotificationSettings> createState() =>
      _PantryNotificationSettingsState();
}

class _PantryNotificationSettingsState
    extends State<PantryNotificationSettings> {
  final _service = PantryBackgroundService.instance;
  final _expiry = ExpiryNotificationService.instance;
  final _appSettings = AppSettingsService.instance;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await _expiry.initialize();
    await _service.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _action(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível salvar. Tente novamente.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _limits() async {
    final items = await PantryDatabase.instance.allItems();
    if (!mounted) return;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cadastre produtos na despensa primeiro.')),
      );
      return;
    }
    final defaultLimit = _appSettings.defaultLowStockThreshold;
    final item = await showDialog<PantryItem>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Escolha um produto'),
        children: [
          for (final item in items)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, item),
              child: Text(
                '${item.name} • limite: ${quantity(_service.thresholds['${item.id}'] ?? defaultLimit)} ${item.unit}',
              ),
            ),
        ],
      ),
    );
    if (item == null || !mounted) return;
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _ThresholdDialog(
        title: 'Limite: ${item.name}',
        label: 'Avisar com esta quantidade (${item.unit})',
        initial: _service.thresholds['${item.id}'] ?? defaultLimit,
      ),
    );
    if (amount != null) await _service.setThreshold(item, amount);
  }

  Future<void> _editGlobalThreshold() async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _ThresholdDialog(
        title: 'Limite padrão de estoque baixo',
        label: 'Avisar quando restar esta quantidade (padrão geral)',
        initial: _appSettings.defaultLowStockThreshold,
      ),
    );
    if (amount != null) {
      await _appSettings.setDefaultLowStockThreshold(amount);
      await _service.checkNow();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Limite padrão atualizado para ${quantity(amount)}.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickReminderHour() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _appSettings.expiryReminderHour, minute: 0),
      helpText: 'Horário diário dos lembretes de validade',
      cancelText: 'Cancelar',
      confirmText: 'Salvar',
    );
    if (picked != null) {
      await _appSettings.setExpiryReminderHour(picked.hour);
      await _expiry.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lembretes agendados para as ${picked.hour.toString().padLeft(2, '0')}:00.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _sendTestNotification() async {
    final ok = await _expiry.sendTestNotification();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Notificação de teste enviada! Confira a central de notificações do aparelho.'
                : (_expiry.error ??
                    'Não foi possível enviar a notificação de teste.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([_service, _expiry, _appSettings]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notificações e Alertas Inteligentes',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (!_service.supported)
            const LiquidGlassCard(
              padding: EdgeInsets.all(16),
              child: Text(
                'As notificações em segundo plano estão disponíveis no aplicativo instalado para Android, iOS, macOS e Windows.',
              ),
            )
          else
            LiquidGlassCard(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(Icons.notifications_active_outlined,
                        color: scheme.primary),
                    title: const Text(
                      'Monitoramento de estoque e receitas',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'Receba avisos de produtos acabando ou faltando e sugestões periódicas de receitas.',
                    ),
                    value: _service.enabled,
                    onChanged: _saving
                        ? null
                        : (value) => _action(() => _service.setEnabled(value)),
                  ),
                  if (_service.enabled) ...[
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.inventory_2_outlined),
                      title: const Text('Alerta de estoque baixo ou zerado'),
                      subtitle: Text(
                        'Padrão atual: avisa com ${quantity(_appSettings.defaultLowStockThreshold)} unidade(s) ou menos.',
                      ),
                      value: _service.stockEnabled,
                      onChanged: _saving
                          ? null
                          : (value) =>
                              _action(() => _service.setCategory(stock: value)),
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.auto_awesome_outlined),
                      title: const Text('Sugestões de receitas pela internet'),
                      subtitle: const Text(
                        'Até uma notificação por dia com receitas reais. Prioriza estoque baixo e validade próxima.',
                      ),
                      value: _service.recipesEnabled,
                      onChanged: _saving
                          ? null
                          : (value) => _action(
                              () => _service.setCategory(recipes: value)),
                    ),
                  ],
                  const Divider(height: 1, indent: 56),
                  SwitchListTile(
                    secondary:
                        Icon(Icons.event_available_outlined, color: scheme.primary),
                    title: const Text(
                      'Lembretes agendados de validade',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_expiry.scheduledCount} avisos agendados • Diariamente às ${_appSettings.expiryReminderHour.toString().padLeft(2, '0')}:00.',
                    ),
                    value: _expiry.enabled,
                    onChanged: _saving
                        ? null
                        : (value) => _action(() => _expiry.setEnabled(value)),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.access_time_rounded),
                    title: const Text('Horário dos lembretes de validade'),
                    subtitle: Text(
                      'Receber avisos às ${_appSettings.expiryReminderHour.toString().padLeft(2, '0')}:00',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _saving ? null : _pickReminderHour,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.scale_outlined),
                    title: const Text('Limite global de estoque baixo'),
                    subtitle: Text(
                      'Avisar quando restarem ${quantity(_appSettings.defaultLowStockThreshold)} ou menos (quando não houver limite individual).',
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 20),
                    onTap: _saving ? null : _editGlobalThreshold,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Limite de estoque por produto'),
                    subtitle: Text(
                      _service.thresholds.isEmpty
                          ? 'Ex.: avisar quando restarem 0,5 kg de arroz. Nenhum limite individual configurado.'
                          : '${_service.thresholds.length} produto(s) com limite personalizado.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _saving ? null : () => _action(_limits),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.restaurant_menu),
                    title: const Text('Últimas receitas sugeridas'),
                    subtitle: const Text(
                        'Veja a caixa de entrada de sugestões geradas em 2º plano.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const RecipeInboxScreen(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _service.hasBackgroundWorker
                              ? 'O sistema verifica periodicamente a cada 6 horas. Receitas precisam de internet; os alertas de estoque e validade funcionam offline.'
                              : 'No Windows, as consultas de receitas acontecem com o app aberto e os lembretes ficam agendados no sistema.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        if (_service.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _service.error!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                        if (_expiry.error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _expiry.error!,
                            style: TextStyle(color: scheme.error),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: !_service.enabled ||
                                      _service.busy ||
                                      _saving
                                  ? null
                                  : () => _action(
                                        () => _service.checkNow(
                                            forceRecipes: true),
                                      ),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: Text(
                                _service.busy
                                    ? 'Consultando...'
                                    : 'Verificar agora',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _sendTestNotification,
                              icon: const Icon(
                                  Icons.notifications_none_rounded,
                                  size: 18),
                              label: const Text('Testar notificação'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThresholdDialog extends StatefulWidget {
  final String title;
  final String label;
  final double initial;
  const _ThresholdDialog({
    required this.title,
    required this.label,
    required this.initial,
  });
  @override
  State<_ThresholdDialog> createState() => _ThresholdDialogState();
}

class _ThresholdDialogState extends State<_ThresholdDialog> {
  final _form = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: '${widget.initial}');
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: widget.label),
            validator: (s) {
              final n =
                  double.tryParse((s ?? '').trim().replaceAll(',', '.'));
              return n == null || !n.isFinite || n < 0
                  ? 'Informe um número maior ou igual a zero'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(
                  context,
                  double.parse(_controller.text.trim().replaceAll(',', '.')),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      );
}
