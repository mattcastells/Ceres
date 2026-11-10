import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/motion.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/dates.dart';

/// Campo de texto del sistema. El error va **debajo** del campo y se anuncia
/// como región viva; nunca se comunica solo con el borde (§7).
class NmTextField extends StatelessWidget {
  const NmTextField({
    required this.label,
    this.controller,
    this.onChanged,
    this.error,
    this.hint,
    this.helper,
    this.suffix,
    this.suffixIcon,
    this.prefixIcon,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.inputFormatters,
    this.onSubmitted,
    this.focusNode,
    super.key,
  });

  final String label;
  /// El controlador lo pone quien usa el campo, y **tiene que sobrevivir a los
  /// rebuilds**: crearlo dentro de un `build` hace que cada tecla lo reemplace
  /// y el cursor vuelva al principio. Antes había además un parámetro `value`
  /// que no se usaba en ningún lado y sugería que se podía manejar el texto
  /// sin controlador; se sacó para que no invite a repetir el error.
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? error;
  final String? hint;
  final String? helper;
  final String? suffix;

  /// Una acción adentro del campo, al final. La usa el micrófono de dictado:
  /// vive ahí y no como un botón aparte porque es una forma de escribir en
  /// **este** campo, no una función nueva de la pantalla.
  final Widget? suffixIcon;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          enabled: enabled,
          autofocus: autofocus,
          obscureText: obscureText,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          style: NmTextStyles.from(NmType.body, color: nm.text).tnum,
          cursorColor: nm.accent,
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            errorText: null,
            prefixIcon: prefixIcon == null
                ? null
                : Icon(prefixIcon, size: NmIconSize.md, color: nm.textMuted),
            suffixText: suffix,
            suffixIcon: suffixIcon,
            suffixStyle: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
            enabledBorder: OutlineInputBorder(
              borderRadius: NmRadius.brMd,
              borderSide: BorderSide(
                color: error == null ? nm.divider : nm.danger,
              ),
            ),
          ),
        ),
        if (error != null)
          _FieldMessage(text: error!, color: nm.danger, assertive: true)
        else if (helper != null)
          _FieldMessage(text: helper!, color: nm.textMuted),
      ],
    );
  }
}

/// El mensaje entra con fundido + 4 px hacia abajo. **Sin sacudida** — la
/// sacudida lee como reproche (21-motion §5).
class _FieldMessage extends StatelessWidget {
  const _FieldMessage({
    required this.text,
    required this.color,
    this.assertive = false,
  });

  final String text;
  final Color color;
  final bool assertive;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return Semantics(
      liveRegion: assertive,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<String>(text),
        tween: Tween<double>(begin: 0, end: 1),
        duration: motion.fade(NmMotion.fast),
        curve: NmMotion.ease,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, motion.reduced ? 0 : 4 * (1 - t)),
            child: child,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: NmSpace.s2),
          child: Text(
            text,
            style: NmTextStyles.from(NmType.caption, color: color),
          ),
        ),
      ),
    );
  }
}

/// Campo numérico con teclado numérico y sufijo de unidad.
class NmNumberField extends StatelessWidget {
  const NmNumberField({
    required this.label,
    required this.controller,
    this.onChanged,
    this.error,
    this.helper,
    this.suffix,
    this.decimals = 0,
    this.enabled = true,
    this.autofocus = false,
    this.hint,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? error;
  final String? helper;
  final String? suffix;
  final int decimals;
  final bool enabled;
  final bool autofocus;
  final String? hint;

  @override
  Widget build(BuildContext context) => NmTextField(
    label: label,
    controller: controller,
    onChanged: onChanged,
    error: error,
    helper: helper,
    suffix: suffix,
    hint: hint,
    enabled: enabled,
    autofocus: autofocus,
    keyboardType: TextInputType.numberWithOptions(decimal: decimals > 0),
    inputFormatters: <TextInputFormatter>[
      FilteringTextInputFormatter.allow(
        decimals > 0 ? RegExp(r'[\d,.]') : RegExp(r'\d'),
      ),
    ],
  );
}

/// Campo de contraseña con alternancia de visibilidad.
class NmPasswordField extends StatefulWidget {
  const NmPasswordField({
    required this.label,
    required this.controller,
    this.onChanged,
    this.error,
    this.helper,
    this.textInputAction,
    this.onSubmitted,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? error;
  final String? helper;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<NmPasswordField> createState() => _NmPasswordFieldState();
}

class _NmPasswordFieldState extends State<NmPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.label,
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        TextField(
          controller: widget.controller,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          obscureText: !_visible,
          textInputAction: widget.textInputAction,
          autofillHints: const <String>[AutofillHints.password],
          style: NmTextStyles.from(NmType.body, color: nm.text),
          cursorColor: nm.accent,
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: NmRadius.brMd,
              borderSide: BorderSide(
                color: widget.error == null ? nm.divider : nm.danger,
              ),
            ),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _visible = !_visible),
              tooltip: _visible ? 'Ocultar contraseña' : 'Mostrar contraseña',
              icon: Icon(
                _visible ? PhosphorIcons.eyeSlash() : PhosphorIcons.eye(),
                size: NmIconSize.md,
                color: nm.textMuted,
              ),
            ),
          ),
        ),
        if (widget.error != null)
          _FieldMessage(text: widget.error!, color: nm.danger, assertive: true)
        else if (widget.helper != null)
          _FieldMessage(text: widget.helper!, color: nm.textMuted),
      ],
    );
  }
}

