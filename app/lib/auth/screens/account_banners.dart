import 'package:flutter/material.dart';

import '../auth_controller.dart';
import 'account_page.dart';
import 'verify_email_page.dart';

/// Reminders at the top of the app: confirm your email, or wait for a parent's permission.
class AccountBanners extends StatelessWidget {
  const AccountBanners({super.key, required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final user = auth.user;
        if (!auth.isSignedIn || user == null) return const SizedBox.shrink();
        final cards = <Widget>[
          if (auth.isOffline) _banner(context, Icons.cloud_off_rounded, 'Offline: showing your last saved profile.', null, null),
          if (user.parentPending)
            _banner(context, Icons.family_restroom_rounded, 'Waiting for your parent or guardian\'s permission.', 'Enter code', () => showParentCodeDialog(context, auth)),
          if (user.needsEmailCheck)
            _banner(context, Icons.mark_email_unread_outlined, 'Confirm your email to unlock everything.', 'Confirm', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VerifyEmailPage(auth: auth)))),
        ];
        return Column(children: cards);
      },
    );
  }

  Widget _banner(BuildContext context, IconData icon, String text, String? action, VoidCallback? onAction) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(text),
        trailing: action == null ? null : TextButton(onPressed: onAction, child: Text(action)),
      ),
    );
  }
}
