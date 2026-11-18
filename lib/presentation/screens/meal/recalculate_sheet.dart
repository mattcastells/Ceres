import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../data/remote/photo_storage_client.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/analysis_stage.dart';
import '../../../domain/models/meal.dart';
import '../../../domain/services/photo_sync_service.dart';
import '../../components/feedback/analysis_progress.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/meal_photo_field.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/overlays.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import 'meal_draft.dart';

const _uuid = Uuid();

/// Recalcular la comida que se está editando.
///
/// Corregir una estimación obligaba a empezar de nuevo: sacar la foto otra
/// vez, esperar el análisis y rearmar la comida entera para cambiar un peso.
/// Acá se parte de lo que ya está cargado —con la foto que la comida ya tiene
/// o una nueva— y se le dice al modelo qué corregir; vuelve la comida
/// completa, con lo que la corrección no toca igual que antes.
///
/// Devuelve `true` cuando recalculó: quien la abrió muestra el aviso.
Future<bool?> showRecalculateSheet(BuildContext context) => showNmSheet<bool>(
  context: context,
  builder: (context) => const RecalculateSheet(),
);

class RecalculateSheet extends ConsumerStatefulWidget {
  const RecalculateSheet({super.key});

  @override
  ConsumerState<RecalculateSheet> createState() => _RecalculateSheetState();
}

class _RecalculateSheetState extends ConsumerState<RecalculateSheet> {
  final TextEditingController _text = TextEditingController();

  /// Mismo techo que aceptan las Edge Functions.
  static const int _maxLength = 400;

  bool _busy = false;
  AppError? _error;

  AnalysisStage _stage = AnalysisStage.preparing;
  DateTime _stageStartedAt = DateTime.now();
  Timer? _tick;

  /// La copia que la subida dejó en el bucket, mientras nadie la reclame.
  ///
  /// Solo aparece cuando la persona eligió una foto nueva: la que la comida ya
  /// tenía está en el bucket desde antes y no se vuelve a subir. Si el
  /// recálculo falla, esta copia no la nombra nadie y hay que borrarla.
  String? _subida;

  /// El servicio de fotos, tomado **antes** de empezar.
  ///
  /// Después de un `dispose` no se puede leer un provider, y justo ahí es
  /// cuando hay algo que limpiar: si el sheet se cierra con el pedido en
  /// curso, la foto que se alcanzó a subir queda en el bucket sin que ninguna
  /// comida la nombre.
  PhotoSyncService? _photos;

