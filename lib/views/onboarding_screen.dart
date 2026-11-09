import 'package:flutter/material.dart';
import '../services/expiry_notification_service.dart';
import '../services/pantry_background_service.dart';
import '../services/theme_service.dart';
import '../sync/lan_sync.dart';
import 'widgets/liquid_glass.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  final bool isRevisit;

  const OnboardingScreen({
    super.key,
    required this.onFinish,
    this.isRevisit = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  final _expiryService = ExpiryNotificationService.instance;
  final _bgService = PantryBackgroundService.instance;
  final _lanSync = LanSync.instance;

  int _currentPage = 0;
  bool _requestingPermissions = false;
  String? _permissionFeedback;

  static const _totalPages = 4;

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    await _expiryService.initialize();
    await _bgService.initialize();
    await _lanSync.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _toggleNotificationsAndBackground(bool enable) async {
    setState(() {
      _requestingPermissions = true;
      _permissionFeedback = null;
    });
    try {
      await _expiryService.setEnabled(enable);
      await _bgService.setEnabled(enable);
      if (mounted) {
        if (enable && (!_expiryService.enabled || !_bgService.enabled)) {
          _permissionFeedback = _expiryService.error ??
              _bgService.error ??
              'Permissão de notificações não concedida pelo sistema.';
        } else if (enable) {
          _permissionFeedback =
              'Notificações de validade, estoque e receitas ativadas com sucesso!';
        }
      }
    } catch (_) {
      if (mounted) {
        _permissionFeedback =
            'Não foi possível solicitar a permissão agora. Você pode alterar nas Configurações.';
      }
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _toggleLanSync(bool enable) async {
    setState(() {
      _requestingPermissions = true;
      _permissionFeedback = null;
    });
    try {
      await _lanSync.initialize();
      await _lanSync.configure(
        enabled: enable,
        code: _lanSync.code,
        peer: _lanSync.manualPeer,
      );
      if (mounted && enable) {
        _permissionFeedback =
            'Sincronização local ativa! Código da casa pronto para compartilhar.';
      }
    } catch (e) {
      if (mounted) {
        _permissionFeedback = 'Aviso na rede local: $e';
      }
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _enableAllRecommended() async {
    setState(() {
      _requestingPermissions = true;
      _permissionFeedback = null;
    });
    try {
      await _expiryService.setEnabled(true);
      await _bgService.setEnabled(true);
      await _lanSync.initialize();
      await _lanSync.configure(
        enabled: true,
        code: _lanSync.code,
        peer: _lanSync.manualPeer,
      );
      if (mounted) {
        final notifOk = _expiryService.enabled && _bgService.enabled;
        _permissionFeedback = notifOk
            ? 'Tudo pronto! Todas as permissões e recursos inteligentes foram ativados.'
            : (_expiryService.error ??
                'Rede local ativa. Verifique a permissão de notificações nas configurações do sistema.');
      }
    } catch (_) {
      if (mounted) {
        _permissionFeedback =
            'Algumas permissões precisam ser revisadas nas configurações.';
      }
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _complete() async {
    await ThemeService.completeOnboarding();
    widget.onFinish();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = _currentPage == _totalPages - 1;

    return Scaffold(
      body: LiquidGlassBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 36,
                            height: 36,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Despensa Smart',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        if (!isLast)
                          TextButton(
                            onPressed: () => _pageController.animateToPage(
                              _totalPages - 1,
                              duration: const Duration(milliseconds: 420),
                              curve: Curves.easeOutCubic,
                            ),
                            child: const Text('Ir para permissões'),
                          )
                        else if (widget.isRevisit)
                          IconButton(
                            tooltip: 'Fechar',
                            onPressed: _complete,
                            icon: const Icon(Icons.close),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      onPageChanged: (index) =>
                          setState(() => _currentPage = index),
                      children: [
                        _buildFeaturePage(
                          badge: 'CONTROLE INTELIGENTE',
                          icon: Icons.kitchen_rounded,
                          accent: scheme.primary,
                          title: 'Sua despensa sempre organizada e sem desperdício',
                          subtitle:
                              'Acompanhe quantidades, categorias e datas de validade com visual Liquid Glass pensado para rapidez no dia a dia.',
                          highlights: const [
                            (
                              icon: Icons.event_available_rounded,
                              title: 'Alertas visuais de validade',
                              desc:
                                  'Identifique na hora itens que vencem nos próximos 7 dias ou que precisam de reposição.'
                            ),
                            (
                              icon: Icons.filter_alt_outlined,
                              title: 'Busca e filtros instantâneos',
                              desc:
                                  'Filtre por categoria, status de estoque ou validade com um toque.'
                            ),
                            (
                              icon: Icons.offline_bolt_outlined,
                              title: '100% disponível offline',
                              desc:
                                  'Seus ingredientes ficam salvos no aparelho, sem depender de nuvem ou cadastro.'
                            ),
                          ],
                        ),
                        _buildFeaturePage(
                          badge: 'RECEITAS SOB MEDIDA',
                          icon: Icons.auto_awesome_rounded,
                          accent: scheme.secondary,
                          title: 'Descubra o que cozinhar com o que você já tem',
                          subtitle:
                              'Receba recomendações reais de receitas que combinam seus ingredientes em estoque e priorizam o que está perto de vencer.',
                          highlights: const [
                            (
                              icon: Icons.priority_high_rounded,
                              title: 'Prioridade anti-desperdício',
                              desc:
                                  'Ingredientes com validade próxima ganham destaque automático na busca de receitas.'
                            ),
                            (
                              icon: Icons.checklist_rounded,
                              title: 'Índice de aproveitamento',
                              desc:
                                  'Veja quantos ingredientes da receita você já possui na despensa antes de começar.'
                            ),
                            (
                              icon: Icons.menu_book_rounded,
                              title: 'Modo de preparo completo',
                              desc:
                                  'Instruções detalhadas e lista de medidas integradas ao TheMealDB.'
                            ),
                          ],
                        ),
                        _buildFeaturePage(
                          badge: 'COMPRAS E CASA CONECTADA',
                          icon: Icons.shopping_cart_checkout_rounded,
                          accent: scheme.tertiary,
                          title: 'Das compras ao relatório mensal em toda a casa',
                          subtitle:
                              'Quando um ingrediente acaba, ele entra automaticamente na lista de compras. Sincronize tudo pelo Wi-Fi com sua família.',
                          highlights: const [
                            (
                              icon: Icons.receipt_long_rounded,
                              title: 'Carrinho com preços e descontos',
                              desc:
                                  'Simule o total da compra no mercado e atualize o estoque ao finalizar.'
                            ),
                            (
                              icon: Icons.insights_rounded,
                              title: 'Resumo mensal inteligente',
                              desc:
                                  'Compare gastos, descontos obtidos e os produtos mais consumidos a cada mês.'
                            ),
                            (
                              icon: Icons.wifi_tethering_rounded,
                              title: 'Sincronização segura na rede local',
                              desc:
                                  'Compartilhe a despensa entre celulares e computador no mesmo Wi-Fi usando o código da casa.'
                            ),
                          ],
                        ),
                        _buildPermissionsPage(context),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      borderRadius: 28,
                      child: Row(
                        children: [
                          Row(
                            children: List.generate(_totalPages, (index) {
                              final active = index == _currentPage;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                margin: const EdgeInsets.only(right: 6),
                                width: active ? 26 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: active
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              );
                            }),
                          ),
                          const Spacer(),
                          if (_currentPage > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: TextButton(
                                onPressed: () => _pageController.previousPage(
                                  duration: const Duration(milliseconds: 320),
                                  curve: Curves.easeOutCubic,
                                ),
                                child: const Text('Voltar'),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: _requestingPermissions ? null : _nextPage,
                            icon: Icon(
                              isLast
                                  ? Icons.rocket_launch_rounded
                                  : Icons.arrow_forward_rounded,
                              size: 18,
                            ),
                            label: Text(
                              isLast ? 'Começar agora' : 'Próximo',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeaturePage({
    required String badge,
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required List<({IconData icon, String title, String desc})> highlights,
  }) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      children: [
        LiquidGlassCard(
          prominent: true,
          padding: const EdgeInsets.all(24),
          borderRadius: 30,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          accent.withValues(alpha: 0.25),
                          accent.withValues(alpha: 0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(icon, size: 32, color: accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: LiquidGlassPill(
                        icon: Icons.verified_outlined,
                        label: badge,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final item in highlights) ...[
          LiquidGlassCard(
            padding: const EdgeInsets.all(18),
            borderRadius: 22,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(item.icon, color: accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.desc,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildPermissionsPage(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([_expiryService, _bgService, _lanSync]),
      builder: (context, _) {
        final notificationsActive =
            _expiryService.enabled && _bgService.enabled;
        final lanActive = _lanSync.enabled;
        final allActive = notificationsActive && lanActive;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          children: [
            LiquidGlassCard(
              prominent: true,
              padding: const EdgeInsets.all(22),
              borderRadius: 28,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LiquidGlassPill(
                    icon: Icons.security_rounded,
                    label: 'PERMISSÕES E PRIVACIDADE',
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ative os avisos e recursos inteligentes',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'O Despensa Smart respeita sua privacidade: seus dados ficam no dispositivo. Autorize as permissões abaixo para receber lembretes de validade, alertas de estoque e sincronizar em casa.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _requestingPermissions || allActive
                          ? null
                          : _enableAllRecommended,
                      icon: _requestingPermissions
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(allActive
                              ? Icons.check_circle_rounded
                              : Icons.verified_user_outlined),
                      label: Text(
                        allActive
                            ? 'Todas as permissões recomendadas estão ativas'
                            : 'Autorizar e ativar tudo (Recomendado)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LiquidGlassCard(
              padding: const EdgeInsets.all(18),
              borderRadius: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.notifications_active_outlined,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notificações e Verificação em 2º Plano',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              notificationsActive
                                  ? 'Permissão concedida • Alertas ativos'
                                  : 'Permite avisar quando um produto vai vencer ou acabar',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: notificationsActive
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: notificationsActive
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: notificationsActive,
                        onChanged: _requestingPermissions
                            ? null
                            : _toggleNotificationsAndBackground,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Inclui permissão de notificações do sistema (POST_NOTIFICATIONS) e agendamento periódico para sugerir receitas antes que os ingredientes vençam.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LiquidGlassCard(
              padding: const EdgeInsets.all(18),
              borderRadius: 22,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: scheme.secondary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.wifi_rounded,
                          color: scheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rede Local (Sincronização Wi-Fi)',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              lanActive
                                  ? 'Ativo na rede local • ${_lanSync.status}'
                                  : 'Opcional • Sincroniza aparelhos da mesma casa',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: lanActive
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                                fontWeight: lanActive
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: lanActive,
                        onChanged:
                            _requestingPermissions ? null : _toggleLanSync,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Solicita acesso à rede local para encontrar outros aparelhos da casa com o mesmo código secreto, sem enviar dados para a internet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            LiquidGlassCard(
              padding: const EdgeInsets.all(16),
              borderRadius: 20,
              child: Row(
                children: [
                  Icon(Icons.cloud_done_outlined,
                      color: scheme.primary, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Acesso à Internet: utilizado exclusivamente para consultar receitas e fotos no TheMealDB.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_permissionFeedback != null) ...[
              const SizedBox(height: 12),
              LiquidGlassCard(
                padding: const EdgeInsets.all(14),
                borderRadius: 18,
                tint: scheme.primaryContainer,
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: scheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _permissionFeedback!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
