import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../validators.dart';
import 'auth_widgets.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> with BusyState<ForgotPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final email = _email.text.trim();
    await run(() async {
      await widget.auth.requestPasswordReset(email);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ResetPasswordPage(auth: widget.auth, email: email)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset your password',
      subtitle: 'Enter your email. If there is an account for it, we will send a 6-digit code.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateEmail,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Send code', busy: busy, onPressed: _send)),
            ],
          ),
        ),
      ],
    );
  }
}

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.auth, required this.email});

  final AuthController auth;
  final String email;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> with BusyState<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await run(() async {
      await widget.auth.confirmPasswordReset(widget.email, _code.text.trim(), _password.text);
      if (!mounted) return;
      finishAuthFlow(context);
      showNotice(context, 'Password changed. Log in with your new password.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Choose a new password',
      subtitle: 'Enter the code we sent to ${widget.email}, then your new password. You will be logged out everywhere else.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateCode,
                decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
              ),
              const SizedBox(height: 4),
              PasswordField(controller: _password, label: 'New password (8 or more characters)', validator: validatePassword),
              const SizedBox(height: 12),
              PasswordField(
                controller: _again,
                label: 'New password again',
                validator: (v) => v == _password.text ? null : 'The two passwords do not match.',
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Change password', busy: busy, onPressed: _save)),
            ],
          ),
        ),
      ],
    );
  }
}
