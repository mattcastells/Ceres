import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/services/external_import.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Traer el historial de otra app, pasando por la IA de la persona.
///
/// Tres pasos en una pantalla: copiar el pedido, pegar lo que devolvió la IA
/// y revisar qué entra antes de guardar. Ver `domain/services/external_import`.
class ExternalImportScreen extends ConsumerStatefulWidget {
  const ExternalImportScreen({super.key});

  @override
  ConsumerState<ExternalImportScreen> createState() =>
      _ExternalImportScreenState();
}

class _ExternalImportScreenState extends ConsumerState<ExternalImportScreen> {
  final _text = TextEditingController();
  ExternalImport? _data;
  ExternalImportReport? _preview;
  String? _error;
  bool _usePlan = false;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  ExternalImportOptions get _options =>
      ExternalImportOptions(usePlan: _usePlan);

  Future<void> _copyPrompt() async {
    await Clipboard.setData(ClipboardData(text: externalImportPrompt(today())));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Pedido copiado. Pegáselo a tu IA.')),
      );
  }

  Future<void> _paste() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text;
    if (text == null || text.trim().isEmpty) return;
    // Si la IA lo mandó en partes, cada pegada se suma debajo de la anterior.
    _text.text = _text.text.trim().isEmpty
        ? text
        : '${_text.text.trimRight()}\n\n$text';
    _reset();
  }

  void _reset() => setState(() {
    _data = null;
    _preview = null;
    _error = null;
  });

  Future<void> _review() async {
    final ExternalImport data;
    try {
      data = ExternalImport.parse(_text.text);
    } on ExternalImportFormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    if (data.isEmpty) {
      setState(
        () => _error =
            'El bloque está vacío: la IA no encontró datos tuyos para pasar.',
      );
      return;
    }
    final repo = ref.read(repositoryProvider);
    final preview = await ExternalImporter(
      repo,
    ).preview(data, options: _options);
    if (!mounted) return;
    setState(() {
      _data = data;
      _preview = preview;
      _error = null;
    });
  }

  Future<void> _import() async {
    final data = _data;
    if (data == null || _saving) return;
    setState(() => _saving = true);
    final report = await ExternalImporter(
      ref.read(repositoryProvider),
    ).apply(data, options: _options);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            report.total == 1
                ? 'Listo: se importó 1 registro.'
                : 'Listo: se importaron ${report.total} registros.',
          ),
        ),
      );
    Navigator.of(context).pop();
  }

  Future<void> _togglePlan(bool value) async {
    setState(() => _usePlan = value);
    final data = _data;
    if (data == null) return;
    final preview = await ExternalImporter(
      ref.read(repositoryProvider),
    ).preview(data, options: _options);
    if (mounted) setState(() => _preview = preview);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final data = _data;
    final preview = _preview;

    return NmScreen(
      title: 'Importar datos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Si llevabas tu progreso con ChatGPT, Gemini, Claude u otra IA, '
            'ella puede pasarte todo de una vez.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),

          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: '1 · Pedíselo a tu IA'),
          Text(
            'Copiá el pedido y pegalo en la misma conversación (o cuenta) '
            'donde registrabas tus datos.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s3),
          NmButton(
            label: 'Copiar el pedido',
            icon: PhosphorIcons.copySimple(),
            variant: NmButtonVariant.secondary,
            block: true,
            onPressed: _copyPrompt,
          ),

          const SizedBox(height: NmSpace.s6),
          const NmSectionHeader(title: '2 · Pegá lo que te respondió'),
          NmTextField(
            label: 'Respuesta de la IA',
            controller: _text,
            hint: '===CERES=== … ===FIN===',
            maxLines: 6,
            error: _error,
            onChanged: (_) => _reset(),
          ),
          const SizedBox(height: NmSpace.s2),
          Text(
            'Si te la mandó en partes, pegalas todas, una debajo de la otra.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s3),
          Row(
            children: <Widget>[
              Expanded(
                child: NmButton(
                  label: 'Pegar',
                  icon: PhosphorIcons.chatText(),
                  variant: NmButtonVariant.ghost,
                  onPressed: _paste,
                ),
              ),
              const SizedBox(width: NmSpace.s3),
              Expanded(
                child: NmButton(
                  label: 'Revisar',
                  onPressed: _text.text.trim().isEmpty ? null : _review,
                ),
              ),
            ],
          ),

          if (data != null && preview != null) ...<Widget>[
            const SizedBox(height: NmSpace.s6),
            const NmSectionHeader(title: '3 · Qué entra'),
            _Preview(data: data, report: preview),
            if (data.plan case final plan?) ...<Widget>[
              const SizedBox(height: NmSpace.s3),
              NmSwitchRow(
                title: 'Usar su plan como mi objetivo',
                subtitle: _planLabel(plan),
                value: _usePlan,
                onChanged: _togglePlan,
              ),
            ],
            const SizedBox(height: NmSpace.s5),
            NmButton(
              label: preview.total == 0
                  ? 'No hay nada nuevo'
                  : 'Importar ${preview.total} '
                        '${preview.total == 1 ? 'registro' : 'registros'}',
              block: true,
              loading: _saving,
              onPressed: preview.total == 0 ? null : _import,
            ),
          ],
          const SizedBox(height: NmSpace.s8),
        ],
      ),
    );
  }

  static String _planLabel(ImportedPlan plan) => <String>[
    '${plan.kcal} kcal',
    if (plan.hasMacros)
      'P ${plan.proteinG} · C ${plan.carbsG} · G ${plan.fatG} g',
  ].join(' · ');
}

