import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/meal.dart';
import '../../../domain/models/meal_suggestion.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import 'meal_draft.dart';

const _uuid = Uuid();

/// Qué puedo comer con lo que me queda.
///
/// Se le pide al modelo **tres** platos que entren en las calorías que quedan
/// del día, con sus ingredientes y su receta.
///
/// Dos cosas que la pantalla no negocia:
///
/// - **Ninguna opción se pasa del presupuesto.** Se comprueba en la función y
///   otra vez en el cliente (`MealSuggestionsClient.parse`); lo que no cierra
///   nunca llega hasta acá. Ofrecerle a alguien un plato que no entra no es una
///   sugerencia imprecisa: es la app diciéndole que puede comer algo que no
///   puede.
/// - **Es una estimación y lo dice.** Los gramos salen del mismo modelo que
///   estima una foto, con la misma validación. Cargar una sugerencia guarda una
///   comida `aiText`, que es lo que es: números estimados, no pesados.
class SuggestionsScreen extends ConsumerStatefulWidget {
  const SuggestionsScreen({this.slot, super.key});

  /// El momento del día desde el que se entró, si se entró desde uno. Le da
  /// contexto al modelo —no es lo mismo desayuno que cena— y es a dónde va la
  /// comida si se carga.
  final MealSlot? slot;

