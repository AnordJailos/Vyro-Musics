import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../validators.dart';
import 'auth_widgets.dart';
import 'complete_profile_page.dart';

class PhonePage extends StatefulWidget {
  const PhonePage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends State<PhonePage> with BusyState<PhonePage> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    final number = normalizePhone(_phone.text);
    await run(() async {
      await widget.auth.requestPhoneCode(number);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CodePage(auth: widget.auth, phone: number)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Use your phone number',
      subtitle: 'We will text you a 6-digit code. If you are new, you will set up your profile next.',
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validatePhone,
                decoration: const InputDecoration(labelText: 'Phone number', helperText: 'Start with + and the country code'),
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

class CodePage extends StatefulWidget {
  const CodePage({super.key, required this.auth, required this.phone});

  final AuthController auth;
  final String phone;

  @override
  State<CodePage> createState() => _CodePageState();
}

class _CodePageState extends State<CodePage> with BusyState<CodePage> {
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
      final outcome = await widget.auth.verifyPhoneCode(widget.phone, _code.text.trim());
      if (!mounted) return;
      if (outcome.pending != null) {
        Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => CompleteProfilePage(auth: widget.auth)));
      } else {
        finishAuthFlow(context);
      }
    });
  }

  Future<void> _resend() => run(() async {
        await widget.auth.requestPhoneCode(widget.phone);
        if (mounted) showNotice(context, 'A new code is on its way.');
      });

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Enter your code',
      subtitle: 'We sent a code to ${widget.phone}. It works for 10 minutes.',
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
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Continue', busy: busy, onPressed: _verify)),
              TextButton(onPressed: busy ? null : _resend, child: const Text('Send a new code')),
            ],
          ),
        ),
      ],
    );
  }
}