class _Preview extends StatelessWidget {
  const _Preview({required this.data, required this.report});

  final ExternalImport data;
  final ExternalImportReport report;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, int)>[
      ('Pesajes', report.weights),
      ('Medidas', report.measurements),
      ('Entrenamientos', report.workouts),
      ('Deportes', report.sports),
      ('Días de comida', report.nutritionDays),
      ('Comidas, como alimentos tuyos', report.foods),
    ].where((r) => r.$2 > 0).toList();

    final left = <String>[
      if (data.records > 0) 'récords',
      if (data.routineDays > 0) 'la rutina',
      if (data.supplements > 0) 'suplementos',
      if (data.otherGoals > 0) 'objetivos que no son de peso',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NmCard(
          child: Column(
            children: <Widget>[
              for (final (label, count) in rows)
                ValueRow(label: label, value: '$count'),
              if (report.profileFields.isNotEmpty)
                ValueRow(
                  label: 'Perfil',
                  value: report.profileFields.join(', '),
                ),
              if (rows.isEmpty && report.profileFields.isEmpty)
                const ValueRow(label: 'Nuevos', value: '0'),
              if (report.alreadyThere > 0)
                ValueRow(
                  label: 'Ya estaba en Ceres',
                  value: '${report.alreadyThere}',
                  muted: true,
                ),
            ],
          ),
        ),
        if (report.nutritionDays > 0) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          const InfoNote(
            text:
                'De cada día de comida llega solo el total: queda como una '
                'comida "Total del día" en la cena.',
          ),
        ],
        if (report.workouts > 0) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          const InfoNote(
            text:
                'Los ejercicios y las series quedan en la nota de cada '
                'entrenamiento.',
          ),
        ],
        if (data.estimated > 0) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          InfoNote(
            text:
                '${data.estimated == 1 ? 'Un dato no venía y se estimó' : '${data.estimated} datos no venían y se estimaron'}: '
                'duraciones, macros o calorías, según lo habitual. Cada '
                'registro estimado lo dice en su nota.',
          ),
        ],
        if (left.isNotEmpty || data.discarded > 0) ...<Widget>[
          const SizedBox(height: NmSpace.s3),
          InfoNote(
            tone: NmNoteTone.caution,
            text: <String>[
              if (left.isNotEmpty)
                'No se importa ${_list(left)}: Ceres todavía no los guarda.',
              if (data.discarded > 0)
                '${data.discarded} '
                    '${data.discarded == 1 ? 'dato venía' : 'datos venían'} '
                    'sin fecha o sin nada que medir, y no hay forma de '
                    'ubicarlos.',
            ].join(' '),
          ),
        ],
      ],
    );
  }

  static String _list(List<String> items) => items.length == 1
      ? items.single
      : '${items.sublist(0, items.length - 1).join(', ')} ni ${items.last}';
}
