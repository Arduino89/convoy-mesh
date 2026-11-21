import 'package:flutter/material.dart';

import '../design_controller.dart';
import '../design_presets.dart';
import '../design_theme.dart';
import '../design_tokens.dart';
import '../outdoor_config.dart';
import '../outdoor_copy.dart';
import 'studio_controls.dart';
import 'studio_customize_pane.dart';
import 'studio_json_dialog.dart';
import 'studio_preview_pane.dart';
import 'synthetic_radar_fixtures.dart';

export 'studio_customize_pane.dart' show CustomizerCategory;
export 'studio_preview_pane.dart' show StudioPreviewPage;

enum StudioMode { preview, customize }

/// Interactive **Outdoor Studio** for Convoy Mesh (100% synthetic data).
///
/// Offers two workspaces:
/// * **Anteprima UI**: side-by-side synthetic preview across Radar BLE, Map and
///   Diagnostic screens switching between **Outdoor Premium** and
///   **Originale (LAB +15)** for easy visual regression checks & rollback.
/// * **Personalizza**: live 6-axis customiser for Outdoor Premium (Colors,
///   Typography, Dimensions, Spacing, Animations, Visual Copy) with real-time
///   WCAG contrast diagnostics and validated JSON import/export.
class FrontendDesignStudioPage extends StatefulWidget {
  const FrontendDesignStudioPage({
    super.key,
    this.controller,
    this.initialDirection,
    this.initialCustomizeTab = false,
  });

  final DesignDirectionController? controller;
  final DesignDirection? initialDirection;
  final bool initialCustomizeTab;

  @override
  State<FrontendDesignStudioPage> createState() =>
      _FrontendDesignStudioPageState();
}

class _FrontendDesignStudioPageState extends State<FrontendDesignStudioPage> {
  late DesignDirection _selected;
  late OutdoorCustomConfig _draft;
  late StudioMode _mode;
  CustomizerCategory _category = CustomizerCategory.colors;
  StudioPreviewPage _previewPage = StudioPreviewPage.radar;
  SyntheticScenario _scenario = SyntheticScenario.groupHike;
  bool _syntheticOnlineBasemap = true;
  bool _syntheticDiagActive = true;
  bool _discardPromptOpen = false;

  final Map<String, TextEditingController> _copyControllers = {};

  DesignDirectionController get _ctrl =>
      widget.controller ?? DesignDirectionController.instance;

  @override
  void initState() {
    super.initState();
    _draft = _ctrl.config;
    _mode =
        widget.initialCustomizeTab ? StudioMode.customize : StudioMode.preview;
    _selected = _mode == StudioMode.customize
        ? DesignDirection.outdoorPremium
        : (widget.initialDirection ?? _ctrl.direction);
    _initCopyControllers(_draft.copy);
  }

  void _initCopyControllers(OutdoorCopyTokens copy) {
    final map = copy.toJson();
    for (final e in map.entries) {
      if (e.key == 'radarCaption') continue;
      _copyControllers[e.key] = TextEditingController(text: e.value);
    }
  }

  void _syncCopyControllers(OutdoorCopyTokens copy) {
    final map = copy.toJson();
    for (final e in map.entries) {
      final c = _copyControllers[e.key];
      if (c != null && c.text != e.value) c.text = e.value;
    }
  }

