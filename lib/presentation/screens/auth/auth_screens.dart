import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/error/app_error.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../../domain/repositories/auth_gateway.dart';
import '../../components/brand/brand_mark.dart';
import '../../components/system/buttons.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/overlays.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_providers.dart';

/// Validaciones de F-01, compartidas por alta e inicio de sesión.
abstract final class AuthValidation {
  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]"
    r'(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  static String? email(String raw) {
    final value = normalizeEmail(raw);
    if (value.isEmpty) return 'Ingresá tu correo.';
    if (value.length > 254) return 'El correo es demasiado largo.';
    if (!_email.hasMatch(value)) return 'Revisá el correo: no parece válido.';
    return null;
  }

  static String? password(String value) {
    if (value.length < 8 || value.length > 72) {
      return 'La contraseña necesita al menos 8 caracteres, una letra y un '
          'número.';
    }
    final hasLetter = RegExp('[A-Za-zÁÉÍÓÚáéíóúÑñ]').hasMatch(value);
    final hasDigit = RegExp(r'\d').hasMatch(value);
    if (!hasLetter || !hasDigit) {
      return 'La contraseña necesita al menos 8 caracteres, una letra y un '
          'número.';
    }
    return null;
  }

  /// 0–3. Indicador de fuerza del alta.
  static int strength(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score.clamp(0, 3);
  }
}

/// S-03 · Iniciar sesión.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({this.initialEmail, super.key});

  final String? initialEmail;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final TextEditingController _email = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final TextEditingController _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      AuthValidation.email(_email.text) == null &&
      AuthValidation.password(_password.text) == null;

  Future<void> _submit() async {
    setState(() {
      _emailError = AuthValidation.email(_email.text);
      _passwordError = AuthValidation.password(_password.text);
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _submitting = true);
    final repo = ref.read(repositoryProvider);

    final email = AuthValidation.normalizeEmail(_email.text);
    final AuthAccount cuenta;
    try {
      cuenta = await ref
          .read(authGatewayProvider)
          .signIn(email: email, password: _password.text);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = error.message;
      });
      return;
    }

    // El perfil local se marca con el correo recién cuando el servidor aceptó
    // las credenciales: antes, cualquier contraseña equivocada dejaba la app
    // como si hubiera sesión.
    //
    // Y va el id de la cuenta, no solo el correo: es lo que deja arrancar
    // limpio cuando el que entra no es el mismo de la vez pasada.
    await repo.signIn(email, accountId: cuenta.id);

    // Traer el respaldo **antes** de habilitar la subida. En un teléfono
    // recién instalado esto devuelve lo que había; si no se hiciera acá, el
    // documento vacío del alta pisaría el respaldo bueno a los pocos segundos.
    // Las tablas primero y siempre: son la fuente de verdad de la cuenta, y lo
    // que traen se reconcilia con lo local en vez de reemplazarlo.
    final desdeTablas = await ref
        .read(relationalSyncProvider)
        ?.openAfterPull(apply: repo.importDocument);

    final restored = await ref
        .read(cloudBackupProvider)
        ?.openAfterRestore(
          localIsEmpty: (desdeTablas ?? false) ? false : !repo.hasUserData,
          apply: (json) => repo.importJson(json),
        );

    if (!mounted) return;
    setState(() => _submitting = false);
    if (restored ?? false) {
      NmSnackbar.show(context, 'Recuperamos tus datos del respaldo');
    }
    context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s10),
          const BrandMark(size: 40),
          const SizedBox(height: NmSpace.s6),
          Text(
            'Entrar a tu cuenta',
            style: NmTextStyles.from(NmType.h1, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s8),
          if (_formError != null) ...<Widget>[
            _FormErrorSummary(message: _formError!),
            const SizedBox(height: NmSpace.s4),
          ],
          NmTextField(
            label: 'Correo',
            controller: _email,
            error: _emailError,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.email],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NmSpace.s4),
          NmPasswordField(
            label: 'Contraseña',
            controller: _password,
            error: _passwordError,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _canSubmit ? _submit() : null,
          ),
          const SizedBox(height: NmSpace.s3),
          Align(
            alignment: Alignment.centerLeft,
            child: NmButton.ghost(
              label: 'Olvidé mi contraseña',
              onPressed: () => context.push(Routes.forgotPassword),
            ),
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Entrar',
            block: true,
            loading: _submitting,
            onPressed: _canSubmit ? _submit : null,
          ),
          const SizedBox(height: NmSpace.s4),
          Center(
            child: NmButton.ghost(
              label: 'Crear cuenta',
              onPressed: () => context.pushReplacement(Routes.signUp),
            ),
          ),
        ],
      ),
    );
  }
}

