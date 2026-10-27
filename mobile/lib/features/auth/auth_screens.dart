import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/session.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: BizColors.navy,
    body: Center(child: BrandLogo(size: 48, onDark: true)),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: BizColors.navy,
      body: SafeArea(
        child: PageBody(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 36, onDark: true)),
              const Expanded(child: Center(child: _WelcomeIllustration())),
              Text('Run your whole business from your phone.', style: t.headlineMedium?.copyWith(color: Colors.white)),
              const SizedBox(height: Space.sm),
              Text(
                'Products, stock, sales and expenses in one place — even when the network drops.',
                style: t.bodyLarge?.copyWith(color: const Color(0xFFC9CEE0)),
              ),
              const SizedBox(height: Space.xl),
              PrimaryButton(label: 'Create a free account', onPressed: () => context.push('/register')),
              const SizedBox(height: Space.sm),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: BizColors.navySoft, width: 1.5),
                ),
                onPressed: () => context.push('/login'),
                child: const Text('I already have an account'),
              ),
              const SizedBox(height: Space.md),
              Text(
                'A product of STANZ DIGITAL CONNECT',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: const Color(0xFF9097B5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lightweight vector illustration in the brand palette (no bitmap assets needed).
class _WelcomeIllustration extends StatelessWidget {
  const _WelcomeIllustration();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 260,
      height: 220,
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 10,
            child: Container(
              width: 190,
              height: 190,
              decoration: const BoxDecoration(color: BizColors.navySoft, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            left: 40,
            top: 40,
            child: _floatingCard(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Today's sales", style: TextStyle(fontSize: 11, color: BizColors.textSecondary)),
                  const SizedBox(height: 2),
                  const Text(
                    'Live from your shop',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BizColors.navy),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final h in [18.0, 30.0, 24.0, 42.0, 36.0, 54.0])
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: 16,
                          height: h,
                          decoration: BoxDecoration(
                            color: h == 54 ? BizColors.primary : BizColors.secondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 8,
            child: _floatingCard(
              width: 130,
              child: const Row(
                children: [
                  Icon(Icons.inventory_2_rounded, color: BizColors.primary, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stock in sync',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: BizColors.navy),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  static Widget _floatingCard({required double width, required Widget child}) => Container(
    width: width,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(Radii.lg),
      boxShadow: Elevations.raised,
    ),
    child: child,
  );
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          child: PageBody(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(alignment: Alignment.centerLeft, child: BrandLogo(size: 32)),
                  const SizedBox(height: Space.lg),
                  Text(title, style: t.headlineMedium),
                  const SizedBox(height: Space.xs),
                  Text(subtitle, style: t.bodyMedium?.copyWith(color: BizColors.textSecondary)),
                  const SizedBox(height: Space.lg),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email address';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email address';
  return null;
}

String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'Use at least 8 characters';
  if (RegExp(r'^\d+$').hasMatch(s) || RegExp(r'^[A-Za-z]+$').hasMatch(s)) {
    return 'Mix letters with numbers or symbols';
  }
  return null;
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({required this.controller, this.newPassword = false, this.onSubmitted});

  final TextEditingController controller;
  final bool newPassword;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autofillHints: [widget.newPassword ? AutofillHints.newPassword : AutofillHints.password],
    textInputAction: TextInputAction.done,
    onFieldSubmitted: (_) => widget.onSubmitted?.call(),
    validator: widget.newPassword ? validatePassword : (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
    decoration: InputDecoration(
      labelText: 'Password',
      helperText: widget.newPassword ? 'At least 8 characters, with letters and numbers' : null,
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).login(_email.text, _password.text);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: 'Welcome back',
    subtitle: 'Sign in to continue to your business.',
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: validateEmail,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: Space.md),
            _PasswordField(controller: _password, onSubmitted: _submit),
          ],
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
      ),
      if (_error != null) _InlineError(_error!),
      const SizedBox(height: Space.sm),
      PrimaryButton(label: 'Sign in', loading: _busy, onPressed: _submit),
      const SizedBox(height: Space.md),
      TextButton(
        onPressed: () => context.pushReplacement('/register'),
        child: const Text("New here? Create an account"),
      ),
    ],
  );
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .register(
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _fieldErrors = e.fieldErrors;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: 'Create your account',
    subtitle: "Free to start. You'll set up your business next.",
    children: [
      Form(
        key: _form,
        child: Column(
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
              decoration: InputDecoration(labelText: 'Full name', errorText: _fieldErrors['full_name']),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              validator: validateEmail,
              decoration: InputDecoration(labelText: 'Email address', errorText: _fieldErrors['email']),
            ),
            const SizedBox(height: Space.md),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Phone number (optional)', hintText: '+256 7XX XXX XXX'),
            ),
            const SizedBox(height: Space.md),
            _PasswordField(controller: _password, newPassword: true, onSubmitted: _submit),
          ],
        ),
      ),
      const SizedBox(height: Space.md),
      if (_error != null) _InlineError(_error!),
      const SizedBox(height: Space.sm),
      PrimaryButton(label: 'Create account', loading: _busy, onPressed: _submit),
      const SizedBox(height: Space.md),
      TextButton(onPressed: () => context.pushReplacement('/login'), child: const Text('Already registered? Sign in')),
    ],
  );
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _busy = false;
  String? _result;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final message = await ref.read(apiProvider).requestPasswordReset(_email.text.trim());
      if (mounted) setState(() => _result = message);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _AuthScaffold(
    title: 'Reset your password',
    subtitle: "Enter your account email and we'll send reset instructions.",
    children: [
      if (_result != null)
        AppCard(
          color: BizColors.successContainer,
          child: Row(
            children: [
              const Icon(Icons.mark_email_read_outlined, color: BizColors.success),
              const SizedBox(width: Space.sm),
              Expanded(child: Text(_result!)),
            ],
          ),
        )
      else ...[
        Form(
          key: _form,
          child: TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            validator: validateEmail,
            onFieldSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Email address'),
          ),
        ),
        const SizedBox(height: Space.md),
        if (_error != null) _InlineError(_error!),
        const SizedBox(height: Space.sm),
        PrimaryButton(label: 'Send instructions', loading: _busy, onPressed: _submit),
      ],
    ],
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(color: BizColors.errorContainer, borderRadius: Radii.control),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: BizColors.error, size: 20),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(message, style: const TextStyle(color: BizColors.error)),
          ),
        ],
      ),
    ),
  );
}