/// Segmentado de 2–4 opciones.
class NmSegmentedControl<T> extends StatelessWidget {
  const NmSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: nm.surfaceRaised,
        borderRadius: NmRadius.brMd,
        border: Border.all(color: nm.divider),
      ),
      child: Row(
        children: options.map((option) {
          final selected = option.$1 == value;
          return Expanded(
            child: Semantics(
              selected: selected,
              inMutuallyExclusiveGroup: true,
              label: option.$2,
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: () => onChanged(option.$1),
                  child: AnimatedContainer(
                    duration: context.motion.fade(NmMotion.instant),
                    curve: NmMotion.ease,
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? nm.accentFill : Colors.transparent,
                      borderRadius: BorderRadius.circular(NmRadius.sm + 2),
                    ),
                    child: Text(
                      option.$2,
                      textAlign: TextAlign.center,
                      style: NmTextStyles.from(
                        NmType.bodySm,
                        color: selected ? nm.accentOnFill : nm.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Fila con switch. El control nunca usa el estilo por defecto del SO.
class NmSwitchRow extends StatelessWidget {
  const NmSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      toggled: value,
      label: title,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: NmRadius.brMd,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: NmLayout.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NmSpace.s3,
              vertical: NmSpace.s2,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: NmTextStyles.from(NmType.body, color: nm.text),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opción de un grupo de radios, con descripción y detalle opcional.
class NmRadioRow<T> extends StatelessWidget {
  const NmRadioRow({
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final selected = value == groupValue;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: subtitle == null ? title : '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: NmRadius.brMd,
          child: AnimatedContainer(
            duration: context.motion.fade(NmMotion.instant),
            constraints: const BoxConstraints(
              minHeight: NmLayout.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NmSpace.s4,
              vertical: NmSpace.s3,
            ),
            decoration: BoxDecoration(
              color: selected ? nm.accentFill : nm.surface,
              borderRadius: NmRadius.brMd,
              border: Border.all(color: selected ? nm.accent : nm.divider),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? PhosphorIcons.radioButton(PhosphorIconsStyle.fill)
                      : PhosphorIcons.circle(),
                  size: NmIconSize.lg,
                  color: selected ? nm.accent : nm.textMuted,
                ),
                const SizedBox(width: NmSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        title,
                        style: NmTextStyles.from(
                          NmType.body,
                          color: selected ? nm.accentOnFill : nm.text,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: NmTextStyles.from(
                            NmType.caption,
                            color: nm.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Casilla con etiqueta larga (términos del registro).
class NmCheckboxRow extends StatelessWidget {
  const NmCheckboxRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: NmRadius.brMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NmSpace.s2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: NmSpace.s2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: NmSpace.s3),
                child: Text(
                  label,
                  style: NmTextStyles.from(NmType.bodySm, color: nm.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Selector de fecha con el formato del sistema y el tema de la app.
class NmDateField extends StatelessWidget {
  const NmDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.initialDate,
    this.error,
    this.helper,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;

  /// Dónde abrir el calendario cuando todavía no hay nada elegido.
  ///
  /// Sin esto abre en hoy, que para una fecha de nacimiento son treinta años de
  /// navegación hacia atrás en el primer paso de un alta obligatoria.
  final DateTime? initialDate;
  final String? error;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
        ),
        const SizedBox(height: NmSpace.s2),
        InkWell(
          borderRadius: NmRadius.brMd,
          onTap: () async {
            final first = firstDate ?? DateTime(1920);
            final last = lastDate ?? DateTime.now();
            // `showDatePicker` lanza si la fecha inicial queda fuera del
            // rango, y un valor viejo —un nacimiento sincronizado de antes de
            // que existiera el tope— puede estarlo.
            var initial = value ?? initialDate ?? DateTime.now();
            if (initial.isBefore(first)) initial = first;
            if (initial.isAfter(last)) initial = last;
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
              locale: const Locale('es', 'AR'),
            );
            if (picked != null) onChanged(picked);
          },
          child: Container(
            constraints: const BoxConstraints(
              minHeight: NmLayout.minTouchTarget,
            ),
            padding: const EdgeInsets.symmetric(horizontal: NmSpace.s4),
            decoration: BoxDecoration(
              color: nm.surface,
              borderRadius: NmRadius.brMd,
              border: Border.all(
                color: error == null ? nm.divider : nm.danger,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    value == null ? 'Elegir fecha' : numericDate(value!),
                    style: NmTextStyles.from(
                      NmType.body,
                      color: value == null ? nm.textMuted : nm.text,
                    ).tnum,
                  ),
                ),
                Icon(
                  PhosphorIcons.calendarBlank(),
                  size: NmIconSize.md,
                  color: nm.textMuted,
                ),
              ],
            ),
          ),
        ),
        if (error != null)
          _FieldMessage(text: error!, color: nm.danger, assertive: true)
        else if (helper != null)
          _FieldMessage(text: helper!, color: nm.textMuted),
      ],
    );
  }
}

/// "Paso N de M" en un flujo de varios pasos.
class StepIndicator extends StatelessWidget {
  const StepIndicator({required this.current, required this.total, super.key});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      value: 'paso $current de $total',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Paso $current de $total',
              style: NmTextStyles.from(NmType.overline, color: nm.textMuted),
            ),
            const SizedBox(height: NmSpace.s2),
            Row(
              children: List<Widget>.generate(total, (i) {
                final done = i < current;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: i == total - 1 ? 0 : NmSpace.s1,
                    ),
                    child: AnimatedContainer(
                      duration: context.motion.move(NmMotion.base),
                      curve: NmMotion.ease,
                      height: 3,
                      decoration: BoxDecoration(
                        color: done ? nm.accent : nm.divider,
                        borderRadius: BorderRadius.circular(NmRadius.full),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