/// S-04 · Crear cuenta.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _terms = false;
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _terms &&
      _name.text.trim().length >= 2 &&
      AuthValidation.email(_email.text) == null &&
      AuthValidation.password(_password.text) == null;

  Future<void> _submit() async {
    setState(() {
      _emailError = AuthValidation.email(_email.text);
      _passwordError = AuthValidation.password(_password.text);
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;

    final repo = ref.read(repositoryProvider);

    setState(() => _submitting = true);
    final email = AuthValidation.normalizeEmail(_email.text);
    final name = _name.text.trim();

    final AuthAccount? account;
    try {
      account = await ref
          .read(authGatewayProvider)
          .signUp(email: email, password: _password.text, displayName: name);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = error.message;
      });
      return;
    }

    await repo.startDemoSession(seeded: false);
    await repo.signIn(email, accountId: account?.id);
    await repo.updateProfile(
      repo.profile.copyWith(displayName: name),
    );

    // Abrir la puerta del respaldo también acá. Sin esto, quien creaba la
    // cuenta y usaba la app toda la tarde no respaldaba **nada**: `markDirty`
    // salía por la primera línea porque `canUpload` seguía en false hasta el
    // próximo arranque. Una cuenta recién creada no tiene respaldo que traer,
    // así que esto solo habilita la subida.
    await ref
        .read(relationalSyncProvider)
        ?.openAfterPull(apply: repo.importDocument);
    await ref
        .read(cloudBackupProvider)
        ?.openAfterRestore(
          localIsEmpty: !repo.hasUserData,
          apply: (json) => repo.importJson(json),
        );

    if (!mounted) return;
    setState(() => _submitting = false);

    // Si el alta ya devolvió sesión, el proyecto no pide confirmar el correo:
    // se puede seguir de largo a completar los datos.
    if (account != null) {
      context.go(Routes.onboarding);
      return;
    }
    context.go('${Routes.checkEmail}?email=${Uri.encodeComponent(email)}');
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    final strength = AuthValidation.strength(_password.text);

    return NmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s10),
          const BrandMark(size: 40),
          const SizedBox(height: NmSpace.s6),
          Text(
            'Crear tu cuenta',
            style: NmTextStyles.from(NmType.h1, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s8),
          if (_formError != null) ...<Widget>[
            _FormErrorSummary(message: _formError!),
            const SizedBox(height: NmSpace.s4),
          ],
          NmTextField(
            label: 'Tu nombre',
            controller: _name,
            hint: 'Como querés que te vean',
            helper: 'Es lo único que ven tus pals. Podés cambiarlo después.',
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.givenName],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NmSpace.s4),
          NmTextField(
            label: 'Correo',
            controller: _email,
            error: _emailError,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.email],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NmSpace.s4),
          NmPasswordField(
            label: 'Contraseña',
            controller: _password,
            error: _passwordError,
            helper: 'Al menos 8 caracteres, una letra y un número.',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NmSpace.s3),
          Row(
            children: <Widget>[
              for (var i = 0; i < 3; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 0 : NmSpace.s1),
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: i < strength ? nm.accent : nm.divider,
                        borderRadius: BorderRadius.circular(NmRadius.full),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NmSpace.s4),
          NmCheckboxRow(
            label: 'Acepto los términos y la política de privacidad.',
            value: _terms,
            onChanged: (v) => setState(() => _terms = v),
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Crear cuenta',
            block: true,
            loading: _submitting,
            onPressed: _canSubmit ? _submit : null,
          ),
          const SizedBox(height: NmSpace.s4),
          Center(
            child: NmButton.ghost(
              label: 'Ya tengo cuenta',
              onPressed: () => context.pushReplacement(Routes.signIn),
            ),
          ),
        ],
      ),
    );
  }
}

