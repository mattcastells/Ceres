import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/calculations/macros.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/food.dart';
import '../../../domain/models/meal.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/food_widgets.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../meal/meal_draft.dart';

const _uuid = Uuid();

/// S-16 · Buscar alimento. Encontrar el alimento en ≤ 3 interacciones.
class FoodSearchScreen extends ConsumerStatefulWidget {
  const FoodSearchScreen({this.initialQuery, super.key});

  final String? initialQuery;

  @override
  ConsumerState<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

enum _SearchTab { recent, favorites, own }

class _FoodSearchScreenState extends ConsumerState<FoodSearchScreen> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery ?? '',
  );
  Timer? _debounce;
  _SearchTab _tab = _SearchTab.recent;
  List<Food> _results = <Food>[];
  bool _searching = false;
  String? _remoteError;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Abre una pantalla que puede terminar agregando el alimento al borrador y,
  /// si lo agregó, se cierra también.
  ///
  /// El buscador es una escala, no un destino: quien llegó acá venía armando
  /// una comida y a eso vuelve. Cada pantalla se cierra sola en vez de que la
  /// última cuente cuántas hay arriba del borrador, que es lo que rompía el
  /// escáner abierto desde el propio borrador.
  Future<void> _openAndCloseIfAdded(String location) async {
    final added = await context.push<bool>(location);
    if (!mounted) return;
    if (added == true) context.pop(true);
  }

  /// Búsqueda local inmediata y, en paralelo, el catálogo externo con
  /// debounce de 350 ms y mínimo 2 caracteres (F-04 paso 3).
  void _onQueryChanged(String raw) {
    _debounce?.cancel();
    final query = raw.trim();

    if (query.length < 2) {
      setState(() {
        _results = <Food>[];
        _searching = false;
        _remoteError = null;
      });
      return;
    }

    setState(() {
      _results = ref.read(repositoryProvider).search(query);
      _searching = true;
      _remoteError = null;
    });

    _debounce = Timer(const Duration(milliseconds: 350), () => _searchOnline(query));
  }

  Future<void> _searchOnline(String query) async {
    final repo = ref.read(repositoryProvider);
    try {
      final remote = await repo.searchOnline(query);
      // Si la persona siguió escribiendo, este resultado ya no corresponde.
      if (!mounted || _query.text.trim() != query) return;

      // Lo local primero (lo tuyo y lo ya usado), después lo del catálogo.
      final merged = <String, Food>{
        for (final food in repo.search(query)) food.id: food,
      };
      for (final food in remote) {
        merged.putIfAbsent(food.id, () => food);
      }
      setState(() {
        _results = merged.values.toList();
        _searching = false;
      });
    } on AppError catch (error) {
      if (!mounted || _query.text.trim() != query) return;
      setState(() {
        _remoteError = error.message;
        _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final hasQuery = _query.text.trim().length >= 2;

    final tabResults = switch (_tab) {
      _SearchTab.recent => repo.recent(),
      _SearchTab.favorites => repo.favorites(),
      _SearchTab.own => repo.ownFoods(),
    };
    final visible = hasQuery ? _results : tabResults;

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: const NmModalHeader(title: 'Buscar alimento'),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.screenPadding,
                NmSpace.s3,
                context.screenPadding,
                NmSpace.s3,
              ),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _onQueryChanged,
                style: NmTextStyles.from(NmType.body, color: nm.text),
                decoration: InputDecoration(
                  hintText: 'Buscá un alimento',
                  prefixIcon: Icon(
                    PhosphorIcons.magnifyingGlass(),
                    size: NmIconSize.md,
                    color: nm.textMuted,
                  ),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar',
                          onPressed: () {
                            _query.clear();
                            _onQueryChanged('');
                            setState(() {});
                          },
                          icon: Icon(PhosphorIcons.x(), size: NmIconSize.md),
                        ),
                ),
              ),
            ),
            if (!hasQuery)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.screenPadding,
                ),
                child: NmSegmentedControl<_SearchTab>(
                  options: const <(_SearchTab, String)>[
                    (_SearchTab.recent, 'Recientes'),
                    (_SearchTab.favorites, 'Favoritos'),
                    (_SearchTab.own, 'Mis alimentos'),
                  ],
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                ),
              ),
            if (_remoteError != null && hasQuery)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  context.screenPadding,
                  NmSpace.s3,
                  context.screenPadding,
                  0,
                ),
                child: InfoNote(
                  tone: NmNoteTone.caution,
                  text: _remoteError!,
                  action: 'Reintentar',
                  onAction: () {
                    setState(() {
                      _searching = true;
                      _remoteError = null;
                    });
                    _searchOnline(_query.text.trim());
                  },
                ),
              ),
            Expanded(
              // El skeleton solo cuando todavía no hay nada que mostrar: si ya
              // hay resultados locales, se muestran mientras llega el catálogo.
              child: _searching && visible.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(context.screenPadding),
                      child: const SkeletonList(rows: 6, withAvatar: false),
                    )
                  : visible.isEmpty
                  ? EmptyState(
                      icon: PhosphorIcons.magnifyingGlass(),
                      title: hasQuery
                          ? 'No encontramos ese alimento'
                          : switch (_tab) {
                              _SearchTab.recent =>
                                'Todavía no usaste ningún alimento',
                              _SearchTab.favorites => 'Sin favoritos',
                              _SearchTab.own => 'Sin alimentos propios',
                            },
                      body: hasQuery
                          ? 'Podés crearlo con tus propios valores o sacarle '
                                'una foto a la comida.'
                          : switch (_tab) {
                              _SearchTab.recent =>
                                'Los alimentos que uses van a aparecer acá.',
                              _SearchTab.favorites =>
                                'Marcá con la estrella los que uses seguido.',
                              _SearchTab.own =>
                                'Los que crees a mano van a aparecer acá.',
                            },
                      // Sin buscar, "Crear alimento" ya está en la barra de
                      // abajo: repetirlo acá hacía que los dos botones se
                      // pisaran en pantalla.
                      primaryLabel: hasQuery ? 'Crear alimento' : null,
                      onPrimary: hasQuery
                          ? () => _openAndCloseIfAdded(Routes.foodNew)
                          : null,
                      secondaryLabel: hasQuery ? 'Sacar una foto' : null,
                      onSecondary: hasQuery
                          ? () => context.push(Routes.photoCapture)
                          : null,
                    )
                  : Semantics(
                      liveRegion: true,
                      label: '${visible.length} resultados',
                      child: ListView.separated(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.screenPadding,
                          vertical: NmSpace.s3,
                        ),
                        itemCount: visible.length,
                        separatorBuilder: (_, _) => const NmDivider(),
                        itemBuilder: (context, index) => StaggeredItem(
                          index: index,
                          child: FoodResultRow(
                            food: visible[index],
                            onTap: () => _openAndCloseIfAdded(
                              Routes.food(visible[index].id),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.screenPadding,
                0,
                context.screenPadding,
                NmSpace.s4,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: NmButton.secondary(
                      label: 'Crear alimento',
                      onPressed: () => _openAndCloseIfAdded(Routes.foodNew),
                    ),
                  ),
                  const SizedBox(width: NmSpace.s2),
                  Expanded(
                    child: NmButton.secondary(
                      label: 'Escanear',
                      onPressed: () => _openAndCloseIfAdded(Routes.foodScan),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// S-17 · Detalle de alimento con selector de porción.
class FoodDetailScreen extends ConsumerStatefulWidget {
  const FoodDetailScreen({required this.foodId, super.key});

  final String foodId;

  @override
  ConsumerState<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends ConsumerState<FoodDetailScreen> {
  final TextEditingController _quantity = TextEditingController(text: '1');
  FoodPortion? _portion;

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  double get _multiplier {
    final raw = double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 0;
    final food = ref.read(repositoryProvider).byId(widget.foodId);
    if (food == null) return raw;
    final portion = _portion;
    if (portion == null) return raw;
    // El múltiplo se expresa contra la porción de referencia del alimento.
    return raw * portion.grams / (food.servingSize <= 0 ? 1 : food.servingSize);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final food = repo.byId(widget.foodId);

    if (food == null) {
      return NmScreen(
        title: 'Alimento',
        child: ErrorState(
          message: 'No encontramos ese alimento.',
          onRetry: () => context.pop(),
          retryLabel: 'Volver',
        ),
      );
    }

    final portions = food.portions.isEmpty
        ? <FoodPortion>[
            FoodPortion(label: food.servingUnit, grams: food.servingSize),
          ]
        : food.portions;
    _portion ??= portions.first;

    final multiplier = _multiplier;
    final kcal = (food.kcal * multiplier).round();
    final valid = multiplier > 0 && multiplier <= 10000;

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: AppBar(
        title: Text(food.name),
        actions: <Widget>[
          IconButton(
            tooltip: food.isFavorite ? 'Quitar de favoritos' : 'Favorito',
            onPressed: () => repo.toggleFoodFavorite(food.id),
            icon: Icon(
              food.isFavorite
                  ? PhosphorIcons.star(PhosphorIconsStyle.fill)
                  : PhosphorIcons.star(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(context.screenPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: NmLayout.contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (food.brand != null) ...<Widget>[
                              Text(
                                food.brand!,
                                style: NmTextStyles.from(
                                  NmType.bodySm,
                                  color: nm.textMuted,
                                ),
                              ),
                              const SizedBox(width: NmSpace.s2),
                            ],
                            NmTag(
                              label: 'Origen: ${food.source.label}',
                              variant: NmTagVariant.outline,
                            ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),
                        Text(
                          'Porción',
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ),
                        ),
                        const SizedBox(height: NmSpace.s2),
                        Wrap(
                          spacing: NmSpace.s2,
                          runSpacing: NmSpace.s2,
                          children: <Widget>[
                            for (final portion in portions)
                              NmChip(
                                label: portion.label,
                                subtitle: '${portion.grams.round()} g',
                                selected: portion.label == _portion?.label,
                                onTap: () => setState(() => _portion = portion),
                              ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),
                        NmNumberField(
                          label: 'Cantidad',
                          controller: _quantity,
                          decimals: 2,
                          error: valid ? null : 'La cantidad va de 0 a 10.000.',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: NmSpace.s6),
                        NmCard(
                          child: NutritionTable(
                            food: food,
                            quantity: multiplier,
                          ),
                        ),
                        if (food.nutrientWarning) ...<Widget>[
                          const SizedBox(height: NmSpace.s4),
                          const InfoNote(
                            tone: NmNoteTone.caution,
                            text: 'Los macros de este alimento no coinciden '
                                'del todo con sus calorías.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                context.screenPadding,
                NmSpace.s3,
                context.screenPadding,
                NmSpace.s4 + MediaQuery.paddingOf(context).bottom,
              ),
              decoration: BoxDecoration(
                color: nm.surface,
                border: Border(top: BorderSide(color: nm.divider)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      Fmt.kcal(kcal),
                      style: NmTextStyles.from(NmType.h3, color: nm.text).tnum,
                    ),
                  ),
                  NmButton(
                    label: 'Agregar a la comida',
                    onPressed: valid
                        ? () {
                            ref.read(mealDraftProvider.notifier).addItem(
                              MealItem(
                                id: _uuid.v4(),
                                foodId: food.id,
                                name: food.name,
                                quantity:
                                    double.tryParse(
                                      _quantity.text.replaceAll(',', '.'),
                                    ) ??
                                    1,
                                unit: _portion!.label,
                                kcal: kcal,
                                proteinG: food.proteinG * multiplier,
                                carbsG: food.carbsG * multiplier,
                                fatG: food.fatG * multiplier,
                                position: 0,
                              ),
                            );
                            repo.markUsed(food.id);
                            // Vuelve al borrador de la comida, no al buscador.
                            //
                            // Antes eran dos `pop()` a ciegas, que daba por
                            // sentado que entre el borrador y esta pantalla
                            // hay **exactamente una** intermedia. Se cumplía
                            // viniendo del buscador y no se cumplía viniendo
                            // del escáner abierto desde el borrador: los dos
                            // pop se llevaban puesto el borrador. Ahora se
                            // avisa "agregué" y cada pantalla intermedia se
                            // cierra sola, sin contar nada.
                            context.pop(true);
                          }
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crear un alimento propio (F-03 paso 3). Es privado del usuario (RN-18).
class FoodNewScreen extends ConsumerStatefulWidget {
  const FoodNewScreen({super.key});

  @override
  ConsumerState<FoodNewScreen> createState() => _FoodNewScreenState();
}

class _FoodNewScreenState extends ConsumerState<FoodNewScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _brand = TextEditingController();
  final TextEditingController _serving = TextEditingController(text: '100');
  final TextEditingController _unit = TextEditingController(text: 'g');
  final TextEditingController _kcal = TextEditingController();
  final TextEditingController _protein = TextEditingController(text: '0');
  final TextEditingController _carbs = TextEditingController(text: '0');
  final TextEditingController _fat = TextEditingController(text: '0');
  String? _error;

  /// Dos toques rápidos creaban **dos** alimentos, cada uno con su uuid: el
  /// botón no pasaba `loading`, así que nada lo deshabilitaba mientras la
  /// escritura estaba en curso.
  bool _saving = false;

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _name,
      _brand,
      _serving,
      _unit,
      _kcal,
      _protein,
      _carbs,
      _fat,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final kcal = int.tryParse(_kcal.text) ?? 0;
    final inconsistent =
        kcal > 0 &&
        macrosAreInconsistent(
          declaredKcal: kcal,
          proteinG: _num(_protein),
          carbsG: _num(_carbs),
          fatG: _num(_fat),
        );
    final computed = kcalFromMacros(
      proteinG: _num(_protein),
      carbsG: _num(_carbs),
      fatG: _num(_fat),
    );

    return NmScreen(
      title: 'Crear alimento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          NmTextField(
            label: 'Nombre',
            controller: _name,
            maxLength: 120,
            error: _error,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: NmSpace.s4),
          NmTextField(label: 'Marca (opcional)', controller: _brand),
          const SizedBox(height: NmSpace.s4),
          Row(
            children: <Widget>[
              Expanded(
                child: NmNumberField(
                  label: 'Porción',
                  controller: _serving,
                  decimals: 2,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NmSpace.s3),
              Expanded(
                child: NmTextField(label: 'Unidad', controller: _unit),
              ),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          NmNumberField(
            label: 'Calorías por porción',
            controller: _kcal,
            suffix: 'kcal',
            onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NmSpace.s2),
              Expanded(
                child: NmNumberField(
                  label: 'Carbos',
                  controller: _carbs,
                  decimals: 1,
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NmSpace.s2),
              Expanded(
                child: NmNumberField(
                  label: 'Grasas',
                  controller: _fat,
                  decimals: 1,
                  suffix: 'g',
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          if (inconsistent) ...<Widget>[
            const SizedBox(height: NmSpace.s4),
            InfoNote(
              tone: NmNoteTone.caution,
              text: 'Los macros no coinciden con las calorías '
                  '(≈ $computed kcal). ¿Querés revisarlos?',
            ),
          ],
          const SizedBox(height: NmSpace.s8),
          NmButton(
            label: 'Guardar alimento',
            block: true,
            loading: _saving,
            onPressed: () async {
              if (_saving) return;
              if (_name.text.trim().isEmpty) {
                setState(() => _error = 'Poné un nombre al alimento.');
                return;
              }
              final serving = _num(_serving);
              if (serving <= 0 || serving > 10000) {
                setState(() => _error = 'La porción va de 0 a 10.000.');
                return;
              }
              setState(() => _saving = true);
              final food = Food(
                id: _uuid.v4(),
                userId: ref.read(profileProvider).id,
                name: _name.text.trim(),
                brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
                source: FoodSource.user,
                servingSize: serving,
                servingUnit: _unit.text.trim().isEmpty
                    ? 'g'
                    : _unit.text.trim(),
                kcal: kcal,
                proteinG: _num(_protein),
                carbsG: _num(_carbs),
                fatG: _num(_fat),
                portions: <FoodPortion>[
                  FoodPortion(
                    label: '${serving.round()} ${_unit.text.trim()}',
                    grams: serving,
                  ),
                ],
                nutrientWarning: inconsistent,
              );
              await ref.read(repositoryProvider).createOwnFood(food);
              if (!mounted) return;
              // El alimento ya está creado: si se vuelve con "Atrás" desde el
              // detalle, el botón tiene que estar usable otra vez.
              setState(() => _saving = false);
              if (!context.mounted) return;
              // `push` y no `pushReplacement`: reemplazarse deja sin dueño al
              // aviso de "lo agregué a la comida" que devuelve el detalle, y
              // esa es la señal con la que las pantallas intermedias se
              // cierran. El alimento ya está creado, así que volver acá con
              // "Atrás" no pierde nada.
              final added = await context.push<bool>(Routes.food(food.id));
              if (added == true && context.mounted) context.pop(true);
            },
          ),
        ],
      ),
    );
  }
}

/// Escanear código de barras con la cámara.
///
/// El campo de texto se queda igual: una etiqueta arrugada, con brillo o mal
/// impresa no se lee, y sin esa salida la pantalla sería un callejón sin
/// salida.
class FoodScanScreen extends ConsumerStatefulWidget {
  const FoodScanScreen({super.key});

  @override
  ConsumerState<FoodScanScreen> createState() => _FoodScanScreenState();
}

class _FoodScanScreenState extends ConsumerState<FoodScanScreen> {
  final TextEditingController _ean = TextEditingController();
  late final MobileScannerController _camera = MobileScannerController(
    // Solo los formatos que usan los productos de góndola: acota los falsos
    // positivos y acelera la detección.
    formats: const <BarcodeFormat>[
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  String? _error;
  bool _searching = false;

  /// La cámara sigue emitiendo mientras se consulta el catálogo; sin esto, un
  /// código bien leído dispara la búsqueda varias veces.
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || _searching) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.length < 8) continue;
      _handled = true;
      _ean.text = value;
      unawaited(_camera.stop());
      unawaited(_lookup());
      return;
    }
  }

  Future<void> _lookup() async {
    final ean = _ean.text.trim();
    if (ean.length < 8) {
      setState(() => _error = 'Un código de barras tiene al menos 8 dígitos.');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final food = await ref.read(repositoryProvider).lookupBarcode(ean);
      if (!mounted) return;
      setState(() => _searching = false);

      if (food == null) {
        setState(
          () => _error = 'Ese código no está en el catálogo. Podés crear el '
              'alimento a mano con los datos de la etiqueta.',
        );
        _resumeCamera();
        return;
      }

      // Se apila en vez de reemplazarse, para poder cerrarse cuando el detalle
      // avise que agregó el alimento. Reemplazándose, ese aviso no llegaba a
      // nadie y el detalle tenía que adivinar cuántas pantallas cerrar: dos,
      // que sobraba una cuando el escáner se abre desde el borrador mismo.
      final added = await context.push<bool>(Routes.food(food.id));
      if (!mounted) return;
      if (added == true) {
        context.pop(true);
        return;
      }
      // Volvió sin agregar: se sigue escaneando en vez de quedar con la cámara
      // congelada y sin forma de reintentar.
      _resumeCamera();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = error.message;
      });
      _resumeCamera();
    }
  }

  /// Vuelve a leer tras un fallo: si la cámara quedara parada habría que salir
  /// y entrar de nuevo para reintentar.
  void _resumeCamera() {
    _handled = false;
    unawaited(_camera.start());
  }

  @override
  void dispose() {
    _ean.dispose();
    unawaited(_camera.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmScreen(
      title: 'Escanear alimento',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s6),
          ClipRRect(
            borderRadius: NmRadius.brMd,
            child: SizedBox(
              height: 260,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  MobileScanner(
                    controller: _camera,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => Container(
                      color: nm.surfaceRaised,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(NmSpace.s4),
                      child: Text(
                        'No pudimos abrir la cámara. Escribí el código abajo.',
                        textAlign: TextAlign.center,
                        style: NmTextStyles.from(
                          NmType.bodySm,
                          color: nm.textMuted,
                        ),
                      ),
                    ),
                  ),
                  // Marco de puntería: sin una guía, no se sabe a qué
                  // distancia poner el envase.
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        height: 110,
                        width: 240,
                        decoration: BoxDecoration(
                          border: Border.all(color: nm.accent, width: 2),
                          borderRadius: NmRadius.brSm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            'Apuntá al código de barras del envase.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),
          NmNumberField(
            label: 'Código de barras (EAN)',
            controller: _ean,
            error: _error,
            hint: '7790070410016',
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Buscar',
            block: true,
            loading: _searching,
            onPressed: _lookup,
          ),
          const SizedBox(height: NmSpace.s4),
          const InfoNote(
            text: 'Los datos salen de Open Food Facts, un catálogo abierto. '
                'Si un producto está mal cargado, podés corregirlo al '
                'agregarlo.',
          ),
        ],
      ),
    );
  }
}
