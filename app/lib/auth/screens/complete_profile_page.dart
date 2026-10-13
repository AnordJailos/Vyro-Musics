import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../auth_models.dart';
import '../validators.dart';
import 'auth_widgets.dart';

/// The last step for someone who signed in with a phone number or a Google or Apple account.
class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> with BusyState<CompleteProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _parentEmail = TextEditingController();
  DateTime? _dob;
  String? _country;

  AgeBand? get _band => _dob == null ? null : ageBandOf(ageOn(_dob!, DateTime.now()));

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _parentEmail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || _band == AgeBand.tooYoung) return;
    await run(() async {
      await widget.auth.completeProfile(CompleteProfileRequest(
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
    final email = widget.auth.pending?.suggestedEmail;
    return AuthScaffold(
      title: 'Almost there',
      subtitle: email == null ? 'Tell us a little about you to finish your account.' : 'Signing up as $email. Tell us a little about you to finish.',
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
              DobField(onChanged: (d) => setState(() => _dob = d)),
              AgeNotice(band: _band),
              if (_band == AgeBand.needsParent) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _parentEmail,
                  keyboardType: TextInputType.emailAddress,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  validator: validateEmail,
                  decoration: const InputDecoration(labelText: "Parent or guardian's email"),
                ),
              ],
              const SizedBox(height: 12),
              CountryField(onChanged: (c) => _country = c),
              const SizedBox(height: 8),
              const TermsCheckbox(),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: SubmitButton(label: 'Finish', busy: busy, onPressed: _band == AgeBand.tooYoung ? null : _submit)),
            ],
          ),
        ),
      ],
    );
  }
}
