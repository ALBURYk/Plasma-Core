import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'researcher_workspace_platform.dart';

const _ink = Color(0xFF111827);
const _muted = Color(0xFF64748B);
const _line = Color(0xFFE2E8F0);
const _panel = Colors.white;
const _page = Color(0xFFF5F7FA);

class ResearcherWorkspaceScreen extends StatefulWidget {
  const ResearcherWorkspaceScreen({super.key});

  @override
  State<ResearcherWorkspaceScreen> createState() =>
      _ResearcherWorkspaceScreenState();
}

class _ResearcherWorkspaceScreenState extends State<ResearcherWorkspaceScreen> {
  static const _viewerId = 'plasma-core-3dmol-viewer';
  static const _configuredApiBaseUrl = String.fromEnvironment(
    'PLASMA_API_BASE_URL',
  );
  static var _viewerRegistered = false;

  double _temperature = 45;
  double _ph = 7.2;
  String _fileName = 'Демо-структура PETase';
  String _pdbText = _demoPdb;
  String _optimizedPdb = _demoPdb;
  String _fastaText = '';
  List<_MutationInfo> _mutations = const [];
  bool _isRunning = false;
  bool _hasResult = false;
  bool _cancelRequested = false;
  bool _english = false;
  bool _darkMode = false;
  String _status = 'Готово к загрузке структуры';

