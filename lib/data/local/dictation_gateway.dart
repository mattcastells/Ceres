import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// En qué estado está el dictado, para que la pantalla lo pueda mostrar.
enum DictationState {
  /// Todavía no se tocó nada, o ya terminó.
  idle,

  /// Se pidió empezar y el motor está abriendo el micrófono. Dura entre medio
  /// segundo y dos, y es justo el rato en que uno empieza a hablar creyendo
  /// que ya está grabando.
  starting,

  /// Escuchando de verdad.
  listening,
}

/// Dictado: lo que se dice al micrófono, convertido en texto.
///
/// Lo hace el reconocedor del propio teléfono (`SpeechRecognizer` de Android),
/// no un servicio nuestro: el audio no pasa por Ceres, no se guarda en
/// ningún lado y no hay un archivo que subir. Lo único que llega a la app es la
/// frase ya transcripta, que es exactamente lo que la persona habría escrito.
///
/// Está acá y no adentro del widget para que la pantalla no sepa de
/// `speech_to_text`: la del micrófono es la clase de dependencia que conviene
/// tener detrás de una puerta, porque falla de maneras muy distintas según el
/// teléfono —sin motor de reconocimiento, sin permiso, sin idioma instalado— y
/// ninguna de esas puede llegar a la interfaz como una excepción suelta.
///
/// ## Por qué el estado se escucha y no se supone
///
/// La primera versión daba por terminada la sesión cuando llegaba un resultado
/// marcado como final. No alcanza: el motor de Android también deja de
/// escuchar por silencio, por timeout o por un error, y en esos casos **no
/// manda ningún resultado**. El botón se quedaba encendido para siempre y la
/// persona seguía hablándole a un micrófono cerrado. Por eso se escucha
/// `onStatus`, que es lo único que dice la verdad sobre si el micrófono está
/// abierto.
class DictationGateway {
  DictationGateway({SpeechToText? engine}) : _engine = engine ?? SpeechToText();

  final SpeechToText _engine;

  /// Cuánto silencio corta el dictado.
  ///
  /// Cinco segundos y no tres: describir una comida tiene pausas —uno se
  /// acuerda del postre a mitad de frase— y con tres se cortaba en la mitad.
  static const Duration pauseFor = Duration(seconds: 5);

  /// Techo duro de una sesión. Nadie describe una comida durante un minuto, y
  /// un micrófono abierto para siempre es lo peor que puede quedar prendido.
  static const Duration listenFor = Duration(seconds: 60);

  bool _initialized = false;
  bool _unavailable = false;
  DictationState _state = DictationState.idle;

  ValueChanged<DictationState>? _onState;
  ValueChanged<String>? _onText;

  DictationState get state => _state;
  bool get isBusy => _state != DictationState.idle;

  /// Si este teléfono puede dictar. `false` sin motor de reconocimiento o con
  /// el permiso denegado: ahí el micrófono ni se ofrece, en vez de ofrecer un
  /// botón que siempre falla.
  bool get isAvailable => !_unavailable;

  /// Prepara el motor. Devuelve `false` si no se puede dictar en este teléfono.
  ///
  /// **Es también donde Android pide el permiso de micrófono**, así que se
  /// llama al tocar el botón y no al abrir la pantalla: un permiso que aparece
  /// solo, antes de que nadie pida nada, es la forma más rápida de que lo
  /// nieguen para siempre.
  Future<bool> prepare() async {
    if (_initialized) return !_unavailable;
    try {
      final ok = await _engine.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      _initialized = true;
      _unavailable = !ok;
      return ok;
    } on Object {
      _initialized = true;
      _unavailable = true;
      return false;
    }
  }

  void _emit(DictationState next) {
    if (_state == next) return;
    _state = next;
    _onState?.call(next);
  }

  /// El estado que informa el motor: `listening`, `notListening`, `done`.
  ///
  /// Es la fuente de verdad de si el micrófono está abierto. Los nombres son
  /// del plugin y llegan como texto, así que se comparan como texto.
  void _onStatus(String status) {
    if (status == SpeechToText.listeningStatus) {
      _emit(DictationState.listening);
      return;
    }
    // `notListening` es "dejó de escuchar pero todavía está procesando" y
    // `done` es "terminó del todo". Para quien mira la pantalla los dos son lo
    // mismo: el micrófono ya no está tomando nada.
    _emit(DictationState.idle);
  }

  void _onError(SpeechRecognitionError error) {
    // `error_no_match` y `error_speech_timeout` son "no se entendió" y "no
    // dijiste nada": no inhabilitan el dictado, pasan todo el tiempo y no son
    // un problema del teléfono. Los permanentes sí apagan el botón.
    if (error.permanent && error.errorMsg != 'error_no_match') {
      _unavailable = true;
    }
    _emit(DictationState.idle);
  }

  /// Empieza a escuchar. [onText] recibe la frase **completa** de la sesión
  /// cada vez que el reconocedor la corrige, no los pedazos sueltos.
  ///
  /// [onState] avisa de cada cambio: cuándo abrió el micrófono de verdad y
  /// cuándo lo cerró, sea porque lo pidió la persona, por silencio o por un
  /// fallo. Es lo que el botón necesita para no quedarse encendido solo.
  Future<bool> start({
    required ValueChanged<String> onText,
    required ValueChanged<DictationState> onState,
  }) async {
    _onText = onText;
    _onState = onState;
    if (!await prepare()) {
      _emit(DictationState.idle);
      return false;
    }

    // Se avisa antes de abrir: entre el toque y el micrófono abierto pasa
    // hasta un par de segundos, y sin decirlo la persona habla en ese hueco y
    // lo dicho se pierde.
    _emit(DictationState.starting);
    try {
      await _engine.listen(
        onResult: (SpeechRecognitionResult result) {
          _onText?.call(result.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          // Parciales: la frase aparece mientras se habla. Sin esto la pantalla
          // se queda muda hasta el final y no se sabe si está escuchando.
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: true,
          pauseFor: pauseFor,
          listenFor: listenFor,
          localeId: await _localeId(),
        ),
      );
      return true;
    } on Object {
      _unavailable = true;
      _emit(DictationState.idle);
      return false;
    }
  }

  Future<void> stop() async {
    _emit(DictationState.idle);
    if (!_initialized) return;
    try {
      await _engine.stop();
    } on Object {
      // Cortar el micrófono no puede fallar hacia afuera: el peor caso es que
      // el motor ya estuviera cortado.
    }
  }

  Future<void> cancel() async {
    _onText = null;
    _onState = null;
    _state = DictationState.idle;
    if (!_initialized) return;
    try {
      await _engine.cancel();
    } on Object {
      // Igual que `stop`.
    }
  }

  /// Español rioplatense si el teléfono lo tiene; cualquier español si no.
  ///
  /// Sin esto el reconocedor usa el idioma del sistema, que puede no ser el que
  /// se está hablando — y "dos empanadas de carne" leído en inglés no se parece
  /// a nada.
  Future<String?> _localeId() async {
    try {
      final locales = await _engine.locales();
      if (locales.isEmpty) return null;
      for (final wanted in const <String>['es_AR', 'es-AR', 'es_419']) {
        for (final locale in locales) {
          if (locale.localeId == wanted) return locale.localeId;
        }
      }
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith('es')) {
          return locale.localeId;
        }
      }
      return null;
    } on Object {
      return null;
    }
  }
}
