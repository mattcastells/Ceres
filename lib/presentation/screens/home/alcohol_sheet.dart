import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../domain/calculations/alcohol.dart';
import '../../../domain/models/alcohol.dart';
import '../../components/system/buttons.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';

/// Registrar lo que se tomó.
///
/// Se carga eligiendo **un formato** y una cantidad, no tres campos: nadie sabe
/// la graduación de lo que tomó, pero todo el mundo sabe si fue una lata o un
/// chopp. El volumen y la graduación del preset viajan a la fila igual, así que
/// el número se puede recalcular y corregir después.
///
/// Las calorías se muestran con "≈" y en el color de las estimaciones, como el
/// gasto por MET: son una cuenta a partir de valores de tabla, no una medición.
Future<void> showAlcoholSheet(BuildContext context, {DateTime? date}) =>
    showNmSheet<void>(
      context: context,
      builder: (context) => _AlcoholSheet(date: date ?? today()),
    );

class _AlcoholSheet extends ConsumerStatefulWidget {
  const _AlcoholSheet({required this.date});

  final DateTime date;

  @override
  ConsumerState<_AlcoholSheet> createState() => _AlcoholSheetState();
}

class _AlcoholSheetState extends ConsumerState<_AlcoholSheet> {
  DrinkPreset _preset = drinkPresets.first;
  double _quantity = 1;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(repositoryProvider).logAlcohol(
      date: widget.date,
      type: _preset.type,
      quantity: _quantity,
      volumeMl: _preset.volumeMl,
      abvPct: _preset.abvPct,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _quantity = 1;
    });
    NmSnackbar.show(context, 'Anotado');
  }

  /// Cuántas unidades de **esa bebida** —dos copas, una lata—, que es otra
  /// cosa que la UBE y por eso no usa `Fmt.standardDrinks`.
  ///
  /// El separador sale de `Fmt` igual: escrito a mano salía "1.9" con el punto
  /// del inglés, en una pantalla donde todo el resto —las calorías, los vasos,
  /// el peso— va con coma.
  String _cantidad(double q) =>
      q == q.roundToDouble() ? Fmt.integer(q) : Fmt.decimal1(q);

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final delDia = ref.watch(repositoryProvider).alcoholOn(widget.date);
    final ube = delDia.fold(0.0, (acc, a) => acc + a.standardDrinksTotal);
    final kcal = delDia.fold(0, (acc, a) => acc + a.kcal);

    final ubeDeEsto = _preset.stdDrinks * _quantity;
    final kcalDeEsto = (_preset.kcal * _quantity).round();

    return NmSheet(
      title: 'Alcohol',
      subtitle: friendlyDay(widget.date),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Qué tomaste',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Wrap(
            spacing: NmSpace.s2,
            runSpacing: NmSpace.s2,
            children: <Widget>[
              for (final p in drinkPresets)
                NmChip(
                  label: p.label,
                  selected: p.id == _preset.id,
                  semanticsInRadioGroup: true,
                  onTap: () => setState(() => _preset = p),
                ),
            ],
          ),

          const SizedBox(height: NmSpace.s5),
          Text(
            'Cuántas',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s2),
          Row(
            children: <Widget>[
              NmIconButton(
                icon: PhosphorIcons.minus(),
                tooltip: 'Una menos',
                onPressed: _quantity <= 0.5
                    ? null
                    : () => setState(() => _quantity -= 0.5),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _cantidad(_quantity),
                    style: NmTextStyles.from(
                      NmType.display,
                      color: nm.text,
                    ).tnum,
                  ),
                ),
              ),
              NmIconButton(
                icon: PhosphorIcons.plus(),
                tooltip: 'Una más',
                onPressed: _quantity >= AlcoholLog.maxQuantity
                    ? null
                    : () => setState(() => _quantity += 0.5),
              ),
            ],
          ),

          const SizedBox(height: NmSpace.s3),
          // Las dos cifras que hacen que esto sirva de algo. La UBE porque es
          // lo único con lo que se pueden sumar una cerveza y un whisky, y las
          // calorías porque son las que no aparecen en ninguna comida.
          // "Tragos" y no "unidades de bebida estándar": es la misma palabra
          // que usa la tarjeta de Inicio, y dos vocabularios para el mismo
          // número obligan a traducir mentalmente entre dos pantallas.
          Text(
            '≈ ${Fmt.standardDrinks(ubeDeEsto)} · '
            '${Fmt.estimatedKcal(kcalDeEsto)}',
            style: NmTextStyles.from(NmType.caption, color: nm.caution).tnum,
          ),

          const SizedBox(height: NmSpace.s5),
          NmButton(
            label: 'Anotar',
            block: true,
            loading: _saving,
            onPressed: _save,
          ),

          if (delDia.isNotEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s5),
            Text(
              'En el día: ≈ ${Fmt.standardDrinks(ube)} · '
              '${Fmt.estimatedKcal(kcal)}',
              style: NmTextStyles.from(
                NmType.caption,
                color: nm.textMuted,
              ).tnum,
            ),
            const SizedBox(height: NmSpace.s2),
            for (final log in delDia)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  log.label,
                  style: NmTextStyles.from(NmType.body, color: nm.text),
                ),
                subtitle: Text(
                  Fmt.estimatedKcal(log.kcal),
                  style: NmTextStyles.from(
                    NmType.caption,
                    color: nm.textMuted,
                  ).tnum,
                ),
                trailing: NmIconButton(
                  icon: PhosphorIcons.trash(),
                  tooltip: 'Borrar',
                  onPressed: () => ref
                      .read(repositoryProvider)
                      .deleteAlcohol(log.id),
                ),
              ),
          ],

          const SizedBox(height: NmSpace.s2),
          Text(
            'Un trago es una unidad de bebida estándar: 10 g de alcohol puro, '
            'que es lo único con lo que se pueden sumar una cerveza y un '
            'whisky. Las calorías son una estimación y van aparte de las '
            'comidas: sumarlas ahí escondería de dónde salieron.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
