import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/config/supabase_config.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/models/meal.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../providers/app_providers.dart';
import 'meal_draft.dart';

const _uuid = Uuid();

/// Si esta compilación puede estimar con IA: hace falta la bandera y un
/// servidor al que preguntarle.
///
/// Es un provider y no una constante para que los tests puedan encender la IA
/// sin servidor: con la constante, todo lo que se estima en el formulario de
/// comida quedaba fuera del alcance de un test de widget.
final mealAiAvailableProvider = Provider<bool>(
  (ref) => FeatureFlags.aiPhotoAnalysis && SupabaseConfig.isConfigured,
);

/// "Sumar un ítem": una línea para agregarle algo al plato sin salir de él.
///
/// Lo que faltaba era el camino corto. Agregarle "una feta de queso" a una
/// comida ya cargada obligaba a buscarla en el catálogo —donde una feta de
/// queso de máquina no está— o a ir a "Describir", esperar otra pantalla y
/// volver. Acá se escribe, se toca el más, y el ítem aparece en la lista con
/// el total de abajo ya sumado. Se revisa y se guarda como siempre: nada se
/// guarda solo.
///
/// Manda **solo lo escrito**, sin los ítems del plato. La función acepta la
/// comida actual, pero en ese modo es un recálculo: devuelve el plato entero y
/// puede retocar lo que ya estaba. Para sumar un ítem no hace falta, y sin
/// contexto el modelo no tiene nada que volver a agregar.
class QuickAddItemField extends ConsumerStatefulWidget {
  const QuickAddItemField({super.key});

  @override
  ConsumerState<QuickAddItemField> createState() => _QuickAddItemFieldState();
}

class _QuickAddItemFieldState extends ConsumerState<QuickAddItemField> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _busy = false;
  String? _error;

  /// Si el último error fue de la estimación (no de lo escrito): ahí se ofrece
  /// cargarlo a mano en vez de dejar a la persona reintentando.
  bool _offerManual = false;

  /// El mismo techo que acepta la función.
  static const int _maxLength = 200;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error == null) return;
    setState(() {
      _error = null;
      _offerManual = false;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final text = _text.text.trim();
    // El servidor pide tres letras: "pan" entra, "a" no.
    if (text.length < 3) {
      setState(() {
        _error = 'Escribí qué querés sumar.';
        _offerManual = false;
      });
      return;
    }

    // Sin servidor no hay a quién preguntarle: lo escrito pasa derecho a la
    // carga a mano, con el nombre ya puesto.
    if (!ref.read(mealAiAvailableProvider)) {
      await _manual(text);
      return;
    }

    final draft = ref.read(mealDraftProvider);
    if (draft == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _offerManual = false;
    });

    try {
      final analysis = await ref
          .read(repositoryProvider)
          .analyzeText(description: text);
      if (!mounted) return;

      final items = <MealItem>[
        for (var i = 0; i < analysis.items.length; i++)
          MealItem.fromAnalysis(
            analysis.items[i],
            id: _uuid.v4(),
            position: draft.items.length + i,
          ),
      ];
      if (items.isEmpty) {
        _fail(_noFood);
        return;
      }

      ref
          .read(mealDraftProvider.notifier)
          .appendEstimatedItems(
            draftId: draft.id,
            items: items,
            aiAnalysisId: analysis.id,
          );
      setState(() => _busy = false);
      // El campo queda vacío y con el foco: lo común es sumar dos o tres
      // cosas seguidas ("pan", "manteca").
      _text.clear();
    } on AppError catch (error) {
      if (!mounted) return;
      _fail(_shortMessage(error));
    } on Object {
      // Cualquier otra cosa —una respuesta con forma rara— no puede dejar el
      // campo girando para siempre.
      if (!mounted) return;
      _fail(_generic);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = message;
      _offerManual = true;
    });
  }

  static const String _noFood =
      'No lo reconocimos. Probá con el nombre y la cantidad.';
  static const String _generic =
      'No pudimos calcularlo. Probá de nuevo o cargalo a mano.';

  /// Una línea. Los mensajes del servidor están pensados para una pantalla
  /// entera y acá hay lugar para una frase debajo del campo.
  static String _shortMessage(AppError error) => switch (error.code) {
    ApiErrorCode.aiNoFood => _noFood,
    ApiErrorCode.offline => 'Sin conexión. Probá de nuevo.',
    ApiErrorCode.upstreamTimeout => 'Tardó demasiado. Probá de nuevo.',
    ApiErrorCode.quotaExceeded =>
      'Llegaste al límite de estimaciones de hoy. Cargalo a mano.',
    ApiErrorCode.aiRateLimited ||
    ApiErrorCode.aiOverloaded => 'El servicio está saturado. Probá en un rato.',
    ApiErrorCode.providerUnavailable =>
      'La estimación no está disponible. Cargalo a mano.',
    _ => _generic,
  };

  /// La carga a mano, con lo escrito como nombre.
  Future<void> _manual(String name) async {
    if (!mounted) return;
    final item = await showManualItemSheet(context, initialName: name);
    if (item == null || !mounted) return;
    final controller = ref.read(mealDraftProvider.notifier);
    final draft = ref.read(mealDraftProvider);
    if (draft == null) return;
    controller.addItem(item.copyWith(position: draft.items.length));
    _text.clear();
    _clearError();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NmTextField(
          label: 'Sumar un ítem',
          controller: _text,
          focusNode: _focus,
          hint: 'una feta de queso, 2 cucharadas de aceite',
          maxLength: _maxLength,
          enabled: !_busy,
          error: _error,
          helper: _busy ? 'Calculando…' : null,
          textInputAction: TextInputAction.done,
          onChanged: (_) => _clearError(),
          onSubmitted: (_) => _submit(),
          suffixIcon: _busy
              ? const Padding(
                  padding: EdgeInsets.all(NmSpace.s3),
                  child: NmSpinner(size: 20),
                )
              : NmIconButton(
                  icon: PhosphorIcons.plus(),
                  tooltip: 'Sumar',
                  size: NmIconSize.md,
                  onPressed: _submit,
                ),
        ),
        if (_error != null && _offerManual)
          Align(
            alignment: Alignment.centerLeft,
            child: NmButton.ghost(
              label: 'Cargar a mano',
              onPressed: () => _manual(_text.text.trim()),
            ),
          ),
      ],
    );
  }
}

