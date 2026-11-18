import 'package:flutter/material.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/models/meal.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';

/// Cambiar la cantidad de un ítem ya cargado.
///
/// Hacía falta para lo que estima la IA —que casi siempre hay que corregir—
/// pero vale igual para cualquier ítem: uno pesa la milanesa después de
/// servirla, o se da cuenta de que eran dos y no una.
///
/// Los macros se reescalan **siempre contra el ítem original**, no contra el
/// resultado del tecleo anterior. Escalar sobre lo ya escalado arrastra el
/// error y con tres correcciones seguidas el número deja de tener sentido.
Future<MealItem?> showEditPortionSheet(
  BuildContext context, {
  required MealItem item,
}) => showNmSheet<MealItem>(
  context: context,
  builder: (context) => _EditPortionSheet(item: item),
);

class _EditPortionSheet extends StatefulWidget {
  const _EditPortionSheet({required this.item});

  final MealItem item;

  @override
  State<_EditPortionSheet> createState() => _EditPortionSheetState();
}

class _EditPortionSheetState extends State<_EditPortionSheet> {
  late final TextEditingController _quantity = TextEditingController(
    text: _format(widget.item.quantity),
  );
  String? _error;

  static String _format(double q) => q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toStringAsFixed(1).replaceAll('.', ',');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  double? get _parsed {
    final raw = _quantity.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null || value <= 0) return null;
    return value;
  }

  /// El ítem como quedaría con la cantidad tipeada.
  MealItem get _preview {
    final value = _parsed;
    final original = widget.item;
    if (value == null || original.quantity <= 0) return original;
    final ratio = value / original.quantity;
    return original.copyWith(
      quantity: value,
      kcal: (original.kcal * ratio).round(),
      proteinG: original.proteinG * ratio,
      carbsG: original.carbsG * ratio,
      fatG: original.fatG * ratio,
    );
  }

  void _save() {
    final value = _parsed;
    if (value == null) {
      setState(() => _error = 'Poné una cantidad mayor que cero.');
      return;
    }
    if (value > 10000) {
      setState(() => _error = 'Esa cantidad es demasiado grande.');
      return;
    }
    Navigator.of(context).pop(_preview);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final preview = _preview;

    return NmSheet(
      title: widget.item.name,
      subtitle: 'Cambiar la cantidad',
      footer: NmButton(label: 'Guardar', block: true, onPressed: _save),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NmNumberField(
            label: 'Cantidad',
            controller: _quantity,
            decimals: 1,
            suffix: widget.item.unit,
            error: _error,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: NmSpace.s5),

          // Se ve cómo quedan los números antes de guardar: corregir una
          // porción a ciegas y después revisar el total es el camino largo.
          NmCard(
            raised: true,
            child: Column(
              children: <Widget>[
                ValueRow(
                  label: 'Calorías',
                  value: Fmt.kcal(preview.kcal),
                  emphasis: true,
                ),
                const NmDivider(),
                ValueRow(
                  label: 'Proteínas',
                  value: Fmt.grams(preview.proteinG.round()),
                  muted: true,
                ),
                ValueRow(
                  label: 'Carbohidratos',
                  value: Fmt.grams(preview.carbsG.round()),
                  muted: true,
                ),
                ValueRow(
                  label: 'Grasas',
                  value: Fmt.grams(preview.fatG.round()),
                  muted: true,
                ),
              ],
            ),
          ),

          const SizedBox(height: NmSpace.s4),
          Text(
            'Los macros se ajustan a la cantidad. Original: '
            '${widget.item.portionLabel}.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
