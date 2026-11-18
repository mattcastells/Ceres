import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/models/sleep.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Registrar cuánto y cómo se durmió.
///
/// Es una estimación de la persona, no una medición: la app no tiene forma de
/// saber cuánto dormiste y no finge tenerla.
Future<void> showSleepSheet(BuildContext context, {DateTime? date}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _SleepSheet(date: date ?? today()),
    );

class _SleepSheet extends ConsumerStatefulWidget {
  const _SleepSheet({required this.date});

  final DateTime date;

  @override
  ConsumerState<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<_SleepSheet> {
  late int _minutes;
  late SleepQuality _quality;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(repositoryProvider).sleepOn(widget.date);
    _minutes = existing?.minutes ?? 7 * 60;
    _quality = existing?.quality ?? SleepQuality.ok;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(repositoryProvider)
        .logSleep(date: widget.date, minutes: _minutes, quality: _quality);
    if (!mounted) return;
    Navigator.of(context).pop();
    NmSnackbar.show(context, 'Sueño registrado');
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final existing = ref.watch(repositoryProvider).sleepOn(widget.date);
    final hours = _minutes ~/ 60;
    final mins = _minutes % 60;

    return NmSheet(
      // Título y día como las otras hojas del "+" (peso, medidas, alcohol):
      // el día iba suelto en el cuerpo y el título no era el de su entrada.
      title: existing == null ? 'Registrar sueño' : 'Editar el sueño',
      subtitle: friendlyDay(widget.date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[

          Center(
            child: Text(
              mins == 0 ? '$hours h' : '$hours h $mins',
              style: NmTextStyles.from(NmType.display, color: nm.text).tnum,
            ),
          ),
          // Pasos de 15 minutos: nadie recuerda su sueño al minuto, y el paso
          // fino solo agrega precisión falsa.
          Slider(
            value: _minutes.toDouble(),
            min: SleepLog.minMinutes.toDouble(),
            max: SleepLog.maxMinutes.toDouble(),
            divisions: (SleepLog.maxMinutes - SleepLog.minMinutes) ~/ 15,
            label: mins == 0 ? '$hours h' : '$hours h $mins',
            onChanged: (v) => setState(() => _minutes = v.round()),
          ),

          const SizedBox(height: NmSpace.s4),
          Text(
            'Cómo dormiste',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final quality in SleepQuality.values)
                NmChip(
                  label: quality.label,
                  selected: quality == _quality,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() => _quality = quality),
                ),
            ],
          ),

          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Guardar',
            block: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (existing != null) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            NmButton.ghost(
              label: 'Eliminar el registro',
              onPressed: () async {
                await ref.read(repositoryProvider).deleteSleep(existing.id);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
          const SizedBox(height: NmSpace.s2),
          Text(
            'Es tu estimación: la app no mide el sueño.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