/// Un ítem con sus números escritos a mano: nombre, calorías y, si se saben,
/// los macros.
///
/// Es la salida sin IA del campo "Sumar un ítem" —sin servidor o
/// una estimación que falló— y por eso arranca con lo que ya se escribió como
/// nombre. No crea un alimento en el catálogo: es un ítem de **esta** comida,
/// como lo que estima la IA. Para guardarlo y reusarlo está "Crear alimento".
Future<MealItem?> showManualItemSheet(
  BuildContext context, {
  String initialName = '',
}) => showNmSheet<MealItem>(
  context: context,
  builder: (context) => _ManualItemSheet(initialName: initialName),
);

class _ManualItemSheet extends StatefulWidget {
  const _ManualItemSheet({required this.initialName});

  final String initialName;

  @override
  State<_ManualItemSheet> createState() => _ManualItemSheetState();
}

class _ManualItemSheetState extends State<_ManualItemSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController();
  final TextEditingController _carbs = TextEditingController();
  final TextEditingController _fat = TextEditingController();

  String? _nameError;
  String? _kcalError;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _name,
      _kcal,
      _protein,
      _carbs,
      _fat,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _num(TextEditingController c) {
    final raw = c.text.replaceAll(',', '.').trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  /// Los macros vacíos son cero; uno fuera de rango invalida el ítem.
  static double? _macro(TextEditingController c) {
    final value = _num(c) ?? 0;
    return value < 0 || value > 500 ? null : value;
  }

  void _save() {
    final name = _name.text.trim();
    final kcal = _num(_kcal);
    final protein = _macro(_protein);
    final carbs = _macro(_carbs);
    final fat = _macro(_fat);

    setState(() {
      _nameError = name.isEmpty ? 'Poné un nombre.' : null;
      _kcalError = kcal == null || kcal < 0 || kcal > 5000
          ? 'Poné las calorías, de 0 a 5000.'
          : protein == null || carbs == null || fat == null
          ? 'Los macros van de 0 a 500 g.'
          : null;
    });
    if (_nameError != null || _kcalError != null) return;

    Navigator.of(context).pop(
      MealItem(
        id: _uuid.v4(),
        name: name.length > 120 ? name.substring(0, 120) : name,
        quantity: 1,
        unit: 'porción',
        kcal: kcal!.round(),
        proteinG: protein!,
        carbsG: carbs!,
        fatG: fat!,
        position: 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NmSheet(
      title: 'Cargar a mano',
      footer: NmButton(label: 'Sumar a la comida', block: true, onPressed: _save),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          NmTextField(
            label: 'Nombre',
            controller: _name,
            maxLength: 120,
            error: _nameError,
            onChanged: (_) {
              if (_nameError != null) setState(() => _nameError = null);
            },
          ),
          const SizedBox(height: NmSpace.s4),
          NmNumberField(
            label: 'Calorías',
            controller: _kcal,
            suffix: 'kcal',
            autofocus: widget.initialName.isNotEmpty,
            error: _kcalError,
            onChanged: (_) {
              if (_kcalError != null) setState(() => _kcalError = null);
            },
          ),
          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: NmNumberField(
                  label: 'Proteínas',
                  controller: _protein,
                  decimals: 1,
                  suffix: 'g',
                  hint: '0',
                ),
              ),
              const SizedBox(width: NmSpace.s2),
              Expanded(
                child: NmNumberField(
                  label: 'Carbos',
                  controller: _carbs,
                  decimals: 1,
                  suffix: 'g',
                  hint: '0',
                ),
              ),
              const SizedBox(width: NmSpace.s2),
              Expanded(
                child: NmNumberField(
                  label: 'Grasas',
                  controller: _fat,
                  decimals: 1,
                  suffix: 'g',
                  hint: '0',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
