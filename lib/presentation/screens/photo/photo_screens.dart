import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';
import '../../../data/local/photo_normalizer.dart';
import '../../../data/remote/photo_storage_client.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/ai_analysis.dart';
import '../../../domain/models/analysis_stage.dart';
import '../../../domain/models/meal.dart';
import '../../../domain/services/photo_sync_service.dart';
import '../../components/activity/badges.dart';
import '../../components/feedback/analysis_progress.dart';
import '../../components/feedback/feedback.dart';
import '../../components/food/food_widgets.dart';
import '../../components/food/meal_photo.dart';
import '../../components/food/photo_viewer.dart';
import '../../components/system/buttons.dart';
import '../../components/system/dictation.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';
import '../meal/meal_draft.dart';

const _uuid = Uuid();

/// El análisis en curso, para pasarlo de "Analizando" a "Revisar".
final analysisProvider = StateProvider<AiAnalysis?>((ref) => null);
final photoPathProvider = StateProvider<String?>((ref) => null);

/// Lo que la persona aclaró sobre la foto antes de analizarla.
///
/// Viaja por provider por lo mismo que [photoTargetProvider]: son tres
/// pantallas encadenadas con `pushReplacement` y arrastrar el texto como query
/// param solo abre lugares donde perderlo. Se limpia al sacar cada foto: una
/// aclaración vieja aplicada a una comida nueva es peor que ninguna.
final photoNoteProvider = StateProvider<String>((ref) => '');

/// Slot y día a los que va la comida cuando se entró desde una sección
/// concreta ("+" de Almuerzo, por ejemplo) y no desde el menú general.
///
/// Va por provider y no por query param porque el circuito son tres pantallas
/// encadenadas con `pushReplacement`: arrastrar los parámetros por las tres
/// solo abre lugares donde perderlos.
class PhotoTarget {
  const PhotoTarget({required this.slot, required this.date});

  final MealSlot slot;
  final DateTime date;
}

final photoTargetProvider = StateProvider<PhotoTarget?>((ref) => null);

/// S-18 · Cámara.
class PhotoCaptureScreen extends ConsumerStatefulWidget {
  const PhotoCaptureScreen({super.key});

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _permissionDenied = false;
  bool _busy = false;

  /// Un fallo que **no** es de permiso ni de cámara: una imagen ilegible, un
  /// archivo que se movió. Antes todo caía en `_permissionDenied` y la pantalla
  /// mandaba a revisar un permiso que estaba bien.
  String? _error;

