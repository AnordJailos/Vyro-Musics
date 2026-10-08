import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../validators.dart';
import 'auth_widgets.dart';

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> with BusyState<VerifyEmailPage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_form.currentState!.validate()) return;
    await run(() async {
      await widget.auth.verifyEmail(_code.text.trim());
      if (!mounted) return;
      showNotice(context, 'Your email is confirmed.');
      Navigator.of(context).pop(true);
    });
  }

  Future<void> _resend() => run(() async {
        await widget.auth.resendEmail();
        if (mounted) showNotice(context, 'A new code is on its way.');
      });

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Confirm your email',
      subtitle: 'We sent a 6-digit code to ${widget.auth.user?.email ?? 'your email'}. It works for 10 minutes.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateCode,
                decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                onFieldSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Confirm', busy: busy, onPressed: _verify)),
              TextButton(onPressed: busy ? null : _resend, child: const Text('Send a new code')),
            ],
          ),
        ),
      ],
    );
  }
}
