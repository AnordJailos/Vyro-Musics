import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../validators.dart';
import 'auth_widgets.dart';
import 'password_reset_pages.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> with BusyState<SignInPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await run(() async {
      await widget.auth.signIn(_email.text.trim(), _password.text);
      if (mounted) finishAuthFlow(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Log in',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateEmail,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _password,
                validator: (v) => (v ?? '').isEmpty ? 'Enter your password.' : null,
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ForgotPasswordPage(auth: widget.auth))),
                  child: const Text('Forgot your password?'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Log in', busy: busy, onPressed: _submit)),
            ],
          ),
        ),
      ],
    );
  }
}