/// Recuperar contraseña.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final TextEditingController _email = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return NmScreen(
      title: 'Recuperar contraseña',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s6),
          Text(
            'Te enviamos un enlace para elegir una contraseña nueva.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s6),
          NmTextField(
            label: 'Correo',
            controller: _email,
            error: _error,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NmSpace.s6),
          NmButton(
            label: 'Enviar enlace',
            block: true,
            loading: _submitting,
            onPressed: () async {
              final error = AuthValidation.email(_email.text);
              setState(() => _error = error);
              if (error != null) return;
              setState(() => _submitting = true);

              final email = AuthValidation.normalizeEmail(_email.text);
              try {
                await ref.read(authGatewayProvider).sendPasswordReset(email);
              } on AppError catch (failure) {
                if (!context.mounted) return;
                setState(() {
                  _submitting = false;
                  _error = failure.message;
                });
                return;
              }

              if (!context.mounted) return;
              setState(() => _submitting = false);
              unawaited(
                context.push(
                  '${Routes.checkEmail}?intent=reset&email='
                  '${Uri.encodeComponent(email)}',
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Revisá tu correo.
class CheckEmailScreen extends ConsumerWidget {
  const CheckEmailScreen({this.email, this.intent = 'signup', super.key});

  final String? email;
  final String intent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    final isReset = intent == 'reset';

    return NmScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s12),
          Icon(
            PhosphorIcons.checkCircle(),
            size: NmIconSize.xl,
            color: nm.success,
          ),
          const SizedBox(height: NmSpace.s6),
          Text(
            'Revisá tu correo',
            style: NmTextStyles.from(NmType.h1, color: nm.text),
          ),
          const SizedBox(height: NmSpace.s3),
          Text(
            isReset
                ? 'Si ${email ?? 'ese correo'} tiene una cuenta, le mandamos un '
                      'enlace para elegir una contraseña nueva.'
                : 'Te mandamos un enlace de confirmación a '
                      '${email ?? 'tu correo'}. Abrilo desde este teléfono para '
                      'terminar de crear la cuenta.',
            style: NmTextStyles.from(NmType.bodySm, color: nm.textMuted),
          ),
          const SizedBox(height: NmSpace.s8),
          NmButton(
            label: isReset ? 'Volver a entrar' : 'Ya confirmé, entrar',
            block: true,
            // Confirmar el correo no abre sesión: hay que entrar igual.
            onPressed: () {
              final address = email;
              context.go(
                address == null
                    ? Routes.signIn
                    : '${Routes.signIn}?email='
                          '${Uri.encodeComponent(address)}',
              );
            },
          ),
        ],
      ),
    );
  }
}

/// El error general va arriba del formulario, no en un toast (S-03).
class _FormErrorSummary extends StatelessWidget {
  const _FormErrorSummary({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(NmSpace.s4),
        decoration: BoxDecoration(
          color: nm.danger.withValues(alpha: nm.isDark ? 0.16 : 0.10),
          borderRadius: NmRadius.brMd,
          border: Border.all(color: nm.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              PhosphorIcons.warningCircle(),
              size: NmIconSize.md,
              color: nm.danger,
            ),
            const SizedBox(width: NmSpace.s3),
            Expanded(
              child: Text(
                message,
                style: NmTextStyles.from(NmType.bodySm, color: nm.danger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
