import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../auth_models.dart';
import '../validators.dart';
import 'auth_widgets.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> with BusyState<SignUpPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _parentEmail = TextEditingController();
  DateTime? _dob;
  String? _country;

  AgeBand? get _band => _dob == null ? null : ageBandOf(ageOn(_dob!, DateTime.now()));

  @override
  void dispose() {
    for (final c in [_name, _username, _email, _password, _parentEmail]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _band == AgeBand.tooYoung) return;
    await run(() async {
      await widget.auth.signUp(RegisterRequest(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
        username: _username.text,
        birthDate: formatDate(_dob!),
        acceptedTermsVersion: kTermsVersion,
        country: _country,
        parentEmail: _band == AgeBand.needsParent ? _parentEmail.text.trim() : null,
        deviceName: widget.auth.deviceName,
      ));
      if (mounted) finishAuthFlow(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create account',
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateName,
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _username,
                inputFormatters: usernameFormatters,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateUsername,
                decoration: const InputDecoration(labelText: 'Username', helperText: 'Lowercase letters, numbers and _'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: validateEmail,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              PasswordField(controller: _password, label: 'Password (8 or more characters)', validator: validatePassword),
              const SizedBox(height: 12),
              DobField(onChanged: (d) => setState(() => _dob = d)),
              AgeNotice(band: _band),
              if (_band == AgeBand.needsParent) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _parentEmail,
                  keyboardType: TextInputType.emailAddress,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: (v) {
                    final problem = validateEmail(v);
                    if (problem != null) return problem;
                    if (v!.trim().toLowerCase() == _email.text.trim().toLowerCase()) return "The parent's email must be different from yours.";
                    return null;
                  },
                  decoration: const InputDecoration(labelText: "Parent or guardian's email"),
                ),
              ],
              const SizedBox(height: 12),
              CountryField(onChanged: (c) => _country = c),
              const SizedBox(height: 8),
              const TermsCheckbox(),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Create account', busy: busy, onPressed: _band == AgeBand.tooYoung ? null : _submit)),
            ],
          ),
        ),
      ],
    );
  }
}