  Future<void> _capture(ImageSource source) async {
    if (source == ImageSource.camera) {
      final proceed = await _showRationale();
      if (!proceed || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      // Compresión a 1024 px del lado mayor, calidad 0,8 (F-05 paso 3).
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      // Salvo cuando la imagen traía alfa: ahí `imageQuality` se ignoró y lo que
      // hay es un PNG sin comprimir de varios MB (`PhotoNormalizer`). Además de
      // pesar, esa foto se sube a Gemini y viaja entera.
      final path = file == null ? null : await PhotoNormalizer.toJpeg(file.path);
      if (!mounted) return;
      setState(() => _busy = false);
      if (path == null) return;
      ref.read(photoPathProvider.notifier).state = path;
      // Foto nueva, aclaración en blanco: lo que se escribió sobre la comida
      // anterior no tiene nada que ver con esta.
      ref.read(photoNoteProvider.notifier).state = '';
      if (!mounted) return;
      // Antes de analizar se pregunta qué es: la foto no puede mostrar el
      // relleno de una empanada y la persona sí lo sabe (S-18b).
      context.pushReplacement(Routes.photoDescribe);
    } on PlatformException catch (error) {
      // Solo esto es un problema de permiso o de cámara. Antes el `on Object`
      // marcaba `_permissionDenied` para **cualquier** fallo, así que una
      // imagen que `PhotoNormalizer` no podía leer terminaba diciendo "No
      // pudimos abrir la cámara" y mandando a revisar un permiso que estaba
      // bien.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _permissionDenied = error.code != 'invalid_image';
        _error = error.code == 'invalid_image'
            ? 'No pudimos leer esa imagen. Probá con otra.'
            : null;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No pudimos usar esa foto. Probá de nuevo o elegí otra.';
      });
    }
  }

  /// `dialog.permission_rationale`: se explica el permiso antes de pedirlo.
  Future<bool> _showRationale() async {
    final accepted = await showNmDialog<bool>(
      context: context,
      builder: (context) => NmDialog(
        title: 'Vamos a usar la cámara',
        body: 'La foto se usa solo para estimar los ítems de la comida. '
            'Podés corregir todo antes de guardar y la imagen queda en tu '
            'teléfono.',
        actions: <Widget>[
          NmButton.ghost(
            label: 'Ahora no',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NmButton(
            label: 'Continuar',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final repo = ref.watch(repositoryProvider);
    final remaining = repo.quotaLimit - repo.quotaUsed;
    final quotaExhausted = remaining <= 0;

    return Scaffold(
      backgroundColor: nm.bg,
      appBar: const NmModalHeader(title: 'Sacar foto'),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(context.screenPadding),
          child: Column(
            children: <Widget>[
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: nm.surfaceRaised,
                    borderRadius: NmRadius.brLg,
                    border: Border.all(color: nm.divider),
                  ),
                  child: _permissionDenied || _error != null
                      ? EmptyState(
                          icon: PhosphorIcons.camera(),
                          title: _error != null
                              ? 'No pudimos usar esa foto'
                              : 'No pudimos abrir la cámara',
                          body:
                              _error ??
                              'Podés darle permiso desde la configuración '
                                  'del sistema o elegir una foto de la galería.',
                          primaryLabel: 'Elegir de la galería',
                          onPrimary: () => _capture(ImageSource.gallery),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              PhosphorIcons.aperture(),
                              size: 64,
                              color: nm.textMuted,
                            ),
                            const SizedBox(height: NmSpace.s4),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NmSpace.s6,
                              ),
                              child: Text(
                                'Encuadrá el plato completo desde arriba.',
                                textAlign: TextAlign.center,
                                style: NmTextStyles.from(
                                  NmType.bodySm,
                                  color: nm.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: NmSpace.s4),
              if (quotaExhausted)
                const InfoNote(
                  tone: NmNoteTone.caution,
                  text: 'Llegaste al límite diario de análisis por foto. '
                      'Podés registrar la comida a mano.',
                )
              else if (remaining <= 5)
                InfoNote(
                  text: 'Te quedan $remaining análisis por foto hoy.',
                ),
              const SizedBox(height: NmSpace.s4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NmButton.secondary(
                      label: 'Galería',
                      icon: PhosphorIcons.images(),
                      onPressed: quotaExhausted
                          ? null
                          : () => _capture(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: NmSpace.s3),
                  Expanded(
                    child: NmButton(
                      label: 'Sacar foto',
                      icon: PhosphorIcons.camera(),
                      loading: _busy,
                      onPressed: quotaExhausted
                          ? null
                          : () => _capture(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// S-18b · Qué es lo que se ve. El paso entre sacar la foto y analizarla.
///
/// Existe porque la foto tiene un techo que no se puede subir mejorando el
/// prompt: una empanada se ve igual sea de carne, de humita o de jamón y
/// queso, y el pollo frito y el hervido son el mismo pollo desde arriba. El
/// modelo elige el más probable y se equivoca callado. La persona que la sacó
/// sabe la respuesta y hasta ahora no tenía dónde escribirla.
///
/// El campo es **opcional**: seguir sin escribir nada deja el análisis
/// exactamente como era. Por eso el botón dice "Analizar" y no "Continuar", y
/// no hay validación de largo mínimo — vacío es una respuesta válida.
class PhotoDescribeScreen extends ConsumerStatefulWidget {
  const PhotoDescribeScreen({super.key});

  @override
  ConsumerState<PhotoDescribeScreen> createState() =>
      _PhotoDescribeScreenState();
}

class _PhotoDescribeScreenState extends ConsumerState<PhotoDescribeScreen> {
  late final TextEditingController _text = TextEditingController(
    text: ref.read(photoNoteProvider),
  );

  /// Mismo techo que acepta la Edge Function: cortar acá evita que alguien
  /// escriba de más y el servidor lo recorte sin decirlo.
  static const int _maxLength = 400;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _analyze() {
    ref.read(photoNoteProvider.notifier).state = _text.text.trim();
    context.pushReplacement(Routes.photoAnalyzing);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final path = ref.watch(photoPathProvider);

    return NmScreen(
      title: '¿Qué es?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          if (path != null) ...<Widget>[
            MealPhoto(path: path, height: 200),
            const SizedBox(height: NmSpace.s5),
          ],
          Text(
            'Si querés, contanos qué hay en la foto. La IA ve la forma pero no '
            'el relleno ni cómo está cocinado: con eso estima mucho mejor.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s5),
          // Con el plato delante y el teléfono en la mano, decirlo es más
          // rápido que escribirlo. Mismo campo, mismo botón de abajo.
          NmDictationField(
            controller: _text,
            builder: (context, microphone) => NmTextField(
              label: 'Descripción (opcional)',
              controller: _text,
              hint: 'empanadas de carne al horno, la ensalada con aceite',
              maxLines: 3,
              maxLength: _maxLength,
              autofocus: true,
              textInputAction: TextInputAction.newline,
              suffixIcon: microphone,
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          // Un solo botón, que lee el campo.
          //
          // Eran dos —"Analizar" y "Analizar sin describir"— y el segundo
          // existía para decir que saltear estaba permitido. Pero con el campo
          // vacío los dos hacían exactamente lo mismo, y con el campo lleno el
          // de abajo tiraba lo escrito: dos botones para una sola decisión que
          // el campo ya expresa solo.
          NmButton(
            label: 'Analizar',
            block: true,
            icon: PhosphorIcons.sparkle(),
            onPressed: _analyze,
          ),
        ],
      ),
    );
  }
}

/// S-19 · Analizando. La única espera larga del producto (21-motion §4.4).
class PhotoAnalyzingScreen extends ConsumerStatefulWidget {
  const PhotoAnalyzingScreen({super.key});

  @override
  ConsumerState<PhotoAnalyzingScreen> createState() =>
      _PhotoAnalyzingScreenState();
}

class _PhotoAnalyzingScreenState extends ConsumerState<PhotoAnalyzingScreen>
    with SingleTickerProviderStateMixin {
  /// Lo que se cuenta primero: el trabajo real, en el orden en que pasa.
  ///
  /// Se dice una sola vez cada una y entre las cinco cubren la espera típica
  /// —la mediana de la llamada es 12,3 s (`AnalysisTiming.typical`)—, así que
  /// la mayoría de las veces la pantalla no llega a salir de acá.
  ///
  /// Arrancan con el paso `analyzing` y no antes: contar "estimando porciones"
  /// mientras todavía se sube la foto sería inventar. Preparar y subir tienen
  /// su propio texto, que sale de `AnalysisStage`.
  static const List<String> _opening = <String>[
    'Buscando alimentos en la foto…',
    'Reconociendo las preparaciones…',
    'Estimando el tamaño de las porciones…',
    'Calculando calorías y macros…',
    'Revisando que los números cierren…',
  ];

  /// Y después, mientras siga sin llegar la respuesta, esto rota sin fin.
  ///
  /// **No hay "Terminando" ni "Está tardando más de lo normal", a propósito.**
  /// Los dos prometían algo sobre el reloj que Ceres no puede prometer:
  /// cuánto tarda el modelo no lo decidimos nosotros. "Terminando" a los 14 s
  /// era mentira la mitad de las veces, y el aviso de demora convertía una
  /// espera normal en un problema — la persona no puede hacer nada con ese
  /// dato salvo ponerse ansiosa y mirar el reloj.
  ///
  /// Lo que la espera necesita es señal de vida, y para eso alcanza con que la
  /// frase cambie. Que además sea liviana es lo que hace la diferencia entre
  /// esperar y esperar preocupado.
  /// Ninguna pasa de dos líneas a propósito: la altura del texto está fijada
  /// en dos y lo que sobre se corta con puntos suspensivos. Un chiste cortado
  /// es peor que un chiste corto.
  static const List<String> _idle = <String>[
    'Contando garbanzos de a uno…',
    'Discutiendo si es una porción o dos…',
    'Preguntándole a la milanesa qué lleva…',
    'Midiendo el aceite con una cucharita…',
    'Buscando el tomate escondido atrás…',
    'Pesando el arroz grano por grano…',
    'Sacándole la ficha a la salsa…',
    'Llamando al nutricionista imaginario…',
    'Repasando la cuenta con los dedos…',
    'Mirando la foto de costado, por las dudas…',
    'Poniéndole nombre a eso del costado…',
    'Negociando con la porción de postre…',
  ];

  /// Cada cuánto cambia la frase. Lo bastante seguido para que se vea que algo
  /// pasa, lo bastante espaciado para poder leerla.
  static const Duration _phaseEvery = Duration(milliseconds: 3200);

  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  final List<Timer> _timers = <Timer>[];

  /// Cuántas frases se dijeron ya en esta corrida. Las primeras salen de
  /// `_opening` y de ahí en más el índice sigue contando contra `_idle`.
  int _phaseIndex = 0;
  String _phase = _opening.first;

  /// Desde qué frase del pozo arranca la rotación. Al azar por corrida: dos
  /// análisis lentos seguidos contarían el mismo chiste en el mismo orden, y
  /// ahí la broma deja de tapar la espera y pasa a marcarla.
  final int _idleOffset = math.Random().nextInt(_idle.length);

  bool _cancelled = false;

  /// En qué paso real va el circuito, y desde cuándo. Los dos alimentan la
  /// barra: el paso da el tramo y el reloj estima dentro de él.
  AnalysisStage _stage = AnalysisStage.preparing;
  DateTime _stageStartedAt = DateTime.now();

  /// Qué falló. Sin esto, un análisis que se cae dejaba la pantalla girando
  /// para siempre: `analyze` lanzaba, nadie lo agarraba, y no había ni error ni
  /// salida más que Cancelar. La espera eterna es la peor forma de contar un
  /// fallo, porque no se distingue de una que está por terminar bien — y ahora
  /// que las frases rotan sin fin, esto es lo único que corta el bucle.
  AppError? _error;

  /// Segundos que faltan para que reintentar pueda salir bien.
  ///
  /// Solo se llena cuando el proveedor dice cuánto falta (su 429 lo trae). El
  /// 13 de agosto se tocó "Reintentar" cuatro veces en cuarenta segundos
  /// contra una cuota agotada: cada toque gastaba cupo y ninguno podía
  /// funcionar. Un botón que se puede tocar es una promesa de que sirve.
  int _retryIn = 0;
  Timer? _cuenta;

  /// Hasta acá se cuenta segundo a segundo. Más que esto no es una espera, es
  /// el cupo del día: un contador de seis cifras bajando durante horas no le
  /// sirve a nadie, y el `setState` por segundo tampoco.
  static const int _cuentaMax = 90;

  /// La copia que analizar dejó en el bucket, mientras nadie la reclame.
  ///
  /// Analizar sube la foto con un id al azar —la Edge Function la lee de ahí—.
  /// Si el análisis sale bien, la comida termina apuntando a esa copia y deja
  /// de estar suelta. Si falla o se cancela, no la nombra nadie: invisible,
  /// imborrable desde la app y ocupando espacio para siempre. Se guarda acá
  /// para poder borrarla al salir.
  String? _subida;

  @override
  void initState() {
    super.initState();
    _start();
  }

  /// Borra la copia suelta, si quedó una. Fire-and-forget a propósito: nadie
  /// espera por una limpieza, y si falla la purga del arranque la vuelve a
  /// intentar.
  void _descartarSubida() {
    final ruta = _subida;
    if (ruta == null) return;
    _subida = null;
    unawaited(
      ref
          .read(photoSyncProvider)
          ?.delete(bucket: PhotoBucket.meal, path: ruta)
          .catchError((_) {}) ??
          Future<void>.value(),
    );
  }

  void _start() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _stage = AnalysisStage.preparing;
    _stageStartedAt = DateTime.now();

    // Un tick corto mantiene viva la estimación del tramo del modelo. No es
    // una animación: es el reloj real contra el que se dibuja la barra.
    _timers.add(
      Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _error == null) setState(() {});
      }),
    );
    unawaited(_run());
  }

  /// Arranca los mensajes recién cuando empieza el trabajo del modelo: contar
  /// "estimando porciones" mientras todavía se sube la foto sería inventar.
  ///
  /// Un solo timer periódico en vez de uno por frase: la lista ya no termina,
  /// así que no hay una cantidad fija de avisos que agendar.
  void _startPhaseMessages() {
    _phaseIndex = 0;
    _phase = _phraseAt(0);
    _timers.add(
      Timer.periodic(_phaseEvery, (_) {
        if (!mounted || _error != null) return;
        setState(() => _phase = _phraseAt(++_phaseIndex));
      }),
    );
  }

  /// Lo que se está diciendo ahora. Mientras se prepara y se sube, el paso
  /// habla por sí solo; recién con el modelo trabajando entran las frases.
  String get _label =>
      _stage == AnalysisStage.analyzing ? _phase : _stage.label;

  /// Las de `_opening` una vez cada una y en orden; de ahí en adelante, el
  /// pozo en bucle. Nunca se queda sin frase, que es justamente el punto.
  String _phraseAt(int index) {
    if (index < _opening.length) return _opening[index];
    final rotated = index - _opening.length + _idleOffset;
    return _idle[rotated % _idle.length];
  }

  void _onStage(AnalysisStage stage) {
    if (!mounted) return;
    setState(() {
      _stage = stage;
      _stageStartedAt = DateTime.now();
      if (stage == AnalysisStage.analyzing) {
        _startPhaseMessages();
      }
    });
  }

  Future<void> _run() async {
    final path = ref.read(photoPathProvider);
    if (!mounted || _cancelled) return;

    try {
      final analysis = await ref
          .read(repositoryProvider)
          .analyze(
            photoPath: path ?? '',
            description: ref.read(photoNoteProvider),
            onStage: _onStage,
            onUploaded: (remote) => _subida = remote,
          );
      if (!mounted || _cancelled) return;

      // Llegó bien: la copia del bucket pasa a ser la de la comida, así que ya
      // no hay nada suelto que limpiar.
      _subida = null;
      ref.read(analysisProvider.notifier).state = analysis;

      // La foto ya está en el bucket: analizarla la subió. Se pasa a apuntar a
      // esa copia y no al archivo del teléfono, así al guardar la comida no se
      // sube una segunda vez —era el doble de espacio por cada foto analizada,
      // con la primera copia sin que la referenciara nadie—. `MealPhoto` sabe
      // mostrar las dos, así que la revisión se ve igual.
      final remote = analysis.photoPath;
      if (remote != null) {
        ref.read(photoPathProvider.notifier).state = remote;
      }

      context.pushReplacement(Routes.photoReview);
    } on AppError catch (error) {
      if (!mounted || _cancelled) return;
      _fallo(error);
    } on Object catch (error) {
      if (!mounted || _cancelled) return;
      _fallo(
        AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos analizar la foto. Cargá la comida a mano; la '
              'foto queda adjunta.',
          requestId: error.toString(),
        ),
      );
    }
  }

  /// Muestra el fallo y, si el proveedor dijo cuánto falta, arranca la cuenta
  /// que mantiene apagado el botón hasta que valga la pena.
  void _fallo(AppError error) {
    _cuenta?.cancel();
    setState(() {
      _error = error;
      _retryIn = error.retryAfter?.inSeconds ?? 0;
    });
    // Sin cuenta regresiva para las esperas largas: el botón queda apagado y
    // la salida son los dos de abajo, cargar a mano o volver.
    if (_retryIn <= 0 || _retryIn > _cuentaMax) return;

    _cuenta = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _retryIn--);
      if (_retryIn <= 0) timer.cancel();
    });
  }

  void _retry() {
    _cuenta?.cancel();
    setState(() {
      _error = null;
      _retryIn = 0;
      _phaseIndex = 0;
      _phase = _opening.first;
    });
    _start();
  }

  /// Salida sin IA: se arma la comida a mano con la foto ya sacada.
  ///
  /// Si ya había un borrador abierto —se entra acá desde el "+" de una comida
  /// que se estaba cargando—, **no se empieza uno nuevo**: solo se le adjunta
  /// la foto y se vuelve. `start` reemplaza el estado entero, así que los ítems
  /// que la persona ya había cargado desaparecían en silencio; y como después
  /// de guardar el `pop` volvía a la pantalla del borrador anterior, que ahora
  /// tenía `draft == null`, quedaba un `Scaffold` con un spinner y sin AppBar
  /// del que solo se salía con el botón atrás del sistema.
  ///
  /// Es la misma regla que ya cumple la pantalla de revisión, que distingue
  /// entre empezar y agregar.
  void _manual() {
    // La comida a mano se arma con la foto del teléfono, no con la del bucket:
    // `photoPathProvider` sigue apuntando al archivo local porque el análisis
    // no llegó a devolver la ruta remota. Así que la copia que subió el intento
    // fallido no la va a nombrar nadie y se borra acá.
    _descartarSubida();
    final target = ref.read(photoTargetProvider);
    final notifier = ref.read(mealDraftProvider.notifier);

    if (ref.read(mealDraftProvider) != null) {
      notifier.setPhoto(ref.read(photoPathProvider));
      context.pop();
      return;
    }

    final DateTime date = target?.date ?? ref.read(selectedDateProvider);
    final MealSlot slot =
        target?.slot ?? MealSlot.forHour(DateTime.now().hour);
    notifier.start(
      slot: slot,
      date: date,
      photoPath: ref.read(photoPathProvider),
    );
    context.pushReplacement(
      '${Routes.mealNew}?slot=${slot.wire}&date=${isoDate(date)}',
    );
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _cuenta?.cancel();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final path = ref.watch(photoPathProvider);
    final animate = !context.motion.reduced;

    return Scaffold(
      backgroundColor: nm.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(context.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: ClipRRect(
                  borderRadius: NmRadius.brLg,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (path != null)
                        Opacity(
                          opacity: 0.45,
                          child: Image.file(File(path), fit: BoxFit.cover),
                        )
                      else
                        ColoredBox(color: nm.surfaceRaised),
                      // Barrido vertical: sugiere lectura, no progreso falso.
                      if (animate)
                        AnimatedBuilder(
                          animation: _sweep,
                          builder: (context, _) => Align(
                            alignment: Alignment(0, _sweep.value * 2 - 1),
                            child: Container(
                              height: 2,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Colors.transparent,
                                    nm.accent,
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: NmSpace.s6),

              if (_error != null) ...<Widget>[
                ErrorState(
                  message: _error!.message,
                  code: _error!.code.wire,
                  onRetry: _retry,
                  // El botón queda a la vista y apagado, contando. Esconderlo
                  // sería peor: la salida desaparecería justo cuando la
                  // persona la está buscando.
                  retryEnabled: _retryIn <= 0,
                  retryLabel: switch (_retryIn) {
                    <= 0 => 'Reintentar',
                    <= _cuentaMax => 'Reintentar en $_retryIn s',
                    _ => 'Reintentar más tarde',
                  },
                ),
                const SizedBox(height: NmSpace.s5),
                NmButton(
                  label: 'Cargar la comida a mano',
                  block: true,
                  onPressed: _manual,
                ),
                const SizedBox(height: NmSpace.s2),
                NmButton.ghost(
                  label: 'Volver',
                  block: true,
                  onPressed: () {
                    _cancelled = true;
                    _descartarSubida();
                    context.pop();
                  },
                ),
              ] else ...<Widget>[
                AnalysisProgress(
                  stage: _stage,
                  elapsedInStage: DateTime.now().difference(_stageStartedAt),
                ),
                const SizedBox(height: NmSpace.s5),
                // Dos líneas reservadas, ocupadas o no. Las frases no miden
                // todas lo mismo y ahora se turnan sin parar: sin la altura
                // fija, la foto de arriba se estira y se encoge en cada
                // cambio. Un salto de layout cada 3 s en una pantalla de
                // espera es justo el nervio que se está tratando de sacar.
                SizedBox(
                  width: double.infinity,
                  // Con el tamaño de letra del sistema, no con el de diseño:
                  // en ×1,3 dos líneas ya no entran en 48 px y la frase se
                  // cortaría por la mitad.
                  height:
                      MediaQuery.textScalerOf(context).scale(NmType.h3.size) *
                      NmType.h3.lineHeight *
                      2,
                  child: Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: context.motion.fade(NmMotion.fast),
                      // El `Align` no es decorativo: `AnimatedSwitcher` apila
                      // sus hijos centrados, así que un texto que mide lo que
                      // dice quedaría centrado y cambiando de lugar en cada
                      // frase.
                      child: Align(
                        key: ValueKey<String>(_label),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: NmTextStyles.from(NmType.h3, color: nm.text),
                        ),
                      ),
                    ),
                  ),
                ),
                // Acá iba una aclaración de que el tiempo restante es una
                // estimación. Era cierta y no ayudaba: le ponía el foco al
                // reloj, que es exactamente lo que la espera no necesita. El
                // "≈" de la barra ya dice lo mismo sin subrayarlo.
                const SizedBox(height: NmSpace.s6),
                NmButton.secondary(
                  label: 'Cancelar',
                  block: true,
                  onPressed: () {
                    _cancelled = true;
                    _descartarSubida();
                    context.pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// S-20 · Revisar análisis. ★
///
/// Ningún dato de IA se guarda sin pasar por el ojo de la persona.
class PhotoReviewScreen extends ConsumerStatefulWidget {
  const PhotoReviewScreen({super.key});

  @override
  ConsumerState<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends ConsumerState<PhotoReviewScreen> {
  bool _saving = false;

  /// Ya se guardó, así que al salir no hay que descartar el borrador.
  bool _committed = false;

  /// Cómo estaba el borrador antes de entrar acá, para poder dejarlo igual si
  /// el análisis se descarta. Es `null` cuando no había ninguno abierto —el
  /// caso del menú Agregar—, y ahí descartar es cerrarlo.
  MealDraft? _previousDraft;

  @override
  void initState() {
    super.initState();
    // Después del primer frame, no en `initState` ni en `didChangeDependencies`:
    // Riverpod prohíbe modificar un provider durante un ciclo de vida del
    // widget y tira *"Tried to modify a provider while the widget tree was
    // building"*. Es el mismo motivo por el que `MealFormScreen` abre su
    // borrador así.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startDraft();
    });
  }

  /// El borrador se abre **al entrar**, no al guardar.
  ///
  /// Antes los ítems vivían en una lista de esta pantalla y el borrador se
  /// armaba recién en `_save`. Con eso, "Agregar un ítem que falta" mandaba al
  /// buscador, el buscador agregaba al borrador… que todavía no existía:
  /// `addItem` sobre `null` no hace nada y no avisa. El alimento elegido se
  /// perdía en silencio y la pantalla volvía igual que antes. Siendo el
  /// borrador la única lista, ese camino funciona sin nada especial.
  void _startDraft() {
    final analysis = ref.read(analysisProvider);
    if (analysis == null) return;
    final target = ref.read(photoTargetProvider);
    final photoPath = ref.read(photoPathProvider);
    final controller = ref.read(mealDraftProvider.notifier);

    _previousDraft = ref.read(mealDraftProvider);

    // Sin foto, la estimación salió de una descripción escrita: se guarda como
    // tal para que el origen del dato no diga algo que no pasó.
    final source = photoPath == null
        ? MealSource.aiText
        : MealSource.aiPhoto;
    final items = <MealItem>[
      for (var i = 0; i < analysis.items.length; i++)
        _toMealItem(analysis.items[i], _previousDraft == null
            ? i
            : _previousDraft!.items.length + i),
    ];

    // Con una comida ya abierta —el análisis se pidió **desde** "Nueva
    // comida"— lo estimado se suma a esa comida. Empezar un borrador nuevo le
    // borraría a la persona los ítems que ya había cargado, y en silencio.
    if (_previousDraft != null) {
      controller.appendAnalysis(
        source: source,
        items: items,
        photoPath: photoPath,
        aiAnalysisId: analysis.id,
      );
      return;
    }

    controller.start(
      // Si se entró por el "+" de una sección, ese slot manda sobre la hora.
      slot: target?.slot ?? MealSlot.forHour(DateTime.now().hour),
      date: target?.date ?? ref.read(selectedDateProvider),
      source: source,
      // Cómo llamó el modelo al plato entero ("Milanesa con puré"). Si no vino
      // ninguno, el borrador arma el título con los ítems y no se guarda nada.
      name: analysis.title,
      photoPath: photoPath,
      aiAnalysisId: analysis.id,
      items: items,
    );
  }

  /// Un ítem estimado por la IA se distingue de uno elegido del catálogo por
  /// tener [MealItem.aiConfidence]. No es un detalle: el badge de confianza
  /// dice cuánta duda tiene el modelo, y ponerle uno a un alimento del catálogo
  /// sería presentar un dato verificado como si fuera una estimación. La
  /// conversión vive en el modelo porque el recálculo hace exactamente la
  /// misma, y dos copias se separan.
  static MealItem _toMealItem(AiAnalysisItem item, int position) =>
      MealItem.fromAnalysis(item, id: _uuid.v4(), position: position);

  /// Se va sin guardar: el borrador vuelve a como estaba antes de entrar.
  ///
  /// Sin borrador previo eso es cerrarlo —si quedara abierto, "Nueva comida"
  /// lo retomaría y aparecería con los ítems de un análisis que se descartó—.
  /// Y si venía de una comida a medio armar, esa comida queda intacta: se
  /// descarta el análisis, no lo que la persona ya había cargado.
  void _discardIfUnsaved() {
    if (_committed) return;
    ref.read(mealDraftProvider.notifier).restore(_previousDraft);
    ref.read(analysisProvider.notifier).state = null;
    ref.read(photoTargetProvider.notifier).state = null;

    // Y la foto que subió el análisis se borra del bucket.
    //
    // Analizar la sube sí o sí —la Edge Function la lee de ahí—, así que
    // descartar la estimación, que es de lo más común cuando el número no
    // convence, dejaba en el servidor una foto que ya no pertenece a ningún
    // registro: no se muestra, no se borra y no hay forma de encontrarla.
    //
    // Sin `await` y sin avisar: la persona ya se fue de la pantalla y esto no
    // cambia nada de lo que ve. Si el borrado falla queda una foto, que es
    // molesto y no grave; lo que importaba era que dejaran de acumularse una
    // por cada análisis descartado.
    final path = ref.read(photoPathProvider);
    ref.read(photoPathProvider.notifier).state = null;
    final photos = ref.read(photoSyncProvider);
    if (path != null && photos != null && PhotoSyncService.isRemotePath(path)) {
      unawaited(
        photos
            .delete(bucket: PhotoBucket.meal, path: path)
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _save() async {
    final draft = ref.read(mealDraftProvider);
    if (draft == null || draft.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final date = draft.date;

    await repo.saveMeal(draft.toMeal(syncStatus: SyncStatus.synced));
    _committed = true;
    ref.read(mealDraftProvider.notifier).clear();
    ref.read(analysisProvider.notifier).state = null;
    ref.read(photoTargetProvider.notifier).state = null;
    // Inicio queda parado en el día donde acaba de caer la comida: guardar
    // algo y no verlo en ningún lado se lee como que no se guardó.
    ref.read(selectedDateProvider.notifier).set(date);

    if (!mounted) return;
    setState(() => _saving = false);
    context.go(Routes.home);
    NmSnackbar.show(
      context,
      draft.source == MealSource.aiText
          ? 'Comida guardada desde la descripción'
          : 'Comida guardada desde la foto',
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final analysis = ref.watch(analysisProvider);
    final draft = ref.watch(mealDraftProvider);
    final path = ref.watch(photoPathProvider);
    final controller = ref.read(mealDraftProvider.notifier);

    if (analysis == null) {
      return NmScreen(
        title: 'Revisar análisis',
        child: ErrorState(
          message: 'No pudimos leer la estimación. Podés cargar la comida a '
              'mano.',
          onRetry: () => context.go(Routes.mealNew),
          retryLabel: 'Cargar a mano',
        ),
      );
    }

    // El borrador se abre después del primer frame, así que este es ese frame.
    if (draft == null) {
      return Scaffold(
        backgroundColor: nm.bg,
        appBar: const NmModalHeader(title: 'Revisar análisis'),
        body: const Center(child: NmSpinner()),
      );
    }

    final items = draft.items;
    final lowConfidence = items.any(
      (i) => i.aiConfidence != null && i.aiConfidence! < 0.5,
    );

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _discardIfUnsaved();
      },
      child: Scaffold(
        backgroundColor: nm.bg,
        appBar: const NmModalHeader(title: 'Revisar análisis'),
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
                          if (path != null)
                            ClipRRect(
                              borderRadius: NmRadius.brMd,
                              child: ZoomablePhoto(
                                file: File(path),
                                child: Image.file(
                                  File(path),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          const SizedBox(height: NmSpace.s4),
                          AiEstimateBanner(
                            confidenceAvg: analysis.confidenceAvg,
                          ),
                          const SizedBox(height: NmSpace.s6),
                          Text(
                            'Momento del día',
                            style: NmTextStyles.from(
                              NmType.caption,
                              color: nm.textMuted,
                            ),
                          ),
                          const SizedBox(height: NmSpace.s2),
                          Wrap(
                            spacing: NmSpace.s2,
                            children: <Widget>[
                              for (final slot in MealSlot.values)
                                NmChip(
                                  label: slot.label,
                                  selected: slot == draft.slot,
                                  semanticsInRadioGroup: true,
                                  onTap: () => controller.setSlot(slot),
                                ),
                            ],
                          ),
                          const SizedBox(height: NmSpace.s6),
                          const NmSectionHeader(title: 'Ítems detectados'),
                          for (var i = 0; i < items.length; i++)
                            StaggeredItem(
                              index: i,
                              child: _AiItemRow(
                                // La clave es el id del ítem y no su posición:
                                // sin esto, borrar el primero le pasa el estado
                                // (y el controlador de texto) del borrado al que
                                // queda en su lugar.
                                key: ValueKey<String>(items[i].id),
                                item: items[i],
                                onChanged: (updated) =>
                                    controller.replaceItem(i, updated),
                                onRemove: () =>
                                    controller.removeItem(items[i].id),
                              ),
                            ),
                          const SizedBox(height: NmSpace.s4),
                          NmButton.secondary(
                            label: 'Agregar un ítem que falta',
                            block: true,
                            icon: PhosphorIcons.plus(),
                            onPressed: () => context.push(
                              '${Routes.foodSearch}?target=ai_item',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              MealTotalsBar(
                kcal: draft.totalKcal,
                proteinG: draft.proteinG,
                carbsG: draft.carbsG,
                fatG: draft.fatG,
                child: NmButton(
                  label: lowConfidence ? 'Guardar igual' : 'Guardar comida',
                  block: true,
                  loading: _saving,
                  onPressed: items.isEmpty ? null : _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila editable del análisis.
///
/// Tiene que ser `StatefulWidget` y el controlador vivir acá adentro. Antes se
/// creaba un `TextEditingController` nuevo **en cada build**, y como cada tecla
/// dispara un `setState` del padre, pasaba esto: se rehacía el campo, el texto
/// se volvía a calcular desde la cantidad ya modificada y el cursor saltaba al
/// principio. Escribir "150" daba cualquier cosa menos 150, y encima cada
/// controlador quedaba sin liberar.
class _AiItemRow extends StatefulWidget {
  const _AiItemRow({
    required this.item,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final MealItem item;
  final ValueChanged<MealItem> onChanged;
  final VoidCallback onRemove;

  @override
  State<_AiItemRow> createState() => _AiItemRowState();
}

class _AiItemRowState extends State<_AiItemRow> {
  late final TextEditingController _quantity = TextEditingController(
    text: _format(widget.item.quantity),
  );

  /// La cantidad con la que se calcularon los macros que están en pantalla.
  /// Se guarda al empezar a editar para que reescalar sea siempre contra el
  /// original y no contra el resultado del tecleo anterior.
  late final double _base = widget.item.quantity;
  late final MealItem _baseItem = widget.item;

  static String _format(double q) => q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toString().replaceAll('.', ',');

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    // Campo vacío o a medio escribir ("1," mientras se tipea "1,5"): no se
    // toca nada todavía. Antes cualquier tecla intermedia reescalaba los
    // macros y el número quedaba arrastrado.
    if (parsed == null || parsed <= 0) return;
    if (_base <= 0) return;

    final ratio = parsed / _base;
    widget.onChanged(
      _baseItem.copyWith(
        quantity: parsed,
        kcal: (_baseItem.kcal * ratio).round(),
        proteinG: _baseItem.proteinG * ratio,
        carbsG: _baseItem.carbsG * ratio,
        fatG: _baseItem.fatG * ratio,
        // Insumo para `ai_result_corrected` (F-06 paso 6). Se marca el ítem que
        // se corrigió y no todos, como antes: un solo cambio ensuciaba la
        // medición al dejar la comida entera marcada como corregida.
        wasAiCorrected: _baseItem.aiConfidence != null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final item = widget.item;
    final confidence = item.aiConfidence;
    final low = confidence != null && confidence < 0.5;

    return Padding(
      padding: const EdgeInsets.only(bottom: NmSpace.s3),
      child: NmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.name,
                    style: NmTextStyles.from(NmType.body, color: nm.text),
                  ),
                ),
                // El badge de confianza es del modelo. Un alimento que la
                // persona eligió del catálogo no tiene confianza que mostrar
                // —tiene una tabla nutricional detrás— y ponerle una sería
                // presentar un dato verificado como si fuera una estimación.
                if (confidence != null)
                  ConfidenceBadge(value: confidence)
                else
                  const NmTag(
                    label: 'Del catálogo',
                    variant: NmTagVariant.outline,
                  ),
                NmIconButton(
                  icon: PhosphorIcons.trash(),
                  onPressed: widget.onRemove,
                  tooltip: 'Quitar ${item.name}',
                  size: NmIconSize.md,
                ),
              ],
            ),
            const SizedBox(height: NmSpace.s3),
            Row(
              children: <Widget>[
                Expanded(
                  child: NmTextField(
                    label: 'Cantidad',
                    controller: _quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    error: low ? 'Revisá esta cantidad' : null,
                    onChanged: _onChanged,
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Unidad',
                        style: NmTextStyles.from(
                          NmType.caption,
                          color: nm.textMuted,
                        ),
                      ),
                      const SizedBox(height: NmSpace.s2),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: NmSpace.s3,
                        ),
                        child: Text(
                          item.unit,
                          style: NmTextStyles.from(
                            NmType.body,
                            color: nm.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: NmSpace.s3),
                Text(
                  '${item.kcal} kcal',
                  style: NmTextStyles.from(NmType.bodySm, color: nm.text).tnum,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
