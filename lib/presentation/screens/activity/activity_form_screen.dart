import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/formats.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/activity.dart';
import '../../../domain/repositories/repositories.dart';
import '../../components/activity/activity_inputs.dart';
import '../../components/activity/exercise_calories_estimate.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import 'overlap_warning.dart';

const _uuid = Uuid();

/// S-10 · Registro rápido de actividad. ★
/// S-12 · Entrenamiento de fuerza (`mode=strength`).
///
/// El objetivo es guardar en menos de 12 segundos por el camino feliz.
class ActivityFormScreen extends ConsumerStatefulWidget {
  const ActivityFormScreen({
    this.mode = ActivityFormMode.duration,
    this.activityTypeId,
    this.activityId,
    this.templateId,
    this.date,
    super.key,
  });

  final ActivityFormMode mode;
  final String? activityTypeId;

  /// Cuando viene, se edita una actividad existente.
  final String? activityId;
  final String? templateId;
  final DateTime? date;

  @override
  ConsumerState<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends ConsumerState<ActivityFormScreen> {
  String? _typeId;
  int _duration = 30;
  Intensity _intensity = Intensity.moderate;
  DateTime _startedAt = DateTime.now();
  int? _distanceMeters;
  int? _steps;
  int? _avgHr;
  int? _maxHr;
  int? _override;
  String? _overrideReason;
  bool _usePace = false;
  bool _favorite = false;
  bool _expanded = false;
  bool _saving = false;
  String? _error;
  Timer? _debounce;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _distance = TextEditingController();
  final TextEditingController _stepsCtrl = TextEditingController();
  final TextEditingController _avgHrCtrl = TextEditingController();
  final TextEditingController _maxHrCtrl = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  bool get _isStrength => widget.mode == ActivityFormMode.strength;
  bool get _isWalkRun => widget.mode == ActivityFormMode.walkRun;
  bool get _isDistance => widget.mode == ActivityFormMode.distance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
  }