  @override
  void dispose() {
    _tick?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onStage(AnalysisStage stage) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _stageStartedAt = DateTime.now();
    });
  }

  void _descartarSubida() {
    final ruta = _subida;
    if (ruta == null) return;
    _subida = null;
    unawaited(
      _photos?.delete(bucket: PhotoBucket.meal, path: ruta).catchError(
            (Object _) {},
          ) ??
          Future<void>.value(),
    );
  }

  Future<void> _recalculate() async {
    final draft = ref.read(mealDraftProvider);
    if (draft == null || draft.isEmpty) return;

    final instruction = _text.text.trim();
    final photoPath = draft.photoPath;
    // Sin foto no hay nada contra qué recalcular más que lo escrito, así que
    // ahí la corrección es obligatoria. Con foto, no escribir nada es válido:
    // significa "volvé a mirarla".
    if (photoPath == null && instruction.length < 3) {
      setState(
        () => _error = const AppError(
          code: ApiErrorCode.validation,
          message: 'Contanos qué hay que corregir.',
        ),
      );
      return;
    }

    _photos = ref.read(photoSyncProvider);
    setState(() {
      _busy = true;
      _error = null;
      _stage = AnalysisStage.preparing;
      _stageStartedAt = DateTime.now();
    });
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _busy) setState(() {});
    });

    try {
      final analysis = await ref
          .read(repositoryProvider)
          .recalculate(
            items: draft.items,
            instruction: instruction,
            photoPath: photoPath,
            onStage: _onStage,
            onUploaded: (remote) => _subida = remote,
          );
      // Se cerró el sheet con el pedido en curso: no hay comida que corregir
      // —quien lo cerró decidió que no— y la foto que se subió para esto no la
      // va a nombrar nadie.
      if (!mounted) {
        _descartarSubida();
        return;
      }

      // Una respuesta sin ítems no puede pisar la comida: la dejaría vacía y
      // sin forma de guardarla. El servidor ya lo rechaza con su propio error,
      // así que esto es el cinturón de la regla que sostiene todo lo demás —
      // recalcular no borra nada.
      if (analysis.items.isEmpty) {
        _fallo(
          const AppError(
            code: ApiErrorCode.aiNoFood,
            message: 'El recálculo no devolvió ningún ítem. La comida quedó '
                'como estaba.',
          ),
        );
        return;
      }

      // Llegó bien: la copia del bucket pasa a ser la de la comida, así que ya
      // no hay nada suelto que limpiar. Y la comida pasa a apuntar a esa copia
      // en vez de al archivo del teléfono, para que guardar no la suba de nuevo.
      _subida = null;
      ref
          .read(mealDraftProvider.notifier)
          .replaceAnalysis(
            // Con foto la estimación salió de la imagen; sin foto, de la
            // descripción. El origen del dato tiene que decir lo que pasó.
            source: photoPath == null ? MealSource.aiText : MealSource.aiPhoto,
            items: <MealItem>[
              for (var i = 0; i < analysis.items.length; i++)
                MealItem.fromAnalysis(
                  analysis.items[i],
                  id: _uuid.v4(),
                  position: i,
                ),
            ],
            photoPath: analysis.photoPath,
            aiAnalysisId: analysis.id,
          );

      _tick?.cancel();
      Navigator.of(context).pop(true);
    } on AppError catch (error) {
      _fallo(error);
    } on Object catch (error) {
      _fallo(
        AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos recalcular la comida. Quedó como estaba.',
          requestId: error.toString(),
        ),
      );
    }
  }

  /// La comida queda intacta: recalcular no borra nada si falla.
  void _fallo(AppError error) {
    _tick?.cancel();
    _descartarSubida();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final draft = ref.watch(mealDraftProvider);
    final photoPath = draft?.photoPath;

    return PopScope(
      // Mientras corre no se cierra: el pedido sigue vivo igual y la comida
      // quedaría a medio camino, con la foto nueva ya subida y sin nadie que
      // la borre.
      canPop: !_busy,
      child: NmSheet(
        title: 'Recalcular con IA',
        subtitle: 'Se vuelven a estimar los ítems de esta comida.',
        footer: NmButton(
          label: 'Recalcular',
          block: true,
          icon: PhosphorIcons.sparkle(),
          loading: _busy,
          // Sin tope local: el límite diario lo hace cumplir el servidor y su
          // error se muestra abajo.
          onPressed: draft == null || draft.isEmpty
              ? null
              : _recalculate,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            MealPhotoField(
              path: photoPath,
              emptyLabel: 'Usar una foto',
              caption: null,
              onChanged: (path) =>
                  ref.read(mealDraftProvider.notifier).setPhoto(path),
            ),
            const SizedBox(height: NmSpace.s4),
            NmTextField(
              label: 'Qué corregir',
              controller: _text,
              hint: 'la milanesa pesaba 200 g; falta el pan',
              maxLines: 3,
              maxLength: _maxLength,
              enabled: !_busy,
              textInputAction: TextInputAction.newline,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            if (_busy) ...<Widget>[
              const SizedBox(height: NmSpace.s5),
              AnalysisProgress(
                stage: _stage,
                elapsedInStage: DateTime.now().difference(_stageStartedAt),
              ),
              const SizedBox(height: NmSpace.s3),
              Semantics(
                liveRegion: true,
                child: Text(
                  _stage.label,
                  style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
                ),
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: NmSpace.s5),
              ErrorState(message: _error!.message, code: _error!.code.wire),
            ],

          ],
        ),
      ),
    );
  }
}
