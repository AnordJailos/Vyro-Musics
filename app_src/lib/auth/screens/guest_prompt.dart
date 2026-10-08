import 'package:flutter/material.dart';

import '../auth_controller.dart';

/// What a guest sees where an account is needed (profile, becoming an artist).
class GuestPrompt extends StatelessWidget {
  const GuestPrompt({super.key, required this.auth, this.reason = 'Create an account to see your listening, follow artists and keep your music in sync.'});

  final AuthController auth;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_outline_rounded, size: 56),
              const SizedBox(height: 12),
              Text('You are browsing as a guest', style: text.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(reason, style: text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: auth.leaveGuest, child: const Text('Create account or log in')),
            ],
          ),
        ),
      ),
    );
  }
}
