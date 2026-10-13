import 'package:flutter/material.dart';

import '../auth_controller.dart';
import '../auth_models.dart';
import 'auth_widgets.dart';
import 'taste_page.dart' show tasteGenres;
import 'verify_email_page.dart';

const _agreementDraft = '''DRAFT: Vyro artist agreement (the final text will replace this after legal review)

1. You keep ownership of your music.
2. You give Vyro a non-exclusive licence to stream it and to blend it with other songs in Mixing mode. You can switch blending off for any track.
3. You confirm that you own or control everything you upload: the music, lyrics, artwork and any samples.
4. You can remove your music at any time.
5. Payments to artists will follow the rules published before subscriptions start.''';

const artistTypes = {
  'solo': 'Solo artist',
  'group': 'Group or band',
  'producer_dj': 'Producer or DJ',
  'label_manager': 'Label or manager',
};

/// "Become an artist" (ART-01): same account, one extra profile.
class ArtistUpgradePage extends StatefulWidget {
  const ArtistUpgradePage({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ArtistUpgradePage> createState() => _ArtistUpgradePageState();
}

class _ArtistUpgradePageState extends State<ArtistUpgradePage> with BusyState<ArtistUpgradePage> {
  final _form = GlobalKey<FormState>();
  final _stage = TextEditingController();
  final _bio = TextEditingController();
  final _genres = <String>{};
  String? _type;
  bool _rights = false;
  bool _agreement = false;
  bool _checkError = false;

  @override
  void dispose() {
    _stage.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final okForm = _form.currentState!.validate();
    setState(() => _checkError = !(_rights && _agreement));
    if (!okForm || !_rights || !_agreement) return;
    await run(() async {
      await widget.auth.becomeArtist(ArtistRequest(
        stageName: _stage.text.trim(),
        artistType: _type!,
        agreementVersion: kArtistAgreementVersion,
        bio: _bio.text.trim(),
        genres: _genres.toList(),
      ));
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.auth,
      builder: (context, _) {
        final user = widget.auth.user;
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;

        String? blocker;
        Widget? action;
        if (user == null) {
          blocker = 'Please log in first.';
        } else if (!user.contactVerified) {
          blocker = 'Confirm your email before you become an artist, so we know how to reach you.';
          if (user.email != null) {
            action = FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VerifyEmailPage(auth: widget.auth))),
              child: const Text('Confirm my email'),
            );
          }
        } else if (user.parentPending) {
          blocker = 'Your parent or guardian needs to give permission first.';
        } else if (user.isMinor) {
          blocker = 'Artist accounts are for people aged 18 and over.';
        }

        if (blocker != null) {
          return AuthScaffold(title: 'Become an artist', children: [Text(blocker, style: text.bodyLarge), if (action != null) ...[const SizedBox(height: 16), action]]);
        }

        return AuthScaffold(
          title: 'Become an artist',
          subtitle: 'You keep your listener account. An artist profile is added so you can share your music and see how it does.',
          children: [
            Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _stage,
                    textCapitalization: TextCapitalization.words,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your artist name.' : null,
                    decoration: const InputDecoration(labelText: 'Artist name', helperText: 'Names too close to an existing artist are not allowed.'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'You are a'),
                    validator: (v) => v == null ? 'Choose one.' : null,
                    items: [for (final e in artistTypes.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value))],
                    onChanged: (v) => _type = v,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(controller: _bio, maxLength: 500, maxLines: 3, decoration: const InputDecoration(labelText: 'About you (optional)')),
                  const SizedBox(height: 8),
                  Text('Genres (up to 10)', style: text.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in tasteGenres)
                        FilterChip(
                          label: Text(g),
                          selected: _genres.contains(g),
                          onSelected: (on) => setState(() {
                            if (on && _genres.length < 10) _genres.add(g);
                            if (!on) _genres.remove(g);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 170,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
                    child: const Scrollbar(child: SingleChildScrollView(child: Text(_agreementDraft))),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _rights,
                    onChanged: (v) => setState(() => _rights = v ?? false),
                    title: const Text('I own or control everything I will upload.'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agreement,
                    onChanged: (v) => setState(() => _agreement = v ?? false),
                    title: const Text('I accept the Vyro artist agreement.'),
                  ),
                  if (_checkError) Text('Please tick both boxes to continue.', style: TextStyle(color: scheme.error)),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: SubmitButton(label: 'Create artist profile', busy: busy, onPressed: _submit)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
