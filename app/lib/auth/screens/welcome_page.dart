import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../brand/vyro_mark.dart';
import '../../theme/vyro_theme.dart';
import '../auth_controller.dart';
import '../social_sign_in.dart';
import 'auth_widgets.dart';
import 'complete_profile_page.dart';
import 'phone_pages.dart';
import 'sign_in_page.dart';
import 'sign_up_page.dart';

/// The first screen for someone who is signed out.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.auth, required this.social});

  final AuthController auth;
  final SocialSignIn social;

  void _push(BuildContext context, Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const SizedBox(height: 16),
                const Center(child: VyroAppIcon(size: 104)),
                const SizedBox(height: 16),
                const Center(child: VyroWordmark(fontSize: 44)),
                const SizedBox(height: 8),
                Center(child: Text('PRESS PLAY. KEEP THE FLOW.', style: text.labelMedium?.copyWith(letterSpacing: 3, color: VyroColors.mist))),
                const SizedBox(height: 32),
                FilledButton(onPressed: () => _push(context, SignUpPage(auth: auth)), child: const Text('Create account')),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: () => _push(context, SignInPage(auth: auth)), child: const Text('Log in')),
                const SizedBox(height: 4),
                TextButton(onPressed: () => _push(context, PhonePage(auth: auth)), child: const Text('Use my phone number')),
                const SizedBox(height: 8),
                SocialButtons(auth: auth, social: social),
                const SizedBox(height: 8),
                TextButton(onPressed: auth.continueAsGuest, child: const Text('Continue as guest')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SocialButtons extends StatelessWidget {
  const SocialButtons({super.key, required this.auth, required this.social});

  final AuthController auth;
  final SocialSignIn social;

  Future<void> _go(BuildContext context, SocialProvider provider, String label) async {
    if (!social.isAvailable(provider)) {
      showNotice(context, '$label sign-in is not set up in this build yet.');
      return;
    }
    try {
      final token = await social.idToken(provider);
      if (token == null) return; // the person cancelled
      final outcome = await auth.signInSocial(provider, token);
      if (!context.mounted) return;
      if (outcome.pending != null) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CompleteProfilePage(auth: auth)));
      } else {
        finishAuthFlow(context);
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apple = defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;
    return Column(
      children: [
        OutlinedButton.icon(
          onPressed: () => _go(context, SocialProvider.google, 'Google'),
          icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
          label: const Text('Continue with Google'),
        ),
        if (apple) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _go(context, SocialProvider.apple, 'Apple'),
            icon: const Icon(Icons.apple_rounded),
            label: const Text('Continue with Apple'),
          ),
        ],
      ],
    );
  }
}