  @override
  ConsumerState<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends ConsumerState<SuggestionsScreen> {
  bool _loading = false;
  AppError? _error;
  List<MealSuggestion>? _options;

  /// El presupuesto con el que se pidieron las opciones que están en pantalla.
  ///
  /// Se congela al pedir y no se vuelve a leer del día: si mientras tanto se
  /// registra otra comida, las barras seguirían dibujándose contra un número
  /// distinto del que se usó para pedirlas y dirían cualquier cosa.
  int _budget = 0;

  /// Si el presupuesto lo puso la persona en vez de salir del día.
  ///
  /// "Lo que me queda" es la pregunta de la noche, cuando lo que importa es no
  /// pasarse. Pero también se cocina para el mediodía teniendo el día entero
  /// por delante, y ahí el número que interesa es el del plato —"algo de 600"—
  /// y no el saldo. Con un solo modo, la segunda pregunta no se podía hacer.
  bool _custom = false;

  /// De qué modo salieron las opciones que están en pantalla. Va aparte de
  /// [_custom] por lo mismo que [_budget]: el texto tiene que describir lo que
  /// se ve, no lo que está elegido ahora.
  bool _shownIsCustom = false;

  final TextEditingController _target = TextEditingController();

  // Sin `initState` que pida nada, y eso es lo importante de esta pantalla.
  //
  // Hasta ahora entrar acá disparaba una consulta al modelo sola, antes de que
  // nadie pidiera nada. Estaba mal por tres motivos distintos y cualquiera de
  // los tres alcanza: gastaba una de las 20 consultas del día con solo abrir
  // la pantalla —incluso para mirar, o para entrar sin querer—; le pegaba al
  // proveedor con el saldo que hubiera en ese instante, que casi nunca es el
  // número con el que uno quiere buscar; y hacía imposible elegir "Otro
  // número" sin haber gastado antes una búsqueda que no se pidió.
  //
  // La regla, ahora: **nada sale para Gemini hasta que alguien toca el botón.**

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  int get _remaining {
    final balance = ref.read(todaySummaryProvider).balance;
    return balance.remainingKcal;
  }

  /// Con cuántas calorías se piden las opciones.
  int get _presupuesto => _custom
      ? int.tryParse(_target.text.trim()) ?? 0
      : _remaining;

  /// Si lo que está en pantalla salió de pedir exactamente esto.
  ///
  /// Cuando no —porque todavía no se pidió nada, porque se cambió de modo, o
  /// porque se comió algo y el saldo se movió—, hay que decir con qué se
  /// buscaría al tocar el botón. Cuando sí, decirlo dos veces es ruido.
  bool get _alDia =>
      _budget > 0 && _shownIsCustom == _custom && _budget == _presupuesto;

  /// Las restricciones del perfil, para decirlas en pantalla. Quien las aplica
  /// es el servidor; acá solo se muestran.
  List<String> get _restricciones {
    final profile = ref.watch(profileProvider);
    return <String>[
      for (final flag in profile.dietaryFlags) flag.label.toLowerCase(),
      if (profile.dietaryNote.trim().isNotEmpty) 'lo que anotaste',
    ];
  }

  Future<void> _pedir() async {
    if (!mounted) return;
    final summary = ref.read(todaySummaryProvider);
    final restante = _presupuesto;
    final proteina = summary.macros.protein;

    setState(() {
      _loading = true;
      _error = null;
      _options = null;
      _budget = restante;
      _shownIsCustom = _custom;
    });

    try {
      final options = await ref
          .read(repositoryProvider)
          .suggestMeals(
            remainingKcal: restante,
            slot: widget.slot,
            // Si le falta proteína para el objetivo del día, que las opciones
            // apunten para ahí. Es el único macro que se manda: es el que la
            // gente persigue y el que más cambia qué plato conviene.
            remainingProteinG: (proteina.target - proteina.current).round(),
          );
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } on Object catch (error) {
      // `on AppError` solo no alcanza y ya nos costó una vez: un `TypeError`
      // **no es una `Exception`**, así que una respuesta con forma inesperada
      // se escapaba de todos los catch y dejaba `_loading` en true para
      // siempre. En pantalla: "Buscando opciones que entren…" girando sin
      // error, y sin el botón de refrescar, que solo se dibuja cuando no está
      // cargando.
      if (!mounted) return;
      setState(() {
        _error = AppError(
          code: ApiErrorCode.server,
          message:
              'No pudimos leer las sugerencias. Probá de nuevo en un rato.',
          requestId: error.toString(),
        );
        _loading = false;
      });
    }
  }

  /// Carga la sugerencia como una comida, abriendo el formulario con todo
  /// puesto.
  ///
  /// No se guarda de una: se abre el borrador para que se pueda cambiar la
  /// cantidad, sacar un ingrediente o mandarla a otro momento del día antes de
  /// que entre al historial. Lo que el modelo propuso es un punto de partida, y
  /// guardarlo sin mirar sería meter números estimados sin que nadie los haya
  /// aceptado.
  void _cargar(MealSuggestion option) {
    var position = 0;
    ref
        .read(mealDraftProvider.notifier)
        .start(
          slot: widget.slot ?? _slotDeAhora(),
          date: ref.read(selectedDateProvider),
          // `aiText` y no `manual`: estos gramos los estimó el modelo, igual
          // que los de una descripción escrita. Que el origen del dato diga lo
          // que pasó es lo que después permite mirar el historial y saber qué
          // se pesó y qué se estimó.
          source: MealSource.aiText,
          items: <MealItem>[
            for (final i in option.items)
              MealItem(
                id: _uuid.v4(),
                name: i.name,
                quantity: i.quantity,
                unit: i.unit,
                kcal: i.kcal,
                proteinG: i.proteinG,
                carbsG: i.carbsG,
                fatG: i.fatG,
                position: position++,
              ),
          ],
        );
    context.pushReplacement(Routes.mealNew);
  }

  /// El momento del día que corresponde a la hora, para cuando se entró desde
  /// el menú general y no desde un slot.
  MealSlot _slotDeAhora() {
    final hour = DateTime.now().hour;
    if (hour < 11) return MealSlot.breakfast;
    if (hour < 16) return MealSlot.lunch;
    if (hour < 19) return MealSlot.snack;
    return MealSlot.dinner;
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    // Sin el botón de refrescar de la barra: ahora que el de abajo dice
    // "Buscar otras", eran dos puertas a lo mismo, y la de arriba —un ícono
    // circular al lado del título— es la que más fácil se toca sin querer. Cada
    // toque es una consulta al modelo y una unidad de las 20 del día.
    return NmScreen(
      title: '¿Qué como?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),

          NmSegmentedControl<bool>(
            options: <(bool, String)>[
              (false, 'Lo que me queda'),
              (true, 'Otro número'),
            ],
            value: _custom,
            onChanged: (custom) {
              setState(() {
                _custom = custom;
                // El saldo del día como punto de partida: casi siempre lo que
                // se quiere es correrlo un poco, no escribirlo de cero.
                if (custom && _target.text.trim().isEmpty && _remaining > 0) {
                  _target.text = '$_remaining';
                }
              });
              // Y nada más: cambiar de modo **no** busca. Antes volver a "lo
              // que me queda" disparaba una consulta sola, con el argumento de
              // que el número ya se sabía. Que se sepa el número no quiere
              // decir que se haya pedido nada, y cada tirada del modelo la
              // paga la cuota del día.
            },
          ),
          const SizedBox(height: NmSpace.s4),

          if (_custom) ...<Widget>[
            NmTextField(
              label: 'Calorías del plato',
              controller: _target,
              suffix: 'kcal',
              hint: '600',
              keyboardType: TextInputType.number,
              maxLength: 4,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_presupuesto > 0) _pedir();
              },
            ),
            const SizedBox(height: NmSpace.s3),
          ] else if (!_alDia) ...<Widget>[
            // Con qué se buscaría al tocar el botón. En "Otro número" no hace
            // falta —el campo lo dice—, y cuando lo que está en pantalla salió
            // justo de este presupuesto tampoco: ahí habla el texto de abajo,
            // que describe lo que se ve.
            Text(
              _remaining > 0
                  ? 'Buscamos con las $_remaining kcal que te quedan hoy.'
                  : 'Hoy no te quedan calorías: elegí "Otro número" para '
                        'buscar igual.',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s3),
          ],

          // El botón está en los dos modos, y es la única puerta al modelo.
          //
          // Antes vivía solo dentro de "Otro número", porque el otro modo
          // buscaba solo. Ahora que no busca nada solo, sin este botón ahí no
          // habría forma de buscar.
          NmButton(
            label: _options == null ? 'Buscar opciones' : 'Buscar otras',
            block: true,
            icon: PhosphorIcons.magnifyingGlass(),
            loading: _loading,
            onPressed: _presupuesto > 0 && !_loading ? _pedir : null,
          ),
          const SizedBox(height: NmSpace.s5),

          // Con qué presupuesto salió **el pedido que está en pantalla**, que
          // no es necesariamente el que está elegido ahora: se puede buscar con
          // 600 y después escribir 900 sin volver a buscar.
          //
          // Se dibuja apenas sale el pedido y no cuando llegan las opciones: si
          // el pedido falla, saber con cuánto se pidió es justamente lo que
          // hace entendible el error.
          if (_budget > 0) ...<Widget>[
            Text(
              _shownIsCustom
                  ? 'Tres platos de hasta $_budget kcal.'
                  : 'Tres platos que entran en las $_budget kcal que te '
                        'quedaban hoy.',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s5),
          ],

          // Que se vea que las restricciones están puestas.
          //
          // Sin esto no hay forma de distinguir "respeta que soy celíaco" de
          // "se olvidó", y esa duda obliga a leer la lista de ingredientes de
          // las tres opciones con lupa — que es exactamente el trabajo que la
          // pantalla venía a sacarse de encima.
          if (_restricciones.isNotEmpty) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(
                  PhosphorIcons.plant(),
                  size: NmIconSize.sm,
                  color: nm.textMuted,
                ),
                const SizedBox(width: NmSpace.s2),
                Expanded(
                  child: Text(
                    'Sin lo que no comés: ${_restricciones.join(', ')}.',
                    style: NmTextStyles.from(
                      NmType.caption,
                      color: nm.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NmSpace.s5),
          ],

          if (_loading)
            const _Buscando()
          else if (_error != null)
            ErrorState(
              message: _error!.message,
              code: _error!.code.wire,
              // Un presupuesto muy chico no se arregla reintentando: no hay
              // nada que pedir de nuevo.
              onRetry: _error!.code == ApiErrorCode.budgetTooLow ? null : _pedir,
            )
          // Lo primero que se ve al entrar. Es una pantalla que **no hizo
          // nada** todavía, y tiene que verse así: un spinner acá era la app
          // gastando cuota por su cuenta y haciéndolo pasar por normal.
          else if (_options == null)
            const EmptyState(
              icon: Icons.restaurant_menu_outlined,
              title: 'Decime con cuánto y busco',
              body: 'Elegí el presupuesto y tocá "Buscar opciones". Cada '
                  'búsqueda le pregunta al modelo, así que sale cuando vos '
                  'querés y no antes.',
            )
          else if (_options!.isEmpty)
            const EmptyState(
              icon: Icons.no_food_outlined,
              title: 'Esta vez no salió nada',
              body: 'Ninguna opción cerró con ese presupuesto. Probá de nuevo: '
                  'el modelo no siempre contesta lo mismo.',
            )
          else
            for (final option in _options!)
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s4),
                child: _SuggestionCard(
                  option: option,
                  budgetKcal: _budget,
                  onLoad: () => _cargar(option),
                ),
              ),

