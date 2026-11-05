import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/local_recipe_ai_service.dart';
import '../services/family_mode_service.dart';
import '../sync/lan_sync.dart';
import 'family_consumption_screen.dart';
import 'widgets/liquid_glass.dart';

class LocalAiSettingsScreen extends StatefulWidget {
  const LocalAiSettingsScreen({super.key});

  @override
  State<LocalAiSettingsScreen> createState() => _LocalAiSettingsScreenState();
}

class _LocalAiSettingsScreenState extends State<LocalAiSettingsScreen> {
  final _service = LocalRecipeAiService.instance;
  final _preferencesController = TextEditingController();
  final _familyMemberController = TextEditingController();
  LocalRecipeAiSettings _settings = const LocalRecipeAiSettings();
  List<String> _familyMembers = [];
  bool _familyConfiguredEnabled = false;
  bool _familySaving = false;
  bool _checking = true;
  bool _installed = false;
  bool _busy = false;
  bool _saving = false;
  bool _hasChanges = false;
  int _progress = 0;
  String? _error;

  bool get _supported => !kIsWeb;
  bool get _familyEnabled => FamilyModeService.instance.available;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _preferencesController.dispose();
    _familyMemberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final settings = await _service.loadSettings();
      await LanSync.instance.initialize();
      await FamilyModeService.instance.load();
      final installed = _supported && await _service.isModelInstalled();
      if (mounted) {
        setState(() {
          _settings = settings;
          _preferencesController.text = settings.dietaryPreferences;
          _installed = installed;
          _familyMembers = List.of(FamilyModeService.instance.members);
          _familyConfiguredEnabled =
              FamilyModeService.instance.configuredEnabled;
          _hasChanges = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível carregar as configurações: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _updateSettings(LocalRecipeAiSettings settings) {
    setState(() {
      _settings = settings;
      _hasChanges = true;
    });
  }

  Future<void> _toggleFamilyMode(bool value) async {
    setState(() {
      _familySaving = true;
      _error = null;
    });
    try {
      if (value) {
        await FamilyModeService.instance.saveMembers(_familyMembers);
      }
      await FamilyModeService.instance.setEnabled(value);
      if (mounted) {
        setState(() {
          _familyConfiguredEnabled = value;
          _familyMembers = List.of(FamilyModeService.instance.members);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? 'Modo família ativado. O consumo será sincronizado entre os aparelhos da casa.'
                  : 'Modo família desativado.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _familySaving = false);
    }
  }

  Future<void> _saveFamilyMembers() async {
    setState(() {
      _familySaving = true;
      _error = null;
    });
    try {
      await FamilyModeService.instance.saveMembers(_familyMembers);
      if (mounted) {
        setState(() {
          _familyMembers = List.of(FamilyModeService.instance.members);
          _familyMemberController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pessoas da casa atualizadas.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _familySaving = false);
    }
  }

  void _addFamilyMember() {
    final name = _familyMemberController.text.trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    if (name.isEmpty) return;
    if (_familyMembers.any((person) => person.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'Essa pessoa já está cadastrada.');
      return;
    }
    if (_familyMembers.length >= 30) {
      setState(() => _error = 'Cadastre no máximo 30 pessoas.');
      return;
    }
    if (name.length > 50) {
      setState(() => _error = 'Cada nome pode ter no máximo 50 caracteres.');
      return;
    }
    setState(() {
      _familyMembers = [..._familyMembers, name];
      _error = null;
    });
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final settings = LocalRecipeAiSettings(
      recipeCount: _settings.recipeCount,
      creativity: _settings.creativity,
      dietaryPreferences: _preferencesController.text.trim(),
      prioritizeExpiring: _settings.prioritizeExpiring,
    );
    try {
      await _service.saveSettings(settings);
      if (mounted) {
        setState(() {
          _settings = settings;
          _hasChanges = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferências de IA salvas.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível salvar as preferências: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
    });
    try {
      await _service.downloadModel(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) {
        setState(() => _installed = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gemma 4 E2B baixado e pronto para uso.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível baixar o modelo: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir modelo local?'),
        content: const Text(
          'O Gemma 4 E2B ocupa cerca de 2,6 GB. Será necessário baixá-lo novamente para gerar receitas offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Manter modelo'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir modelo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.deleteModel();
      if (mounted) {
        setState(() => _installed = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Modelo local excluído.')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível excluir o modelo: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final creativity = _settings.creativity < 0.35
        ? 'Objetiva'
        : _settings.creativity < 0.7
        ? 'Equilibrada'
        : 'Criativa';

    return Scaffold(
      appBar: const LiquidGlassAppBar(title: Text('Configurar IA local')),
      body: LiquidGlassBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 760 : 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                LiquidGlassCard(
                  prominent: true,
                  padding: const EdgeInsets.all(22),
                  borderRadius: 28,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 29,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Gemma 4 E2B',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Geração de receitas diretamente no aparelho',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          LiquidGlassPill(
                            icon: _installed
                                ? Icons.check_circle_outline_rounded
                                : Icons.download_outlined,
                            label: _checking
                                ? 'Verificando modelo'
                                : _installed
                                ? 'Modelo instalado'
                                : 'Download de ${LocalRecipeAiService.modelSize}',
                            color: _installed ? scheme.primary : scheme.outline,
                          ),
                          LiquidGlassPill(
                            icon: Icons.phone_android_rounded,
                            label: 'Processamento local',
                            color: scheme.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _supported
                            ? 'Baixe o modelo uma vez (${LocalRecipeAiService.modelSize}) usando uma conexão estável e espaço livre. Depois, as receitas são geradas offline e os itens da despensa não são enviados a um servidor de IA.'
                            : 'A IA local não está disponível na versão Web. Use o aplicativo para Android, iOS, Windows, macOS ou Linux.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      if (_supported && _busy && !_installed) ...[
                        const SizedBox(height: 18),
                        LinearProgressIndicator(value: _progress / 100),
                        const SizedBox(height: 8),
                        Text('Baixando Gemma 4 E2B... $_progress%'),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_supported && !_installed)
                            FilledButton.icon(
                              onPressed: _checking || _busy
                                  ? null
                                  : _downloadModel,
                              icon: const Icon(Icons.download_rounded),
                              label: Text(
                                _busy ? 'Baixando...' : 'Baixar modelo',
                              ),
                            ),
                          if (_installed)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _deleteModel,
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Excluir modelo local'),
                            ),
                          if (!_checking && _error != null)
                            TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Tentar novamente'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Como a IA prepara suas sugestões',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LiquidGlassCard(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.kitchen_outlined),
                        title: Text('Receitas com o estoque disponível'),
                        subtitle: Text(
                          'O modelo considera quantidade, unidade e validade dos itens cadastrados.',
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      const ListTile(
                        leading: Icon(Icons.lock_outline_rounded),
                        title: Text('Privacidade no aparelho'),
                        subtitle: Text(
                          'A inferência usa o Gemma baixado. Somente o download inicial precisa de internet.',
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      const ListTile(
                        leading: Icon(Icons.fact_check_outlined),
                        title: Text('Confira antes de cozinhar'),
                        subtitle: Text(
                          'Conteúdo gerado pode conter imprecisões. Confira ingredientes, quantidades, alergênicos e preparo.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Preferências de geração',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LiquidGlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quantidade de receitas',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<int>(
                        expandedInsets: EdgeInsets.zero,
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                          ButtonSegment(value: 3, label: Text('3')),
                        ],
                        selected: {_settings.recipeCount},
                        onSelectionChanged: (selection) => _updateSettings(
                          LocalRecipeAiSettings(
                            recipeCount: selection.first,
                            creativity: _settings.creativity,
                            dietaryPreferences: _settings.dietaryPreferences,
                            prioritizeExpiring: _settings.prioritizeExpiring,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Estilo das sugestões',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            creativity,
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _settings.creativity,
                        divisions: 4,
                        label: creativity,
                        onChanged: (value) => _updateSettings(
                          LocalRecipeAiSettings(
                            recipeCount: _settings.recipeCount,
                            creativity: value,
                            dietaryPreferences: _settings.dietaryPreferences,
                            prioritizeExpiring: _settings.prioritizeExpiring,
                          ),
                        ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Mais tradicionais'),
                          Text('Mais criativas'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _preferencesController,
                        maxLength: 160,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Preferências alimentares',
                          hintText: 'Ex.: vegetariana, sem lactose, pouco sal',
                          helperText:
                              'Informe restrições ou preferências para orientar as receitas.',
                          prefixIcon: Icon(Icons.restaurant_menu_rounded),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) {
                          if (!_hasChanges) {
                            setState(() => _hasChanges = true);
                          }
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Priorizar itens perto do vencimento',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Dá preferência a itens que o app detectou com estoque baixo ou validade próxima.',
                        ),
                        value: _settings.prioritizeExpiring,
                        onChanged: (value) => _updateSettings(
                          LocalRecipeAiSettings(
                            recipeCount: _settings.recipeCount,
                            creativity: _settings.creativity,
                            dietaryPreferences: _settings.dietaryPreferences,
                            prioritizeExpiring: value,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _hasChanges && !_saving
                              ? _saveSettings
                              : null,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _saving ? 'Salvando...' : 'Salvar preferências',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Modo família e consumo da casa',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LiquidGlassCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.family_restroom_rounded,
                          color: scheme.primary,
                        ),
                        title: const Text(
                          'Modo família',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          LanSync.instance.enabled
                              ? 'Identifique quem usou os itens. Os registros acompanham a sincronização da casa.'
                              : 'Ative primeiro “Compartilhar com a casa” nas configurações de sincronização.',
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Ativar modo família',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _familyConfiguredEnabled && !_familyEnabled
                              ? 'A sincronização está desligada. Ative-a para registrar novos consumos por pessoa.'
                              : 'A sincronização local precisa permanecer ativa.',
                        ),
                        value: _familyConfiguredEnabled,
                        onChanged: _familySaving ||
                                (!LanSync.instance.enabled &&
                                    !_familyConfiguredEnabled)
                            ? null
                            : _toggleFamilyMode,
                      ),
                      if (_familyMembers.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _familyMembers
                              .map(
                                (person) => InputChip(
                                  avatar: const Icon(
                                    Icons.person_outline_rounded,
                                    size: 18,
                                  ),
                                  label: Text(person),
                                  onDeleted: _familySaving
                                      ? null
                                      : () => setState(
                                            () => _familyMembers =
                                                List.of(_familyMembers)
                                                  ..remove(person),
                                          ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _familyMemberController,
                              maxLength: 50,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Pessoa da casa',
                                hintText: 'Nome',
                                counterText: '',
                                prefixIcon: Icon(Icons.person_add_alt_1),
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (_) => _addFamilyMember(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            tooltip: 'Adicionar pessoa',
                            onPressed:
                                _familySaving ? null : _addFamilyMember,
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                _familySaving ? null : _saveFamilyMembers,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Salvar pessoas'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: !_familyEnabled
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const FamilyConsumptionScreen(),
                                      ),
                                    ),
                            icon: const Icon(Icons.bar_chart_rounded),
                            label: const Text('Consumo da casa'),
                          ),
                        ],
                      ),
                      if (!LanSync.instance.enabled) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Use o mesmo código da casa nos aparelhos. Os relatórios por pessoa aparecem quando a sincronização e o modo família estão ativos.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Recursos incluídos',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                LiquidGlassCard(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.auto_awesome_outlined),
                        title: Text('Geração de receitas'),
                        subtitle: Text(
                          'Cria opções com ingredientes, quantidades e modo de preparo.',
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      const ListTile(
                        leading: Icon(Icons.eco_outlined),
                        title: Text('Redução de desperdício'),
                        subtitle: Text(
                          'Use itens próximos do vencimento ou em baixa quantidade nas suas sugestões.',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
