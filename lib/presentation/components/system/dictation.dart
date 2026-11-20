import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../data/local/dictation_gateway.dart';
import 'overlays.dart';

/// Un campo de texto que además se puede dictar.
///
/// Envuelve al campo y le pone el micrófono adentro, más la línea que dice qué
/// está pasando. Va junto y no separado porque el estado del dictado **es
/// estado de ese campo**: quien mira quiere saber si lo que dice está entrando
/// ahí, y eso se contesta al lado del campo, no en una esquina de la pantalla.
///
/// Se toca una vez y escucha; se toca de nuevo, se hace silencio o pasa el
/// minuto, y para. Lo dictado se **suma** a lo que ya había escrito, no lo
/// pisa: quien escribió media frase y después habla no pierde la mitad.
///
/// Si el teléfono no puede dictar —sin motor de reconocimiento, o con el
/// permiso negado— el micrófono desaparece y queda un campo de texto normal.
/// La primera vez el permiso lo pide Android al tocarlo, que es cuando se
/// entiende para qué es.
class NmDictationField extends StatefulWidget {
  const NmDictationField({
    required this.controller,
    required this.builder,
    this.onChanged,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;

  /// Arma el campo con el micrófono que se le pasa. Es un builder y no un
  /// campo fijo porque cada pantalla usa su propio `NmTextField` con su
  /// etiqueta, su pista y su largo máximo.
  final Widget Function(BuildContext context, Widget? microphone) builder;

  /// Se avisa con el texto ya actualizado, para que la pantalla haga lo mismo
  /// que si se hubiera tecleado (limpiar el error, habilitar el botón).
  final ValueChanged<String>? onChanged;
  final bool enabled;

  /// Dónde tiene sentido ofrecerlo. En escritorio y en los tests no hay motor
  /// de reconocimiento y el botón sería decorado.
  static bool get isSupportedPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<NmDictationField> createState() => _NmDictationFieldState();
}

class _NmDictationFieldState extends State<NmDictationField> {
  final DictationGateway _dictation = DictationGateway();

  DictationState _state = DictationState.idle;

  /// Lo que había escrito cuando empezó a hablar. El reconocedor devuelve la
  /// frase entera de la sesión en cada corrección, así que sin esto cada
  /// corrección duplicaría lo anterior.
  String _base = '';

  /// Si ya entró alguna palabra en esta sesión. Sirve para no decir "no
  /// entendimos nada" cuando en realidad entró algo.
  bool _algoEntro = false;

  /// Se apaga solo si el teléfono resulta no poder dictar. No arranca en
  /// `false` porque saberlo cuesta inicializar el motor, y eso es justo lo que
  /// dispara el pedido de permiso: se descubre al primer toque.
  bool _available = true;

  @override
  void dispose() {
    _dictation.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_state != DictationState.idle) {
      await _dictation.stop();
      return;
    }

    // Se arranca desde lo que hay escrito, con un espacio de por medio si hace
    // falta. `trimRight` para no dejar dos.
    _base = widget.controller.text.trimRight();
    _algoEntro = false;

    final started = await _dictation.start(
      onText: _write,
      onState: (next) {
        if (!mounted) return;
        setState(() => _state = next);
        if (next == DictationState.idle && !_algoEntro) {
          // Terminó sin haber entendido nada. Se dice, porque el caso se ve
          // igual que "todavía no empecé" y deja a la persona esperando.
          NmSnackbar.show(
            context,
            'No llegamos a entender nada. Probá de nuevo, más cerca del '
            'micrófono.',
          );
        }
      },
    );
    if (!mounted) return;

    if (!started) {
      setState(() {
        _state = DictationState.idle;
        _available = _dictation.isAvailable;
      });
      NmSnackbar.show(
        context,
        _dictation.isAvailable
            ? 'No pudimos abrir el micrófono. Escribilo y listo.'
            : 'Para dictar hace falta el permiso de micrófono. Podés '
                  'escribirlo igual.',
      );
    }
  }

  void _write(String words) {
    if (!mounted || words.trim().isEmpty) return;
    _algoEntro = true;
    final texto = _base.isEmpty ? words : '$_base $words';
    widget.controller.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
    widget.onChanged?.call(texto);
  }

  bool get _mostrarMicrofono =>
      _available && NmDictationField.isSupportedPlatform;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        widget.builder(
          context,
          _mostrarMicrofono
              ? _MicButton(
                  state: _state,
                  onPressed: widget.enabled ? _toggle : null,
                )
              : null,
        ),
        // La línea de estado. Aparece solo mientras pasa algo y ocupa el lugar
        // del texto de ayuda, así que no mueve nada de lo que está abajo.
        if (_state != DictationState.idle)
          Padding(
            padding: const EdgeInsets.only(top: NmSpace.s2),
            child: Row(
              children: <Widget>[
                _PulsingDot(color: nm.accent, active: _state == DictationState.listening),
                const SizedBox(width: NmSpace.s2),
                Expanded(
                  child: Text(
                    _state == DictationState.starting
                        ? 'Abriendo el micrófono…'
                        : 'Te escuchamos. Tocá el micrófono para terminar.',
                    style: NmTextStyles.from(NmType.caption, color: nm.accent),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// El micrófono, con los tres estados a la vista.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.state, required this.onPressed});

  final DictationState state;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final escuchando = state != DictationState.idle;

    return IconButton(
      onPressed: onPressed,
      // El estado se dice con palabras y no solo con el color: es un botón que
      // cambia lo que hace al tocarlo, y con lector de pantalla el color no
      // existe.
      tooltip: escuchando ? 'Terminar de dictar' : 'Dictar',
      icon: AnimatedContainer(
        duration: context.motion.fade(NmMotion.fast),
        curve: NmMotion.ease,
        padding: const EdgeInsets.all(NmSpace.s2),
        decoration: BoxDecoration(
          // Relleno mientras escucha: el cambio de color de un ícono solo es
          // demasiado sutil para el dato más importante de la pantalla en ese
          // momento, que es si el micrófono está abierto.
          color: escuchando ? nm.accentFill : Colors.transparent,
          borderRadius: BorderRadius.circular(NmRadius.full),
        ),
        child: Icon(
          escuchando
              ? PhosphorIcons.microphone(PhosphorIconsStyle.fill)
              : PhosphorIcons.microphone(),
          size: NmIconSize.md,
          color: escuchando ? nm.accentOnFill : nm.textMuted,
        ),
      ),
    );
  }
}

/// El punto que late mientras el micrófono está abierto.
///
/// Es lo único de la pantalla que se mueve, y por eso alcanza: un elemento
/// animado dice "esto está pasando ahora" mejor que cualquier texto. Se queda
/// quieto —pero visible— con las animaciones reducidas.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.motion.reduced || !widget.active) {
      return _dot(widget.active ? 1 : 0.4);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _dot(0.35 + _controller.value * 0.65),
    );
  }

  Widget _dot(double opacity) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: widget.color.withValues(alpha: opacity),
      shape: BoxShape.circle,
    ),
  );
}
