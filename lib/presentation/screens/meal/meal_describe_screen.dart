import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../components/feedback/feedback.dart';
import '../../components/system/buttons.dart';
import '../../components/system/dictation.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../photo/photo_screens.dart';

/// Describir la comida en una frase y que la IA la estime.
///
/// Es la respuesta a lo que el catálogo de productos envasados no puede
/// contestar. Open Food Facts sabe de códigos de barras: un asado, una
/// milanesa o dos empanadas no tienen ninguno, y son la mayor parte de lo que
/// se come acá.
///
/// El resultado cae en la **misma pantalla de revisión** que el análisis por
/// foto: nada estimado por IA se guarda sin pasar por el ojo de la persona.
class MealDescribeScreen extends ConsumerStatefulWidget {
  const MealDescribeScreen({super.key});

  @override
  ConsumerState<MealDescribeScreen> createState() =>
      _MealDescribeScreenState();
}

class _MealDescribeScreenState extends ConsumerState<MealDescribeScreen> {
  final TextEditingController _text = TextEditingController();
  bool _busy = false;
  AppError? _error;

  /// Un solo ejemplo, y distinto del que ya muestra el campo vacío.
  ///
  /// Cuatro chips ocupaban media pantalla y empujaban el botón de estimar fuera
  /// de la vista: para entender cómo se escribe alcanza con uno.
  static const String _ejemplo = 'milanesa con puré y una ensalada chica';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _estimate() async {
    final description = _text.text.trim();
    if (description.length < 3) {
      setState(
        () => _error = const AppError(
          code: ApiErrorCode.validation,
          message: 'Contanos qué comiste, con un poco más de detalle.',
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final analysis = await ref
          .read(repositoryProvider)
          .analyzeText(description: description);
      if (!mounted) return;

      // La foto queda explícitamente en null: esta estimación no tiene imagen
      // y la revisión no debe mostrar la de un análisis anterior.
      ref.read(photoPathProvider.notifier).state = null;
      ref.read(analysisProvider.notifier).state = analysis;
      context.pushReplacement(Routes.photoReview);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error;
      });
    } on Object catch (error) {
      // Sin esta rama, cualquier fallo que no fuera `AppError` —una respuesta
      // con una forma inesperada alcanza: `_toAnalysis` castea— dejaba `_busy`
      // en true para siempre. El botón giraba, no había error, y no había
      // salida más que cerrar la pantalla. Es el mismo agujero que ya se tapó
      // en la espera del análisis por foto: una espera eterna es la peor forma
      // de contar un fallo, porque no se distingue de estar por terminar.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppError(
          code: ApiErrorCode.server,
          message: 'No pudimos estimar la comida. Probá de nuevo o cargala a '
              'mano.',
          requestId: error.toString(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return NmScreen(
      title: 'Describir la comida',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),
          Text(
            'Escribilo como se lo contarías a alguien. La IA lo convierte en '
            'ítems con sus cantidades y vos los revisás antes de guardar.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),

          // Contarlo en voz alta es la forma corta de este campo: se toca el
          // micrófono, se dice, y lo dicho queda escrito acá. De ahí en
          // adelante el camino es el mismo de siempre —estimar, revisar,
          // guardar—, así que no hay un paso más ni una pantalla nueva.
          NmDictationField(
            controller: _text,
            enabled: !_busy,
            onChanged: (_) => setState(() => _error = null),
            builder: (context, microphone) => NmTextField(
              label: 'Qué comiste',
              controller: _text,
              hint: 'dos empanadas de carne y una coca',
              autofocus: true,
              maxLines: 3,
              maxLength: 400,
              suffixIcon: microphone,
              onChanged: (_) => setState(() => _error = null),
            ),
          ),

          const SizedBox(height: NmSpace.s3),
          NmChip(
            label: _ejemplo,
            selected: false,
            onTap: () => setState(() {
              _text.text = _ejemplo;
              _error = null;
            }),
          ),

          if (_error != null) ...<Widget>[
            const SizedBox(height: NmSpace.s5),
            ErrorState(message: _error!.message, code: _error!.code.wire),
          ],

          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Estimar',
            block: true,
            icon: PhosphorIcons.sparkle(),
            loading: _busy,
            // La cuota la cuenta el servidor: si se llegó al límite, el error
            // que devuelve se muestra arriba con su mensaje.
            onPressed: _estimate,
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            'Es una estimación, no una medición: revisá los números antes de '
            'guardar.',
            style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
          ),
        ],
      ),
    );
  }
}
