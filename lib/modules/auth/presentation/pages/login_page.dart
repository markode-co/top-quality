import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_quality/core/i18n/context_i18n.dart';
import 'package:top_quality/presentation/providers/app_providers.dart';
import 'package:top_quality/presentation/widgets/app_top_controls.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: AlignmentDirectional.topEnd,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: const [LanguageToggle(), ThemeModeToggle()],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/branding/logo.png',
                          width: 104,
                          height: 104,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: Text(
                        context.t(en: 'Top Quality', ar: 'توب كواليتي'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        context.t(
                          en: 'Sign in using the administrator credentials.',
                          ar: 'سجّل الدخول باستخدام بيانات اعتماد المسؤول.',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _identifierController,
                      keyboardType: TextInputType.text,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                      ],
                      decoration: InputDecoration(
                        labelText: context.t(
                          en: 'Username or Email',
                          ar: 'اسم المستخدم أو البريد الإلكتروني',
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      keyboardType: TextInputType.visiblePassword,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText:
                            context.t(en: 'Password', ar: 'كلمة المرور'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (authState.hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          authState.error.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_localError != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _localError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: authState.isLoading ? null : _submit,
                        child: Text(
                          authState.isLoading
                              ? context.t(
                                  en: 'Signing in...',
                                  ar: 'جارٍ تسجيل الدخول...',
                                )
                              : context.t(
                                  en: 'Sign In', ar: 'تسجيل الدخول'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() {
    final email = _identifierController.text.trim();
    final password = _passwordController.text;

    // Basic client-side validation before hitting Firebase.
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _localError = 'صيغة البريد غير صحيحة.');
      return Future.value();
    }
    if (password.isEmpty || password.length < 6) {
      setState(() => _localError = 'كلمة المرور يجب ألا تكون فارغة وأن لا تقل عن 6 أحرف.');
      return Future.value();
    }

    setState(() => _localError = null);
    return ref.read(authControllerProvider.notifier).signIn(
          identifier: email,
          password: password,
        );
  }
}