          if (_options != null && _options!.isNotEmpty) ...<Widget>[
            const SizedBox(height: NmSpace.s2),
            const InfoNote(
              text: 'Los gramos son una estimación, igual que los de la foto: '
                  'sirven para orientarse, no para pesar. Al cargar una podés '
                  'cambiar lo que quieras antes de guardarla.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Buscando extends StatelessWidget {
  const _Buscando();

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const NmSpinner(size: 20),
            const SizedBox(width: NmSpace.s3),
            Text(
              'Buscando opciones que entren…',
              style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            ),
          ],
        ),
        const SizedBox(height: NmSpace.s6),
        const SkeletonList(rows: 3, withAvatar: false),
      ],
    );
  }
}

/// Una de las tres opciones: qué es, cuánto ocupa del día, con qué se hace y
/// cómo.
class _SuggestionCard extends StatefulWidget {
  const _SuggestionCard({
    required this.option,
    required this.budgetKcal,
    required this.onLoad,
  });

  final MealSuggestion option;
  final int budgetKcal;
  final VoidCallback onLoad;

  @override
  State<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends State<_SuggestionCard> {
  /// Los ingredientes y la receta arrancan plegados.
  ///
  /// Tres recetas abiertas a la vez son tres pantallas de scroll para elegir
  /// entre tres cosas. Lo que se necesita para decidir —qué es y cuánto ocupa—
  /// entra sin abrir nada.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final o = widget.option;
    final sobra = widget.budgetKcal - o.kcal;

    return NmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  o.name,
                  style: NmTextStyles.from(NmType.h4, color: nm.text),
                ),
              ),
              const SizedBox(width: NmSpace.s3),
              Text(
                '${o.kcal} kcal',
                style: NmTextStyles.from(NmType.h4, color: nm.accent).tnum,
              ),
            ],
          ),

          const SizedBox(height: NmSpace.s2),
          Row(
            children: <Widget>[
              if (o.minutes != null) ...<Widget>[
                Icon(PhosphorIcons.clock(), size: 14, color: nm.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${o.minutes} min',
                  style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
                ),
                const SizedBox(width: NmSpace.s3),
              ],
              Expanded(
                child: Text(
                  'P ${o.proteinG.round()} · C ${o.carbsG.round()} · '
                  'G ${o.fatG.round()}',
                  style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
                ),
              ),
            ],
          ),

          const SizedBox(height: NmSpace.s3),
          // Cuánto del día ocupa. Lo que importa no es el número solo: es que
          // se vea que **sobra**, que es la promesa de la pantalla.
          ClipRRect(
            borderRadius: NmRadius.brSm,
            child: LinearProgressIndicator(
              value: o.fractionOf(widget.budgetKcal),
              minHeight: 6,
              backgroundColor: nm.surfaceRaised,
              valueColor: AlwaysStoppedAnimation<Color>(nm.accent),
            ),
          ),
          const SizedBox(height: NmSpace.s2),
          Text(
            sobra <= 0
                ? 'Usa todo lo que te queda'
                : 'Te quedarían $sobra kcal',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),

          if (_open) ...<Widget>[
            const SizedBox(height: NmSpace.s5),
            const NmSectionHeader(title: 'Ingredientes'),
            for (final i in o.items)
              ValueRow(
                label: i.name,
                caption: '${_cantidad(i.quantity)} ${i.unit}',
                value: '${i.kcal} kcal',
              ),

            const SizedBox(height: NmSpace.s5),
            const NmSectionHeader(title: 'Cómo se hace'),
            for (var n = 0; n < o.steps.length; n++)
              Padding(
                padding: const EdgeInsets.only(bottom: NmSpace.s2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${n + 1}.',
                        style: NmTextStyles.from(
                          NmType.bodySm,
                          color: nm.textMuted,
                        ).tnum,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        o.steps[n],
                        style: NmTextStyles.from(NmType.bodySm, color: nm.text),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              NmButton.ghost(
                label: _open ? 'Ocultar' : 'Ver la receta',
                onPressed: () => setState(() => _open = !_open),
              ),
              const Spacer(),
              NmButton.secondary(
                label: 'Cargar esta',
                onPressed: widget.onLoad,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// "150" y no "150.0"; "1,5" cuando de verdad hay una fracción.
  String _cantidad(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
}