  @override
  void dispose() {
    for (final c in _copyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty => _selected != _ctrl.direction || _draft != _ctrl.config;

  void _updateDraft(OutdoorCustomConfig next) {
    setState(() {
      _draft = next;
      _selected = DesignDirection.outdoorPremium;
    });
  }

  Future<void> _apply() async {
    final saved = await _ctrl.applySelection(_selected, _draft);
    if (!mounted) return;
    setState(() {});
    final note = saved
        ? 'Stile applicato: ${_selected.label}'
        : 'Stile applicato in memoria (${_selected.label}), ma il salvataggio locale non è riuscito.';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _resetAll() {
    setState(() {
      _draft = OutdoorCustomConfig.defaults;
      _selected = DesignDirection.outdoorPremium;
      _syncCopyControllers(_draft.copy);
    });
  }

  void _resetCopyOnly() {
    setState(() {
      _draft = _draft.copyWith(copy: OutdoorCopyTokens.defaults);
      _selected = DesignDirection.outdoorPremium;
      _syncCopyControllers(_draft.copy);
    });
  }

  Future<void> _exportJson() async {
    await showStudioExportJsonDialog(context, config: _draft);
  }

  Future<void> _importJson(ConvoyDesignTokens tokens) async {
    final imported = await showStudioImportJsonDialog(context, tokens: tokens);
    if (imported == null || !mounted) return;
    setState(() {
      _draft = imported;
      _selected = DesignDirection.outdoorPremium;
      _syncCopyControllers(imported.copy);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Configurazione JSON caricata nella bozza. Tocca Applica per confermare.',
        ),
      ),
    );
  }

  Future<void> _confirmDiscardAndPop() async {
    if (_discardPromptOpen) return;
    _discardPromptOpen = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Scartare le modifiche?'),
          content: const Text(
            'Hai personalizzazioni non ancora applicate in Outdoor Studio. Vuoi uscire senza applicarle?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Resta'),
            ),
            FilledButton(
              key: const Key('studio-discard-confirm-btn'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Scarta ed esci'),
            ),
          ],
        ),
      );
      if (discard == true && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } finally {
      _discardPromptOpen = false;
    }
  }

  void _onPreviewAction(String name) {
    if (!mounted) return;
    if (name == 'chooseDesign') {
      setState(() {
        _mode = StudioMode.customize;
        _selected = DesignDirection.outdoorPremium;
      });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Anteprima sintetica: azione «$name»'),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outdoorTokens = DesignPresets.buildOutdoor(_draft);
    final outerTheme = buildConvoyTheme(outdoorTokens);
    final dirty = _dirty;

    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && dirty) {
          _confirmDiscardAndPop();
        }
      },
      child: Theme(
        data: outerTheme,
        child: Scaffold(
          backgroundColor: outdoorTokens.canvas,
          appBar: AppBar(
            title: Text(
              'Outdoor Studio',
              style: outdoorTokens.display(21, color: outdoorTokens.inkOnCanvas),
            ),
            actions: [
              IconButton(
                key: const Key('studio-import-json-btn'),
                tooltip: 'Importa configurazione JSON',
                icon: const Icon(Icons.file_upload_outlined),
                onPressed: () => _importJson(outdoorTokens),
              ),
              IconButton(
                key: const Key('studio-export-json-btn'),
                tooltip: 'Esporta configurazione JSON',
                icon: const Icon(Icons.data_object),
                onPressed: _exportJson,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: const Key('studio-apply-btn'),
                  onPressed: dirty ? _apply : null,
                  child: Text(dirty ? 'Applica' : 'Attivo'),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              _modeBar(outdoorTokens),
              Divider(height: 1, color: outdoorTokens.outline),
              Expanded(
                child: _mode == StudioMode.preview
                    ? StudioPreviewWorkspace(
                        outdoorTokens: outdoorTokens,
                        selectedDirection: _selected,
                        previewPage: _previewPage,
                        scenario: _scenario,
                        onlineBasemap: _syntheticOnlineBasemap,
                        diagActive: _syntheticDiagActive,
                        onSelectDirection: (d) => setState(() => _selected = d),
                        onSelectScenario: (s) => setState(() => _scenario = s),
                        onSelectPreviewPage: (p) =>
                            setState(() => _previewPage = p),
                        onToggleOnlineBasemap: (v) =>
                            setState(() => _syntheticOnlineBasemap = v),
                        onToggleDiagActive: () => setState(
                          () => _syntheticDiagActive = !_syntheticDiagActive,
                        ),
                        onToggleOutingScenario: () => setState(() {
                          _scenario = _scenario == SyntheticScenario.activeOuting
                              ? SyntheticScenario.groupHike
                              : SyntheticScenario.activeOuting;
                        }),
                        onOpenCustomize: () => setState(() {
                          _mode = StudioMode.customize;
                          _selected = DesignDirection.outdoorPremium;
                        }),
                        onPreviewAction: _onPreviewAction,
                      )
                    : StudioCustomizeWorkspace(
                        tokens: outdoorTokens,
                        draft: _draft,
                        category: _category,
                        copyControllers: _copyControllers,
                        onSelectCategory: (c) => setState(() => _category = c),
                        onUpdateDraft: _updateDraft,
                        onResetCopy: _resetCopyOnly,
                        onResetAll: _resetAll,
                        onOpenPreview: () =>
                            setState(() => _mode = StudioMode.preview),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeBar(ConvoyDesignTokens t) {
    return Container(
      color: t.surface,
      padding: EdgeInsets.fromLTRB(t.hPad * 0.75, 8, t.hPad * 0.75, 10),
      child: Row(children: [
        Expanded(
          child: StudioModeTabButton(
            key: const Key('studio-mode-preview'),
            tokens: t,
            icon: Icons.smartphone_outlined,
            label: 'Anteprima UI',
            selected: _mode == StudioMode.preview,
            onTap: () => setState(() => _mode = StudioMode.preview),
          ),
        ),
        SizedBox(width: t.space(2)),
        Expanded(
          child: StudioModeTabButton(
            key: const Key('studio-mode-customize'),
            tokens: t,
            icon: Icons.tune,
            label: 'Personalizza',
            selected: _mode == StudioMode.customize,
            onTap: () => setState(() {
              _mode = StudioMode.customize;
              _selected = DesignDirection.outdoorPremium;
            }),
          ),
        ),
      ]),
    );
  }
}
