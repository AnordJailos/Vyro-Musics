import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../auth_models.dart';
import '../validators.dart';
import 'artist_upgrade_page.dart';
import 'auth_widgets.dart';
import 'verify_email_page.dart';

/// A parent or guardian shares the code they were emailed; the young person enters it here.
Future<void> showParentCodeDialog(BuildContext context, AuthController auth) {
  final code = TextEditingController();
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      var busy = false;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Parent or guardian's permission"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('We emailed a 6-digit code to your parent or guardian. Ask them for it and enter it here.'),
              const SizedBox(height: 12),
              TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: '6-digit code', counterText: '')),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        try {
                          await auth.resendParentConsent();
                          if (context.mounted) showNotice(context, 'A new code was emailed to your parent or guardian.');
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                child: const Text('Email them a new code'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Not now')),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (validateCode(code.text) != null) {
                        showNotice(context, 'Enter the 6-digit code.');
                        return;
                      }
                      setState(() => busy = true);
                      try {
                        await auth.confirmParentConsent(code.text.trim());
                        if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                        setState(() => busy = false);
                      }
                    },
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
    },
  );
}

/// Profile, privacy, parent permission, artist upgrade, sign out and account deletion.
class AccountPage extends StatelessWidget {
  const AccountPage({super.key, required this.auth});

  final AuthController auth;

  Future<void> _change(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _editProfile(BuildContext context, UserProfile user) {
    final name = TextEditingController(text: user.displayName);
    final username = TextEditingController(text: user.username);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Your name')),
            const SizedBox(height: 12),
            TextField(controller: username, inputFormatters: usernameFormatters, decoration: const InputDecoration(labelText: 'Username')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (validateName(name.text) != null || validateUsername(username.text) != null) {
                showNotice(context, 'Check your name and username.');
                return;
              }
              try {
                await auth.updateProfile(
                  displayName: name.text.trim() == user.displayName ? null : name.text.trim(),
                  username: username.text == user.username ? null : username.text,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Your music on this device stays here.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Log out')),
        ],
      ),
    );
    if (ok != true) return;
    await auth.signOut();
    if (context.mounted) finishAuthFlow(context);
  }

  Future<void> _delete(BuildContext context, UserProfile user) async {
    final typed = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This permanently deletes your account and your listening history. Your plays stay in artists\' totals, but without your name.'),
            const SizedBox(height: 12),
            TextField(controller: typed, decoration: const InputDecoration(labelText: 'Type DELETE to confirm')),
            if (user.hasPassword) ...[
              const SizedBox(height: 8),
              TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Your password')),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error, foregroundColor: Theme.of(d).colorScheme.onError),
            onPressed: () => Navigator.of(d).pop(typed.text.trim() == 'DELETE'),
            child: const Text('Delete my account'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _change(context, () async {
      await auth.deleteAccount(password: user.hasPassword ? password.text : null);
      if (context.mounted) finishAuthFlow(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final user = auth.user;
        if (user == null) return const Scaffold(body: Center(child: Text('Please log in.')));
        final text = Theme.of(context).textTheme;
        final s = user.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                leading: CircleAvatar(child: Text(user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase())),
                title: Text(user.displayName),
                subtitle: Text('@${user.username}${user.email != null ? '\n${user.email}' : ''}${user.phone != null ? '\n${user.phone}' : ''}'),
                isThreeLine: user.email != null || user.phone != null,
                trailing: IconButton(tooltip: 'Edit profile', icon: const Icon(Icons.edit_outlined), onPressed: () => _editProfile(context, user)),
              ),
              if (user.needsEmailCheck)
                ListTile(
                  leading: const Icon(Icons.mark_email_unread_outlined),
                  title: const Text('Confirm your email'),
                  subtitle: const Text('Needed to become an artist and to recover your account.'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VerifyEmailPage(auth: auth))),
                ),
              if (user.parentPending)
                ListTile(
                  leading: const Icon(Icons.family_restroom_rounded),
                  title: const Text("Waiting for your parent or guardian's permission"),
                  subtitle: const Text('Tap to enter the code they received.'),
                  onTap: () => showParentCodeDialog(context, auth),
                ),
              const Divider(),
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Privacy', style: text.titleMedium)),
              SwitchListTile(
                title: const Text('Private session'),
                subtitle: const Text('Your listening is not added to your history or used for recommendations. It still counts for the artist.'),
                value: s.privateSession,
                onChanged: (v) => _change(context, () => auth.updateSettings(privateSession: v)),
              ),
              SwitchListTile(
                title: const Text('Personalized recommendations'),
                subtitle: const Text('Use my listening to suggest music. Turn off and plays are no longer linked to you.'),
                value: s.personalization,
                onChanged: (v) => _change(context, () => auth.updateSettings(personalization: v)),
              ),
              SwitchListTile(
                title: const Text('Show my listening on my profile'),
                value: s.shareListening,
                onChanged: (v) => _change(context, () => auth.updateSettings(shareListening: v)),
              ),
              SwitchListTile(
                title: const Text('Hide my activity from friends'),
                value: s.hideActivity,
                onChanged: (v) => _change(context, () => auth.updateSettings(hideActivity: v)),
              ),
              SwitchListTile(
                title: const Text('Allow explicit content'),
                subtitle: Text(user.isMinor ? 'Not available for accounts under 18.' : 'Songs marked explicit can play.'),
                value: s.explicitAllowed,
                onChanged: user.isMinor ? null : (v) => _change(context, () => auth.updateSettings(explicitAllowed: v)),
              ),
              const Divider(),
              if (!user.isArtist)
                ListTile(
                  leading: const Icon(Icons.mic_external_on_rounded),
                  title: const Text('Become an artist'),
                  subtitle: const Text('Share your music and see who listens.'),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ArtistUpgradePage(auth: auth))),
                )
              else
                ListTile(leading: const Icon(Icons.mic_external_on_rounded), title: Text('Artist: ${user.artist!.stageName}'), subtitle: Text(user.artist!.verified ? 'Verified' : 'Not verified yet')),
              ListTile(leading: const Icon(Icons.logout_rounded), title: const Text('Log out'), onTap: () => _signOut(context)),
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                title: Text('Delete my account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () => _delete(context, user),
              ),
            ],
          ),
        );
      },
    );
  }
}
