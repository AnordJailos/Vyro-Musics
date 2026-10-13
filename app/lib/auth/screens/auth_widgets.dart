import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_errors.dart';
import '../countries.dart';
import '../validators.dart';

/// The versions people agree to. They go to the server with the sign-up, which stores them with the time.
const kTermsVersion = '2026-10';
const kArtistAgreementVersion = '2026-10';

void showError(BuildContext context, Object error) {
  final text = error is ApiException ? error.message : 'Something went wrong. Please try again.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

void showNotice(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// After a successful sign-in, close every screen that was opened on top of the first one.
void finishAuthFlow(BuildContext context) => Navigator.of(context).popUntil((r) => r.isFirst);

/// Runs a button action once at a time, shows progress, and reports errors.
mixin BusyState<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (subtitle != null) ...[Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium), const SizedBox(height: 16)],
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SubmitButton extends StatelessWidget {
  const SubmitButton({super.key, required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(label),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, this.label = 'Password', this.validator, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      validator: widget.validator,
      onFieldSubmitted: widget.onSubmitted,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show password' : 'Hide password',
          icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

final List<TextInputFormatter> usernameFormatters = [
  TextInputFormatter.withFunction((old, value) => value.copyWith(text: value.text.toLowerCase())),
  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
];

class DobField extends StatelessWidget {
  const DobField({super.key, required this.onChanged});

  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      validator: (v) => v == null ? 'Choose your date of birth.' : null,
      builder: (state) => InkWell(
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: state.value ?? DateTime(now.year - 20, now.month, now.day),
            firstDate: DateTime(now.year - 110),
            lastDate: now,
            helpText: 'Date of birth',
          );
          if (picked != null) {
            state.didChange(picked);
            onChanged(picked);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: 'Date of birth', errorText: state.errorText, suffixIcon: const Icon(Icons.calendar_month_rounded)),
          child: Text(state.value == null ? 'Choose a date' : formatDate(state.value!)),
        ),
      ),
    );
  }
}

class CountryField extends StatelessWidget {
  const CountryField({super.key, required this.onChanged});

  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final entries = countryNames.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Country (optional)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Prefer not to say')),
        for (final e in entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
      ],
      onChanged: onChanged,
    );
  }
}

/// Explains what the age rules mean for the date that was picked.
class AgeNotice extends StatelessWidget {
  const AgeNotice({super.key, required this.band});

  final AgeBand? band;

  @override
  Widget build(BuildContext context) {
    final text = switch (band) {
      AgeBand.tooYoung => 'Vyro is for people aged 13 and over.',
      AgeBand.needsParent => 'Because you are under 16, a parent or guardian has to give permission. We will email them a code.',
      AgeBand.minor => 'Explicit content is turned off for accounts under 18.',
      _ => null,
    };
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final blocked = band == AgeBand.tooYoung;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(text, style: TextStyle(color: blocked ? scheme.error : scheme.onSurfaceVariant)),
    );
  }
}

class TermsCheckbox extends StatelessWidget {
  const TermsCheckbox({super.key});

  static void _legal(BuildContext context, String title) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: const Text('This is a placeholder. The final text will be published here before launch, after legal review.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormField<bool>(
      initialValue: false,
      validator: (v) => v == true ? null : 'Please agree to continue.',
      builder: (state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: state.value ?? false,
            onChanged: (v) => state.didChange(v ?? false),
            title: const Text('I agree to the Terms of Service and the Privacy Policy'),
            subtitle: Wrap(
              children: [
                TextButton(onPressed: () => _legal(context, 'Terms of Service'), child: const Text('Read the Terms')),
                TextButton(onPressed: () => _legal(context, 'Privacy Policy'), child: const Text('Read the Privacy Policy')),
              ],
            ),
          ),
          if (state.errorText != null) Text(state.errorText!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    );
  }
}
