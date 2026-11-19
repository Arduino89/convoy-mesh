import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import '../outdoor_components.dart';
import '../outdoor_config.dart';

/// Displays formatted Outdoor JSON configuration with Copy & Close actions.
Future<void> showStudioExportJsonDialog(
  BuildContext context, {
  required OutdoorCustomConfig config,
}) async {
  final formatted = const JsonEncoder.withIndent('  ').convert(config.toJson());
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Configurazione Outdoor JSON'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            formatted,
            style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11.5),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: formatted));
            if (ctx.mounted) {
              Navigator.pop(ctx);
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Configurazione JSON copiata negli appunti.'),
                ),
              );
            }
          },
          child: const Text('Copia'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

/// Opens a validated JSON import modal for [OutdoorCustomConfig].
///
/// Validates syntax, size limit (16 KB), top-level object structure and known
/// keys via [OutdoorCustomConfig.tryParseJsonString]; never sends data over the
/// network or mutates the active controller directly until the caller applies.
Future<OutdoorCustomConfig?> showStudioImportJsonDialog(
  BuildContext context, {
  required ConvoyDesignTokens tokens,
}) async {
  final controller = TextEditingController();
  String? errorText;
  OutdoorCustomConfig? parsedConfig;

  try {
    return await showDialog<OutdoorCustomConfig>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void validate(String raw) {
            if (raw.trim().isEmpty) {
              setDialogState(() {
                errorText = null;
                parsedConfig = null;
              });
              return;
            }
            final result = OutdoorCustomConfig.tryParseJsonString(raw);
            setDialogState(() {
              errorText = result.error;
              parsedConfig = result.config;
            });
          }

          void submit() {
            final result = OutdoorCustomConfig.tryParseJsonString(
              controller.text,
            );
            if (result.isOk) {
              Navigator.pop(ctx, result.config);
            } else {
              setDialogState(() {
                errorText = result.error;
                parsedConfig = null;
              });
            }
          }

          return AlertDialog(
            title: const Text('Importa configurazione JSON'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Incolla un JSON esportato da Outdoor Studio (solo uso locale, max 16 KB). I campi fuori scala vengono normalizzati e le note tecniche protette restano invariate.',
                      style: tokens.body(12.5, color: tokens.inkMuted),
                    ),
                    SizedBox(height: tokens.space(2)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const Key('studio-json-paste-btn'),
                        onPressed: () async {
                          final data = await Clipboard.getData(
                            Clipboard.kTextPlain,
                          );
                          final text = data?.text;
                          if (text == null || text.isEmpty) {
                            setDialogState(() {
                              errorText = 'Appunti vuoti o non testuali.';
                              parsedConfig = null;
                            });
                            return;
                          }
                          controller.text = text;
                          validate(text);
                        },
                        icon: const Icon(Icons.content_paste, size: 18),
                        label: const Text('Incolla dagli appunti'),
                      ),
                    ),
                    SizedBox(height: tokens.space(1)),
                    TextField(
                      key: const Key('studio-json-import-field'),
                      controller: controller,
                      minLines: 4,
                      maxLines: 8,
                      style: const TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 11.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '{"palettePreset": "pinoECarta", ...}',
                        alignLabelWithHint: true,
                      ),
                      onChanged: validate,
                    ),
                    if (errorText != null) ...[
                      SizedBox(height: tokens.space(2)),
                      OutdoorCallout(
                        key: const Key('studio-json-import-error'),
                        tokens: tokens,
                        icon: Icons.error_outline,
                        tone: OutdoorTone.critical,
                        text: errorText!,
                      ),
                    ] else if (parsedConfig != null) ...[
                      SizedBox(height: tokens.space(2)),
                      OutdoorCallout(
                        key: const Key('studio-json-import-valid'),
                        tokens: tokens,
                        icon: Icons.check_circle_outline,
                        tone: OutdoorTone.positive,
                        text:
                            'JSON valido (${parsedConfig!.palettePreset.label}). Tocca Importa per caricarlo nella bozza.',
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annulla'),
              ),
              FilledButton(
                key: const Key('studio-json-import-submit'),
                onPressed: submit,
                child: const Text('Importa'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    controller.dispose();
  }
}