  void _hydrate() {
    final repo = ref.read(repositoryProvider);
    final DateTime date = widget.date ?? ref.read(selectedDateProvider);

    if (widget.activityId != null) {
      final activity = repo.activityById(widget.activityId!);
      if (activity != null) {
        setState(() {
          _typeId = activity.activityTypeId;
          _duration = activity.durationMinutes;
          _intensity = activity.intensity;
          _startedAt = activity.startedAt;
          _distanceMeters = activity.distanceMeters;
          _steps = activity.steps;
          _avgHr = activity.averageHeartRate;
          _maxHr = activity.maximumHeartRate;
          _favorite = activity.isFavorite;
          _name.text = activity.customName ?? '';
          _notes.text = activity.notes ?? '';
          if (activity.wasOverridden) {
            _override = activity.estimatedCalories;
            _overrideReason = activity.overrideReason;
          }
        });
        return;
      }
    }

    if (widget.templateId != null) {
      // Sin `orElse` que caiga en `templates.first`: con cero plantillas eso
      // lanza `StateError` y el formulario se cae, y con un id que no existe
      // —una URL vieja, un enlace compartido— hidrataba **otra** plantilla en
      // silencio, que es peor que no hidratar ninguna.
      ExerciseTemplate? encontrada;
      for (final t in repo.templates) {
        if (t.id == widget.templateId) {
          encontrada = t;
          break;
        }
      }
      if (encontrada == null) return;
      final template = encontrada;

      setState(() {
        _typeId = template.activityTypeId;
        _duration = template.defaultDurationMinutes;
        _intensity = template.defaultIntensity;
        _distanceMeters = template.defaultDistanceMeters;
        _name.text = template.name;
      });
      return;
    }

    setState(() {
      _typeId =
          widget.activityTypeId ??
          (_isStrength
              ? repo.typeBySlug('strength_training')?.id
              : _isWalkRun
              ? repo.typeBySlug('walking')?.id
              : repo.recentActivities().firstOrNull?.activityTypeId);
      _startedAt = DateTime(
        date.year,
        date.month,
        date.day,
        DateTime.now().hour,
        DateTime.now().minute,
      );
      _expanded = _isWalkRun || _isDistance;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _distance.dispose();
    _stepsCtrl.dispose();
    _avgHrCtrl.dispose();
    _maxHrCtrl.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// El recálculo tiene un debounce de 120 ms (21-motion §3.3).
  void _scheduleRecalc() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) setState(() {});
    });
  }

  ActivityDraft get _draft => ActivityDraft(
    id: widget.activityId,
    activityTypeId: _typeId ?? '',
    customName: _name.text.trim().isEmpty ? null : _name.text.trim(),
    startedAt: _startedAt,
    durationMinutes: _duration,
    intensity: _intensity,
    distanceMeters: _distanceMeters,
    steps: _steps,
    averageHeartRate: _avgHr,
    maximumHeartRate: _maxHr,
    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    overrideCalories: _override,
    overrideReason: _overrideReason,
    usePaceEstimate: _usePace,
    isFavorite: _favorite,
  );

  String? _validate() {
    if (_typeId == null || _typeId!.isEmpty) {
      return 'Elegí un tipo de actividad.';
    }
    if (_duration < 1 || _duration > 1440) {
      return 'La duración debe estar entre 1 y 1440 minutos.';
    }
    if (_startedAt.isAfter(DateTime.now().add(const Duration(hours: 24)))) {
      return 'No podés registrar actividad en el futuro.';
    }
    if (_distanceMeters != null &&
        (_distanceMeters! < 0 || _distanceMeters! > 500000)) {
      return 'Revisá la distancia.';
    }
    if (_steps != null && (_steps! < 0 || _steps! > 200000)) {
      return 'Revisá la cantidad de pasos.';
    }
    if (_avgHr != null && (_avgHr! < 30 || _avgHr! > 230)) {
      return 'La frecuencia cardíaca va de 30 a 230 bpm.';
    }
    if (_maxHr != null && (_maxHr! < 30 || _maxHr! > 230)) {
      return 'La frecuencia cardíaca va de 30 a 230 bpm.';
    }
    if (_avgHr != null && _maxHr != null && _avgHr! > _maxHr!) {
      return 'La frecuencia promedio no puede superar la máxima.';
    }
    return null;
  }

  Future<void> _save({bool addAnother = false}) async {
    // Dos toques rápidos guardaban **dos** actividades: el botón principal
    // pasa `loading: _saving` y se deshabilita solo, pero "Y otra" no lo hacía,
    // y entre el primer toque y el `setState` hay una ventana.
    if (_saving) return;
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });

    final repo = ref.read(repositoryProvider);

    // Solapamiento con otra actividad: advertencia no bloqueante (F-08).
    final overlaps = repo.checkOverlap(_draft);
    if (overlaps.isNotEmpty && widget.activityId == null) {
      final proceed = await showOverlapWarning(context, overlaps.first);
      if (!proceed) {
        if (mounted) setState(() => _saving = false);
        return;
      }
    }

    final activity = await repo.saveActivity(_draft);
    if (!mounted) return;
    setState(() => _saving = false);

    if (addAnother) {
      setState(() {
        _duration = 30;
        _override = null;
        _notes.clear();
      });
      NmSnackbar.show(context, 'Actividad guardada');
      return;
    }

    context.pop();
    NmSnackbar.show(
      context,
      'Actividad guardada',
      actionLabel: 'Ver',
      onAction: () => context.push(Routes.activity(activity.id)),
    );
  }

  Future<void> _openOverride(int calculated) async {
    final controller = TextEditingController(
      text: (_override ?? calculated).toString(),
    );
    var reason = _overrideReason;

    final result = await showNmDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => NmDialog(
          title: 'Ingresar otro valor',
          body: 'El valor calculado es ${Fmt.integer(calculated)} kcal y '
              'queda guardado aparte.',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              NmNumberField(
                label: 'Calorías',
                controller: controller,
                suffix: 'kcal',
                autofocus: true,
              ),
              const SizedBox(height: NmSpace.s4),
              Wrap(
                spacing: NmSpace.s2,
                runSpacing: NmSpace.s2,
                children: <Widget>[
                  for (final option in const <String>[
                    'Mi reloj marcó otra cosa',
                    'Me pareció mucho',
                    'Me pareció poco',
                    'Otro',
                  ])
                    NmChip(
                      label: option,
                      selected: reason == option,
                      onTap: () => setLocal(() => reason = option),
                    ),
                ],
              ),
            ],
          ),
          actions: <Widget>[
            NmButton.ghost(
              label: 'Cancelar',
              onPressed: () => Navigator.of(context).pop(),
            ),
            NmButton(
              label: 'Guardar',
              onPressed: () {
                final value = int.tryParse(controller.text);
                if (value == null || value < 1 || value > 10000) return;
                Navigator.of(context).pop(value);
              },
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (result == null) return;
    setState(() {
      _override = result;
      _overrideReason = reason;
    });
  }

  Future<void> _saveAsTemplate() async {
    if (_typeId == null) return;
    await ref.read(repositoryProvider).saveTemplate(
      ExerciseTemplate(
        id: _uuid.v4(),
        name: _name.text.trim().isEmpty
            ? ref.read(repositoryProvider).typeById(_typeId!)?.displayName ??
                  'Plantilla'
            : _name.text.trim(),
        activityTypeId: _typeId!,
        defaultDurationMinutes: _duration,
        defaultIntensity: _intensity,
        defaultDistanceMeters: _distanceMeters,
      ),
    );
    if (!mounted) return;
    NmSnackbar.show(context, 'Plantilla guardada');
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final types = ref.watch(activityTypesProvider);
    final units = ref.watch(unitSystemProvider);
    final recent = ref.watch(recentActivitiesProvider);
    final type = _typeId == null ? null : repo.typeById(_typeId!);

    final estimate = _typeId == null
        ? const ActivityEstimate(
            calories: 0,
            method: EstimationMethod.met,
            unavailableReason: 'Elegí un tipo de actividad',
          )
        : repo.estimate(_draft);

    // Con override activo el recálculo no pisa el número: se ofrece (S-10).
    final calculated = _typeId == null
        ? null
        : repo
              .estimate(
                ActivityDraft(
                  activityTypeId: _typeId!,
                  startedAt: _startedAt,
                  durationMinutes: _duration,
                  intensity: _intensity,
                  distanceMeters: _distanceMeters,
                  usePaceEstimate: _usePace,
                ),
              )
              .calories;

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: NmModalHeader(
        title: _isStrength
            ? 'Entrenamiento de fuerza'
            : widget.activityId == null
            ? 'Registrar actividad'
            : 'Editar actividad',
        actions: <Widget>[
          IconButton(
            tooltip: _favorite ? 'Quitar de favoritas' : 'Marcar como favorita',
            onPressed: () => setState(() => _favorite = !_favorite),
            icon: Icon(
              _favorite
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
                        if (_error != null) ...<Widget>[
                          InfoNote(text: _error!, tone: NmNoteTone.caution),
                          const SizedBox(height: NmSpace.s4),
                        ],

                        if (_isStrength) ...<Widget>[
                          NmTextField(
                            label: 'Nombre del entrenamiento',
                            controller: _name,
                            hint: 'Tren superior, Piernas, Full body…',
                          ),
                          const SizedBox(height: NmSpace.s3),
                          Wrap(
                            spacing: NmSpace.s2,
                            children: <Widget>[
                              for (final suggestion in const <String>[
                                'Tren superior',
                                'Piernas',
                                'Full body',
                              ])
                                NmChip(
                                  label: suggestion,
                                  selected: _name.text == suggestion,
                                  onTap: () =>
                                      setState(() => _name.text = suggestion),
                                ),
                            ],
                          ),
                          const SizedBox(height: NmSpace.s6),
                        ] else ...<Widget>[
                          ActivityTypeSelector(
                            types: types,
                            recentTypeIds: recent
                                .map((a) => a.activityTypeId)
                                .toList(),
                            value: _typeId,
                            onChanged: (id) => setState(() => _typeId = id),
                            onBrowseAll: () async {
                              final picked = await context.push<String>(
                                Routes.activitySearch,
                              );
                              if (picked != null) {
                                setState(() => _typeId = picked);
                              }
                            },
                          ),
                          const SizedBox(height: NmSpace.s6),
                        ],

                        DurationInput(
                          valueMinutes: _duration,
                          onChanged: (v) {
                            _duration = v;
                            _scheduleRecalc();
                          },
                        ),
                        const SizedBox(height: NmSpace.s6),

                        ActivityIntensitySelector(
                          value: _intensity,
                          type: type,
                          onChanged: (v) {
                            setState(() => _intensity = v);
                            _scheduleRecalc();
                          },
                        ),
                        const SizedBox(height: NmSpace.s6),

                        Row(
                          children: <Widget>[
                            Expanded(
                              child: NmDateField(
                                label: 'Fecha',
                                value: _startedAt,
                                lastDate: DateTime.now().add(
                                  const Duration(days: 1),
                                ),
                                onChanged: (v) => setState(
                                  () => _startedAt = DateTime(
                                    v.year,
                                    v.month,
                                    v.day,
                                    _startedAt.hour,
                                    _startedAt.minute,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: NmSpace.s3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Hora de inicio',
                                    style: NmTextStyles.from(
                                      NmType.caption,
                                      color: nm.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: NmSpace.s2),
                                  NmButton.secondary(
                                    label: timeOfDay(_startedAt),
                                    block: true,
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.fromDateTime(
                                          _startedAt,
                                        ),
                                      );
                                      if (picked == null) return;
                                      setState(
                                        () => _startedAt = DateTime(
                                          _startedAt.year,
                                          _startedAt.month,
                                          _startedAt.day,
                                          picked.hour,
                                          picked.minute,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: NmSpace.s6),

                        ExerciseCaloriesEstimate(
                          calories: estimate.calories,
                          method: estimate.method,
                          metValue: estimate.metValue,
                          weightKg: estimate.weightKg,
                          durationMinutes: estimate.durationMinutes,
                          originalCalories: _override == null
                              ? null
                              : calculated,
                          unavailableReason: estimate.unavailableReason,
                          onFixWeight: () => context.push(Routes.progress),
                          onOverride: estimate.isAvailable
                              ? () => _openOverride(calculated ?? 0)
                              : null,
                          onRestore: _override == null
                              ? null
                              : () => setState(() {
                                  _override = null;
                                  _overrideReason = null;
                                }),
                          recalculatedHint:
                              _override != null && calculated != _override
                              ? calculated
                              : null,
                          onUseRecalculated: _override == null
                              ? null
                              : () => setState(() => _override = null),
                        ),

                        if ((type?.supportsDistance ?? false) &&
                            _distanceMeters != null &&
                            _distanceMeters! > 0) ...<Widget>[
                          const SizedBox(height: NmSpace.s3),
                          NmSwitchRow(
                            title: 'Calcular por ritmo',
                            subtitle:
                                'Usa la distancia y la duración en lugar del '
                                'MET del tipo',
                            value: _usePace,
                            onChanged: (v) => setState(() => _usePace = v),
                          ),
                        ],

                        const SizedBox(height: NmSpace.s6),

                        // Acordeón "Más detalles".
                        InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          borderRadius: NmRadius.brMd,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: NmSpace.s3,
                            ),
                            child: Row(
                              children: <Widget>[
                                Icon(
                                  _expanded
                                      ? PhosphorIcons.caretUp()
                                      : PhosphorIcons.caretDown(),
                                  size: NmIconSize.md,
                                  color: nm.textMuted,
                                ),
                                const SizedBox(width: NmSpace.s2),
                                Text(
                                  'Más detalles',
                                  style: NmTextStyles.from(
                                    NmType.bodySm,
                                    color: nm.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_expanded) ...<Widget>[
                          if (type?.supportsDistance ?? true) ...<Widget>[
                            DistanceInput(
                              controller: _distance,
                              units: units,
                              onChanged: (meters) {
                                _distanceMeters = meters;
                                _scheduleRecalc();
                              },
                            ),
                            const SizedBox(height: NmSpace.s4),
                          ],
                          if (type?.supportsSteps ?? true) ...<Widget>[
                            NmNumberField(
                              label: 'Pasos',
                              controller: _stepsCtrl,
                              onChanged: (raw) =>
                                  _steps = int.tryParse(raw),
                            ),
                            const SizedBox(height: NmSpace.s4),
                          ],
                          if (type?.supportsHeartRate ?? true) ...<Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: NmNumberField(
                                    label: 'FC promedio',
                                    controller: _avgHrCtrl,
                                    suffix: 'bpm',
                                    onChanged: (raw) =>
                                        _avgHr = int.tryParse(raw),
                                  ),
                                ),
                                const SizedBox(width: NmSpace.s3),
                                Expanded(
                                  child: NmNumberField(
                                    label: 'FC máxima',
                                    controller: _maxHrCtrl,
                                    suffix: 'bpm',
                                    onChanged: (raw) =>
                                        _maxHr = int.tryParse(raw),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: NmSpace.s2),
                            const InfoNote(
                              text: 'La frecuencia cardíaca no entra en el '
                                  'cálculo de calorías.',
                            ),
                            const SizedBox(height: NmSpace.s4),
                          ],
                          NmTextField(
                            label: 'Notas',
                            controller: _notes,
                            maxLines: 3,
                          ),
                          const SizedBox(height: NmSpace.s4),
                          NmButton.ghost(
                            label: 'Guardar como plantilla',
                            onPressed: _saveAsTemplate,
                          ),
                        ],

                        const SizedBox(height: NmSpace.s6),
                        Text(
                          'Las calorías de ejercicio son una estimación.',
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ),
                        ),
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
                    child: NmButton(
                      label: 'Guardar',
                      block: true,
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ),
                  if (widget.activityId == null) ...<Widget>[
                    const SizedBox(width: NmSpace.s2),
                    NmButton.secondary(
                      label: 'Y otra',
                      loading: _saving,
                      onPressed: () => _save(addAnother: true),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