  @override
  void initState() {
    super.initState();
    _registerViewer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _renderMolecule());
  }

  void _registerViewer() {
    if (_viewerRegistered) return;
    registerViewer(_viewerId);
    _viewerRegistered = true;
  }

  Future<void> _pickPdbFile() async {
    final result = await pickPdbFile();
    if (result == null) return;

    setState(() {
      _fileName = result.fileName;
      _pdbText = result.pdbText;
      _optimizedPdb = _pdbText;
      _clearResult();
      _status = 'Файл загружен';
    });
    _renderMolecule();
  }

  Future<void> _loadPetaseFromRcsb() async {
    setState(() {
      _isRunning = true;
      _status = 'Загрузка 5XJH из RCSB...';
    });

    try {
      final pdb = await loadPdbFromRcsb(
        'https://files.rcsb.org/download/5XJH.pdb',
      );
      setState(() {
        _fileName = '5XJH.pdb';
        _pdbText = pdb;
        _optimizedPdb = pdb;
        _clearResult();
        _status = 'Структура 5XJH загружена';
      });
      _renderMolecule();
    } catch (_) {
      setState(() {
        _fileName = 'Демо-структура PETase';
        _pdbText = _demoPdb;
        _optimizedPdb = _demoPdb;
        _clearResult();
        _status = 'Не удалось скачать 5XJH. Используется демо-структура';
      });
      _renderMolecule();
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _runOptimization() async {
    if (_pdbText.trim().isEmpty) {
      setState(() => _status = 'Сначала загрузите PDB-файл');
      return;
    }

    setState(() {
      _isRunning = true;
      _cancelRequested = false;
      _clearResult();
      _status = 'Расчет выполняется...';
    });

    try {
      final response = await _callBackend();
      if (_cancelRequested) return;
      setState(() {
        _optimizedPdb = response.pdb;
        _fastaText = response.fasta;
        _mutations = response.mutations;
        _hasResult = true;
        _status = 'Расчет завершен';
      });
    } catch (_) {
      if (_cancelRequested) {
        setState(() => _status = 'Расчет остановлен');
        return;
      }

      final fallback = _simulateOptimization(_pdbText, _temperature, _ph);
      setState(() {
        _optimizedPdb = fallback.pdb;
        _fastaText = fallback.fasta;
        _mutations = fallback.mutations;
        _hasResult = true;
        _status = 'Backend недоступен. Показан локальный расчет';
      });
    } finally {
      setState(() => _isRunning = false);
      if (!_cancelRequested) _renderMolecule();
    }
  }

  void _stopOptimization() {
    _cancelRequested = true;
    setState(() {
      _isRunning = false;
      _clearResult();
      _status = 'Расчет остановлен';
    });
  }

  void _clearResult() {
    _hasResult = false;
    _fastaText = '';
    _mutations = const [];
  }

  Future<_OptimizationResult> _callBackend() async {
    Object? lastError;
    for (final endpoint in _backendEndpoints()) {
      if (_cancelRequested) throw StateError('cancelled');
      try {
        return await _postOptimization(endpoint);
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError('Backend unavailable: $lastError');
  }

  List<String> _backendEndpoints() {
    if (_configuredApiBaseUrl.isNotEmpty) {
      final baseUrl = _configuredApiBaseUrl.replaceFirst(RegExp(r'/$'), '');
      return ['$baseUrl/api/v1/optimize'];
    }

    final localEndpoints = [
      'http://127.0.0.1:8000/api/v1/optimize',
      'http://127.0.0.1:8001/api/v1/optimize',
      'http://127.0.0.1:8002/api/v1/optimize',
      'http://10.0.2.2:8000/api/v1/optimize',
    ];

    if (!isWeb) return localEndpoints;
    return ['/api/v1/optimize', ...localEndpoints];
  }

  Future<_OptimizationResult> _postOptimization(String endpoint) async {
    final response = await postOptimization(
      endpoint,
      _fileName,
      _pdbText,
      _temperature.toStringAsFixed(1),
      _ph.toStringAsFixed(1),
    );

    if (_cancelRequested) throw StateError('cancelled');
    if (response.status < 200 || response.status > 299) {
      throw StateError('Backend returned ${response.status}');
    }

    final data = jsonDecode(response.responseText) as Map<String, dynamic>;
    return _OptimizationResult(
      pdb: data['optimized_pdb'] as String? ?? _pdbText,
      fasta: data['fasta'] as String? ?? '',
      mutations: (data['mutations'] as List<dynamic>? ?? const [])
          .map((item) => _MutationInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  void _renderMolecule() {
    scheduleMicrotask(() {
      final residues = _mutations.map((mutation) => mutation.position).toList();
      renderMolecule(
        _viewerId,
        _optimizedPdb.isEmpty ? _pdbText : _optimizedPdb,
        residues,
      );
    });
  }

  void _downloadFasta() {
    if (_fastaText.isEmpty) return;
    downloadText(
      'plasma_core_candidate.fasta',
      _fastaText,
      'text/plain;charset=utf-8',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 940;
              final inputPanel = _InputPanel(
                english: _english,
                fileName: _fileName,
                temperature: _temperature,
                ph: _ph,
                isRunning: _isRunning,
                onPickFile: _pickPdbFile,
                onLoadPetase: _loadPetaseFromRcsb,
                onRun: _runOptimization,
                onStop: _stopOptimization,
                onTemperatureChanged: (value) {
                  setState(() => _temperature = value);
                },
                onPhChanged: (value) => setState(() => _ph = value),
              );
              final moleculePanel = _MoleculePanel(
                english: _english,
                status: _statusText(_status, _english),
                mutationCount: _mutations.length,
              );

              return Column(
                children: [
                  _WorkspaceHeader(
                    english: _english,
                    darkMode: _darkMode,
                    onToggleLanguage: () {
                      setState(() => _english = !_english);
                    },
                    onToggleTheme: () {
                      setState(() => _darkMode = !_darkMode);
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: compact
                        ? ListView(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            children: [
                              inputPanel,
                              const SizedBox(height: 12),
                              SizedBox(
                                height: (constraints.maxHeight * 0.46).clamp(
                                  280.0,
                                  520.0,
                                ),
                                child: moleculePanel,
                              ),
                              const SizedBox(height: 12),
                              _ResultPanel(
                                english: _english,
                                fastaText: _fastaText,
                                hasResult: _hasResult,
                                mutations: _mutations,
                                onDownload: _downloadFasta,
                                compact: true,
                              ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'made by Albury',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: _muted,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 380, child: inputPanel),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: moleculePanel),
                                    const SizedBox(height: 12),
                                    _ResultPanel(
                                      english: _english,
                                      fastaText: _fastaText,
                                      hasResult: _hasResult,
                                      mutations: _mutations,
                                      onDownload: _downloadFasta,
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(
                                        'made by Albury',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: _muted,
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    if (!_darkMode) return scaffold;

    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.82,
        0,
        0,
        0,
        235,
        0,
        -0.82,
        0,
        0,
        235,
        0,
        0,
        -0.82,
        0,
        235,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: scaffold,
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.english,
    required this.darkMode,
    required this.onToggleLanguage,
    required this.onToggleTheme,
  });

  final bool english;
  final bool darkMode;
  final VoidCallback onToggleLanguage;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 840;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: _panelDecoration(),
          child: narrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Plasma Core',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: _ink,
                                  fontWeight: FontWeight.w800,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: onToggleLanguage,
                          child: Text(english ? 'EN' : 'RU'),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: darkMode ? 'Light mode' : 'Dark mode',
                          onPressed: onToggleTheme,
                          icon: Icon(
                            darkMode
                                ? Icons.wb_sunny_outlined
                                : Icons.dark_mode_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _SmallPill(
                          text: english
                              ? 'Protein design workspace'
                              : 'Рабочая область белка',
                        ),
                        const _SmallPill(text: 'PDB: RCSB 5XJH'),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(
                      Icons.biotech_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Plasma Core',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 14),
                    _SmallPill(
                      text: english
                          ? 'Protein design workspace'
                          : 'Рабочая область белка',
                    ),
                    const Spacer(),
                    const _SmallPill(text: 'PDB: RCSB 5XJH'),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: onToggleLanguage,
                      child: Text(english ? 'EN' : 'RU'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: darkMode ? 'Light mode' : 'Dark mode',
                      onPressed: onToggleTheme,
                      icon: Icon(
                        darkMode
                            ? Icons.wb_sunny_outlined
                            : Icons.dark_mode_outlined,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _SmallPill extends StatelessWidget {
  const _SmallPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: _muted),
        ),
      ),
    );
  }
}

class _InputPanel extends StatelessWidget {
  const _InputPanel({
    required this.english,
    required this.fileName,
    required this.temperature,
    required this.ph,
    required this.isRunning,
    required this.onPickFile,
    required this.onLoadPetase,
    required this.onRun,
    required this.onStop,
    required this.onTemperatureChanged,
    required this.onPhChanged,
  });

  final bool english;
  final String fileName;
  final double temperature;
  final double ph;
  final bool isRunning;
  final VoidCallback onPickFile;
  final VoidCallback onLoadPetase;
  final VoidCallback onRun;
  final VoidCallback onStop;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<double> onPhChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(
              icon: Icons.tune_outlined,
              title: english ? 'Parameters' : 'Параметры',
              subtitle: english
                  ? 'Protein structure and environment'
                  : 'Структура белка и условия среды',
            ),
            const SizedBox(height: 18),
            _FileBox(
              english: english,
              fileName: fileName,
              onPickFile: onPickFile,
              onLoadPetase: isRunning ? null : onLoadPetase,
            ),
            const SizedBox(height: 22),
            _SliderBlock(
              icon: Icons.thermostat_outlined,
              label: english ? 'Temperature' : 'Температура',
              valueLabel: '${temperature.round()}°C',
              value: temperature,
              min: 20,
              max: 60,
              divisions: 40,
              onChanged: onTemperatureChanged,
            ),
            const SizedBox(height: 14),
            _SliderBlock(
              icon: Icons.water_drop_outlined,
              label: 'pH',
              valueLabel: ph.toStringAsFixed(1),
              value: ph,
              min: 4,
              max: 10,
              divisions: 60,
              onChanged: onPhChanged,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isRunning ? null : onRun,
                icon: isRunning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  isRunning
                      ? (english ? 'Running' : 'Расчет выполняется')
                      : (english ? 'Run calculation' : 'Запустить расчет'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isRunning ? onStop : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(english ? 'Stop' : 'Остановить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: _muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileBox extends StatelessWidget {
  const _FileBox({
    required this.english,
    required this.fileName,
    required this.onPickFile,
    required this.onLoadPetase,
  });

  final bool english;
  final String fileName;
  final VoidCallback onPickFile;
  final VoidCallback? onLoadPetase;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 20, color: _muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _fileNameText(fileName, english),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 360;
                return narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onPickFile,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(english ? 'PDB file' : 'PDB файл'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: onLoadPetase,
                            icon: const Icon(Icons.cloud_download_outlined),
                            label: const Text('5XJH'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onPickFile,
                              icon: const Icon(Icons.upload_file_outlined),
                              label: Text(english ? 'PDB file' : 'PDB файл'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onLoadPetase,
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('5XJH'),
                            ),
                          ),
                        ],
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderBlock extends StatelessWidget {
  const _SliderBlock({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  valueLabel,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _MoleculePanel extends StatelessWidget {
  const _MoleculePanel({
    required this.english,
    required this.status,
    required this.mutationCount,
  });

  final bool english;
  final String status;
  final int mutationCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: _panel,
                border: Border(bottom: BorderSide(color: _line)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.view_in_ar_outlined, color: _ink),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      english ? '3D structure' : '3D структура',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SmallPill(
                    text: english
                        ? '$mutationCount mutations'
                        : '$mutationCount мутаций',
                  ),
                ],
              ),
            ),
            Expanded(
              child: buildViewer(_ResearcherWorkspaceScreenState._viewerId),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({
    required this.english,
    required this.fastaText,
    required this.hasResult,
    required this.mutations,
    required this.onDownload,
    this.compact = false,
  });

  final bool english;
  final String fastaText;
  final bool hasResult;
  final List<_MutationInfo> mutations;
  final VoidCallback onDownload;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 430 : 220,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 720;
          final textStyle = TextStyle(
            color: _ink,
            fontFamily: 'monospace',
            fontSize: compact ? 12 : 13,
            height: 1.4,
          );

          Widget buildFastaCard() {
            return DecoratedBox(
              decoration: _panelDecoration(),
              child: Padding(
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(
                      icon: Icons.text_snippet_outlined,
                      title: english ? 'FASTA result' : 'FASTA результат',
                      subtitle: english
                          ? 'Synthetic coding DNA from reverse translation'
                          : 'Синтетическая coding DNA, полученная обратным переводом белка',
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _line),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 10 : 12),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            child: SelectableText(
                              hasResult
                                  ? fastaText
                                  : english
                                  ? 'FASTA will appear here after calculation. PDB stores protein structure, not source DNA.'
                                  : 'После расчета здесь появится FASTA. PDB хранит структуру белка, а не исходную ДНК.',
                              style: textStyle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          Widget buildMutationsCard() {
            return DecoratedBox(
              decoration: _panelDecoration(),
              child: Padding(
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PanelTitle(
                      icon: Icons.account_tree_outlined,
                      title: english ? 'Mutations' : 'Мутации',
                      subtitle: english
                          ? 'Positions are highlighted in 3D'
                          : 'Позиции подсвечены в 3D',
                    ),
                    SizedBox(height: compact ? 8 : 10),
                    Expanded(
                      child: _MutationList(
                        english: english,
                        mutations: mutations,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: compact ? 34 : null,
                      child: FilledButton.icon(
                        onPressed: hasResult ? onDownload : null,
                        icon: const Icon(Icons.download_outlined, size: 18),
                        label: Text(
                          english ? 'Download FASTA' : 'Скачать FASTA',
                          style: TextStyle(fontSize: compact ? 12 : null),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          if (narrow) {
            return Column(
              children: [
                Expanded(child: buildFastaCard()),
                const SizedBox(height: 12),
                Expanded(child: buildMutationsCard()),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: buildFastaCard()),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: compact ? 260 : 300),
                child: buildMutationsCard(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MutationList extends StatelessWidget {
  const _MutationList({required this.english, required this.mutations});

  final bool english;
  final List<_MutationInfo> mutations;

  @override
  Widget build(BuildContext context) {
    if (mutations.isEmpty) {
      return Center(
        child: Text(
          english ? 'No result yet' : 'Пока нет результата',
          style: const TextStyle(color: _muted),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: mutations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final mutation = mutations[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 54,
                child: Text(
                  mutation.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mutation.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: _panel,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: _line),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

String _fileNameText(String fileName, bool english) {
  if (!english) return fileName;
  if (fileName == 'Демо-структура PETase') return 'PETase demo structure';
  return fileName;
}

String _statusText(String status, bool english) {
  if (!english) return status;
  return switch (status) {
    'Готово к загрузке структуры' => 'Ready to load structure',
    'Файл загружен' => 'File loaded',
    'Загрузка 5XJH из RCSB...' => 'Loading 5XJH from RCSB...',
    'Структура 5XJH загружена' => '5XJH structure loaded',
    'Не удалось скачать 5XJH. Используется демо-структура' =>
      'Could not download 5XJH. Demo structure is used',
    'Сначала загрузите PDB-файл' => 'Load a PDB file first',
    'Расчет выполняется...' => 'Calculation is running...',
    'Расчет завершен' => 'Calculation complete',
    'Расчет остановлен' => 'Calculation stopped',
    'Backend недоступен. Показан локальный расчет' =>
      'Backend unavailable. Local calculation shown',
    _ => status,
  };
}

_OptimizationResult _simulateOptimization(
  String pdb,
  double temperature,
  double ph,
) {
  final residues = _extractResidues(pdb);
  final mutations = <_MutationInfo>[];
  final sequence = residues
      .map((residue) => _threeToOne[residue.name] ?? 'X')
      .toList();

  for (final residue in residues) {
    if (mutations.length >= 6) break;
    final rule = _mutationRuleFor(residue.name, temperature, ph);
    if (rule == null) continue;

    final original = _threeToOne[residue.name] ?? 'X';
    if (original == rule.replacement) continue;

    sequence[residue.index - 1] = rule.replacement;
    mutations.add(
      _MutationInfo(
        position: residue.index,
        original: original,
        replacement: rule.replacement,
        reason: rule.reason,
      ),
    );
  }

  final dna = _proteinToDna(sequence.join());
  return _OptimizationResult(
    pdb: pdb,
    fasta: [
      '>plasma_core_synthetic_coding_dna temp=${temperature.toStringAsFixed(1)}C ph=${ph.toStringAsFixed(1)} mutations=${mutations.isEmpty ? 'none' : mutations.map((mutation) => mutation.label).join(',')}',
      _wrapSequence(dna),
    ].join('\n'),
    mutations: mutations,
  );
}

List<_ResidueInfo> _extractResidues(String pdb) {
  final residues = <_ResidueInfo>[];
  final seen = <String>{};
  for (final line in const LineSplitter().convert(pdb)) {
    if (!line.startsWith('ATOM') || line.length < 26) continue;
    final name = line.substring(17, 20).trim();
    final chain = line.length > 21 ? line.substring(21, 22) : 'A';
    final number = line.substring(22, 26).trim();
    final key = '$chain:$number';
    if (name.isNotEmpty && seen.add(key) && _threeToOne.containsKey(name)) {
      residues.add(_ResidueInfo(index: residues.length + 1, name: name));
    }
  }
  return residues;
}

_MutationRule? _mutationRuleFor(String residue, double temperature, double ph) {
  if (temperature >= 42) {
    final thermal = _thermalRules[residue];
    if (thermal != null) return thermal;
  }
  if (ph >= 8.0) {
    final alkaline = _alkalineRules[residue];
    if (alkaline != null) return alkaline;
  }
  return null;
}

String _proteinToDna(String protein) {
  final buffer = StringBuffer();
  for (final aminoAcid in protein.split('')) {
    buffer.write(_dnaCodons[aminoAcid] ?? 'NNN');
  }
  buffer.write('TAA');
  return buffer.toString();
}

String _wrapSequence(String sequence) {
  final buffer = StringBuffer();
  for (var i = 0; i < sequence.length; i += 72) {
    final end = i + 72 < sequence.length ? i + 72 : sequence.length;
    buffer.writeln(sequence.substring(i, end));
  }
  return buffer.toString().trimRight();
}

class _OptimizationResult {
  const _OptimizationResult({
    required this.pdb,
    required this.fasta,
    required this.mutations,
  });

  final String pdb;
  final String fasta;
  final List<_MutationInfo> mutations;
}

class _ResidueInfo {
  const _ResidueInfo({required this.index, required this.name});

  final int index;
  final String name;
}

class _MutationInfo {
  const _MutationInfo({
    required this.position,
    required this.original,
    required this.replacement,
    required this.reason,
  });

  factory _MutationInfo.fromJson(Map<String, dynamic> json) {
    return _MutationInfo(
      position: json['position'] as int? ?? 0,
      original: json['original'] as String? ?? '?',
      replacement: json['replacement'] as String? ?? '?',
      reason: json['reason'] as String? ?? '',
    );
  }

  final int position;
  final String original;
  final String replacement;
  final String reason;

  String get label => '$original$position$replacement';
}

class _MutationRule {
  const _MutationRule(this.replacement, this.reason);

  final String replacement;
  final String reason;
}

const _threeToOne = {
  'ALA': 'A',
  'ARG': 'R',
  'ASN': 'N',
  'ASP': 'D',
  'CYS': 'C',
  'GLN': 'Q',
  'GLU': 'E',
  'GLY': 'G',
  'HIS': 'H',
  'ILE': 'I',
  'LEU': 'L',
  'LYS': 'K',
  'MET': 'M',
  'PHE': 'F',
  'PRO': 'P',
  'SER': 'S',
  'THR': 'T',
  'TRP': 'W',
  'TYR': 'Y',
  'VAL': 'V',
};

const _dnaCodons = {
  'A': 'GCT',
  'R': 'CGT',
  'N': 'AAC',
  'D': 'GAC',
  'C': 'TGC',
  'Q': 'CAG',
  'E': 'GAA',
  'G': 'GGT',
  'H': 'CAC',
  'I': 'ATT',
  'L': 'CTG',
  'K': 'AAA',
  'M': 'ATG',
  'F': 'TTC',
  'P': 'CCT',
  'S': 'TCT',
  'T': 'ACC',
  'W': 'TGG',
  'Y': 'TAC',
  'V': 'GTT',
};

const _thermalRules = {
  'ASN': _MutationRule('D', 'Thermostability'),
  'GLN': _MutationRule('E', 'Thermostability'),
  'GLY': _MutationRule('A', 'Reduced loop flexibility'),
  'MET': _MutationRule('L', 'Lower oxidation risk'),
  'CYS': _MutationRule('S', 'Free cysteine stabilization'),
};

const _alkalineRules = {
  'ASP': _MutationRule('N', 'Alkaline pH adaptation'),
  'GLU': _MutationRule('Q', 'Alkaline pH adaptation'),
};

const _demoPdb = '''
ATOM      1  N   MET A   1      -8.917  -2.391   0.000  1.00 24.44           N
ATOM      2  CA  MET A   1      -7.602  -1.793   0.000  1.00 24.44           C
ATOM      3  C   MET A   1      -6.561  -2.905   0.000  1.00 24.44           C
ATOM      4  O   MET A   1      -6.852  -4.103   0.000  1.00 24.44           O
ATOM      5  N   GLY A   2      -5.345  -2.501   0.000  1.00 24.44           N
ATOM      6  CA  GLY A   2      -4.236  -3.451   0.000  1.00 24.44           C
ATOM      7  C   GLY A   2      -3.001  -2.713   0.000  1.00 24.44           C
ATOM      8  O   GLY A   2      -2.834  -1.497   0.000  1.00 24.44           O
ATOM      9  N   ASN A   3      -2.125  -3.454   0.000  1.00 24.44           N
ATOM     10  CA  ASN A   3      -0.882  -2.854   0.000  1.00 24.44           C
ATOM     11  C   ASN A   3       0.265  -3.860   0.000  1.00 24.44           C
ATOM     12  O   ASN A   3       0.027  -5.065   0.000  1.00 24.44           O
ATOM     13  N   LEU A   4       1.509  -3.360   0.000  1.00 24.44           N
ATOM     14  CA  LEU A   4       2.699  -4.207   0.000  1.00 24.44           C
ATOM     15  C   LEU A   4       3.866  -3.279   0.000  1.00 24.44           C
ATOM     16  O   LEU A   4       3.686  -2.061   0.000  1.00 24.44           O
ATOM     17  N   CYS A   5       5.064  -3.864   0.000  1.00 24.44           N
ATOM     18  CA  CYS A   5       6.272  -3.074   0.000  1.00 24.44           C
ATOM     19  C   CYS A   5       7.447  -4.019   0.000  1.00 24.44           C
ATOM     20  O   CYS A   5       7.253  -5.224   0.000  1.00 24.44           O
TER
END
''';
