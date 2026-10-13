import 'package:flutter/material.dart';

import '../../brand/vyro_mark.dart';
import '../auth_controller.dart';
import '../social_sign_in.dart';
import 'taste_page.dart';
import 'welcome_page.dart';

/// Decides what to show: loading, the welcome screen, the taste picker for a
/// new account, or the app itself (for guests and signed-in people).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, required this.auth, required this.social, required this.appBuilder});

  final AuthController auth;
  final SocialSignIn social;
  final WidgetBuilder appBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        switch (auth.status) {
          case AuthStatus.starting:
            return const _Splash();
          case AuthStatus.signedOut:
            return WelcomePage(auth: auth, social: social);
          case AuthStatus.guest:
            return appBuilder(context);
          case AuthStatus.signedIn:
            final user = auth.user;
            if (user != null && !user.tasteSet && !auth.isOffline) return TastePage(auth: auth);
            return appBuilder(context);
        }
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [VyroAppIcon(size: 96), SizedBox(height: 24), CircularProgressIndicator()],
        ),
      ),
    );
  }
}
