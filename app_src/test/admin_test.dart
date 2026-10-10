import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vyro_music/admin/admin_api.dart';
import 'package:vyro_music/admin/admin_models.dart';
import 'package:vyro_music/admin/admin_page.dart';
import 'package:vyro_music/audio/playback_controller.dart';
import 'package:vyro_music/audio/track.dart';
import 'package:vyro_music/auth/screens/account_page.dart';
import 'package:vyro_music/main.dart';

import 'auth_fakes.dart';
import 'fakes.dart';

ReviewItem _item(String id, String title, String artist, {ReviewChecks checks = const ReviewChecks(fingerprinted: true), String status = 'in_review'}) =>
    ReviewItem(id: id, title: title, status: status, artistId: 'a-$id', artistName: artist, durationMs: 200000, codec: 'mp3', bitrateKbps: 192, loudnessLufs: -14.1, checks: checks);

class FakeAdminApi implements AdminApi {
  FakeAdminApi() {
    queue = [
      _item('id1', 'Song A', 'Act One', checks: const ReviewChecks(fingerprinted: true, duplicates: [DuplicateMatch(title: 'Original Song', artistName: 'Act Two', similarity: 0.97, sameArtist: false, status: 'published')])),
      _item('id2', 'Song B', 'Act Three', checks: const ReviewChecks()),
    ];
    held = [
      _item('id3', 'Held Song', 'Act Four', status: 'held', checks: const ReviewChecks(fingerprinted: true, externalStatus: 'matches', externalMatches: [ExternalMatch(title: 'A Famous Song', artists: ['Famous Artist'], score: 0.97)])),
    ];
    notices = [
      const TakedownNotice(id: 'n1', status: 'counter_filed', trackTitle: 'Disputed', artistName: 'Act One', strikes: 1, claimantName: 'Rights Holder', claimantEmail: 'rights@example.com', claimantCompany: 'Big Label', statement: 'This is our recording.', counterStatement: 'I made it myself.'),
    ];
    people = [
      const AdminArtist(id: 'p1', stageName: 'Act One', username: 'act_one', trackCount: 3),
      const AdminArtist(id: 'p2', stageName: 'Banned Act', username: 'banned', suspended: true, suspensionReason: 'Rule breaking', strikes: 3),
    ];
  }

  late List<ReviewItem> queue;
  late List<ReviewItem> held;
  late List<TakedownNotice> notices;
  late List<AdminArtist> people;
  final calls = <String>[];

  @override
  Future<List<ReviewItem>> reviewQueue({String status = 'in_review'}) async => List.of(status == 'held' ? held : queue);

  @override
  Future<void> approve(String trackId, {String? note}) async {
    calls.add('approve:$trackId');
    queue.removeWhere((i) => i.id == trackId);
  }

  @override
  Future<void> reject(String trackId, {required String reason, String? note}) async {
    calls.add('reject:$trackId:$reason:${note ?? ''}');
    queue.removeWhere((i) => i.id == trackId);
  }

  @override
  Future<int> bulk({required String action, required List<String> ids, String? reason}) async {
    calls.add('bulk:$action:${ids.join(',')}:${reason ?? ''}');
    queue.removeWhere((i) => ids.contains(i.id));
    return ids.length;
  }

  @override
  Future<Uri> previewUri(String trackId) async => Uri.parse('http://localhost:3000/v1/stream/$trackId.token');

  @override
  Future<List<TakedownNotice>> takedowns() async => List.of(notices);

  @override
  Future<void> resolveTakedown(String noticeId, {required String decision, String? note}) async {
    calls.add('resolve:$noticeId:$decision');
    notices.removeWhere((n) => n.id == noticeId);
  }

  @override
  Future<List<AdminArtist>> artists(String query) async => [for (final a in people) if (a.stageName.toLowerCase().contains(query.toLowerCase())) a];

  @override
  Future<void> verifyArtist(String artistId, bool verified) async => calls.add('verify:$artistId:$verified');

  @override
  Future<void> suspend(String userId, String reason) async => calls.add('suspend:$userId:$reason');

  @override
  Future<void> unsuspend(String userId) async => calls.add('unsuspend:$userId');
}

PlaybackController _playback() => PlaybackController(deckA: FakeDeck(), deckB: FakeDeck());
Widget _page(FakeAdminApi api, [PlaybackController? playback]) => MaterialApp(home: AdminPage(admin: api, playback: playback ?? _playback()));

Future<void> _tall(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  test('automatic check results are read, and a song with none recorded still loads', () {
    final item = ReviewItem.fromJson({
      'id': 'i',
      'title': 'T',
      'status': 'held',
      'durationMs': 1000,
      'artist': {'id': 'a', 'stageName': 'A', 'verified': true, 'strikes': 2, 'publishedCount': 5},
      'checks': {
        'fingerprinted': true,
        'duplicates': [
          {'title': 'Other', 'artistName': 'B', 'similarity': 0.95, 'sameArtist': false, 'status': 'published'},
        ],
        'external': {
          'status': 'matches',
          'matches': [
            {'title': 'Famous', 'artists': ['X'], 'score': 0.9},
          ],
        },
      },
    });
    expect(item.checks.duplicates.single.similarity, closeTo(0.95, 1e-9));
    expect(item.checks.externalStatus, 'matches');
    expect(item.checks.externalMatches.single.artists, ['X']);
    expect([item.artistVerified, item.strikes, item.publishedCount], [true, 2, 5]);

    final bare = ReviewItem.fromJson({'id': 'i', 'title': 'T', 'status': 'in_review', 'artist': {'id': 'a', 'stageName': 'A'}, 'checks': <String, Object?>{}});
    expect(bare.checks.fingerprinted, isFalse);
    expect(bare.checks.duplicates, isEmpty);
  });

  testWidgets('the review queue shows what the checks found for each song', (tester) async {
    await _tall(tester);
    await tester.pumpWidget(_page(FakeAdminApi()));
    await tester.pumpAndSettle();
    expect(find.text('Song A'), findsOneWidget);
    expect(find.textContaining('Sounds like "Original Song" by Act Two (97%)'), findsOneWidget);
    expect(find.text('Not fingerprinted'), findsOneWidget); // Song B was never checked
    expect(find.textContaining('3:20 · mp3 192 kbps'), findsWidgets);

    await tester.tap(find.text('On hold'));
    await tester.pumpAndSettle();
    expect(find.text('Held Song'), findsOneWidget);
    expect(find.textContaining('Matches released music: "A Famous Song" by Famous Artist'), findsOneWidget);
    expect(find.text('Song A'), findsNothing);
  });

  testWidgets('approves a song, and it leaves the queue', (tester) async {
    await _tall(tester);
    final api = FakeAdminApi();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve Song A'));
    await tester.pumpAndSettle();
    expect(api.calls, ['approve:id1']);
    expect(find.text('Song A'), findsNothing);
    expect(find.text('Song B'), findsOneWidget);
  });

  testWidgets('rejecting needs a reason, which is sent with the note', (tester) async {
    await _tall(tester);
    final api = FakeAdminApi();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject Song B'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Reject')).onPressed, isNull);

    await tester.tap(find.text('Audio quality too low'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, 'Please remaster it.');
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();
    expect(api.calls, ['reject:id2:low_quality:Please remaster it.']);
    expect(find.text('Song B'), findsNothing);
  });

  testWidgets('decides several songs at once', (tester) async {
    await _tall(tester);
    final api = FakeAdminApi();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Approve selected'));
    await tester.pumpAndSettle();
    expect(api.calls, ['bulk:approve:id1,id2:']);
    expect(find.text('Nothing is waiting here.'), findsOneWidget);
  });

  testWidgets('a reviewer can listen to a song before deciding', (tester) async {
    await _tall(tester);
    final playback = _playback();
    await tester.pumpWidget(_page(FakeAdminApi(), playback));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Listen to Song A'));
    await tester.pump();
    await tester.pump();
    expect(playback.current!.id, 'preview:id1');
    expect(playback.current!.mixable, isFalse);
    expect(await playback.current!.resolveUri!(), Uri.parse('http://localhost:3000/v1/stream/id1.token'));
    expect(playback.current!.source, TrackSource.vyro);
  });

  testWidgets('decides a copyright notice, asking first because an upheld one is a strike', (tester) async {
    await _tall(tester);
    final api = FakeAdminApi();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copyright'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"Disputed" by Act One'), findsOneWidget);
    expect(find.textContaining('Rights Holder (Big Label)'), findsOneWidget);
    expect(find.text('I made it myself.'), findsOneWidget);

    await tester.tap(find.text('Uphold notice'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gets a strike (2 of 3)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);

    await tester.tap(find.text('Uphold notice'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Uphold'));
    await tester.pumpAndSettle();
    expect(api.calls, ['resolve:n1:uphold']);
    expect(find.text('No copyright notices are waiting.'), findsOneWidget);
  });

  testWidgets('verifies, suspends and restores artists', (tester) async {
    await _tall(tester);
    final api = FakeAdminApi();
    await tester.pumpWidget(_page(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Artists'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Suspended: Rule breaking'), findsOneWidget);

    await tester.tap(find.byTooltip('Options for Act One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark as verified'));
    await tester.pumpAndSettle();
    expect(api.calls, ['verify:p1:true']);

    await tester.tap(find.byTooltip('Options for Act One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suspend'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Spam uploads');
    await tester.tap(find.widgetWithText(FilledButton, 'Suspend'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'suspend:p1:Spam uploads');

    await tester.tap(find.byTooltip('Options for Banned Act'));
    await tester.pumpAndSettle();
    expect(find.text('Suspend'), findsNothing);
    await tester.tap(find.text('Restore account'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'unsuspend:p2');

    await tester.enterText(find.byType(TextField), 'banned');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Act One'), findsNothing);
    expect(find.text('Banned Act'), findsOneWidget);
  });

  group('who sees the admin console', () {
    testWidgets('staff get an entry on the Account screen, and it opens the console', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await signedIn(FakeAuthApi(user: testUser(role: 'moderator')));
      await tester.pumpWidget(MaterialApp(home: AccountPage(auth: auth, admin: FakeAdminApi(), playback: _playback())));
      expect(find.text('Admin console'), findsOneWidget);
      await tester.tap(find.text('Admin console'));
      await tester.pumpAndSettle();
      expect(find.text('Copyright'), findsOneWidget);
      expect(find.text('Song A'), findsOneWidget);
    });

    testWidgets('everyone else does not', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await signedIn(FakeAuthApi());
      await tester.pumpWidget(MaterialApp(home: AccountPage(auth: auth, admin: FakeAdminApi(), playback: _playback())));
      expect(find.text('Admin console'), findsNothing);
    });

    testWidgets('inside the app, a moderator reaches it from the Account button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final auth = await signedIn(FakeAuthApi(user: testUser(role: 'admin')));
      await tester.pumpWidget(VyroApp(playback: _playback(), auth: auth, admin: FakeAdminApi()));
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Admin console'), findsOneWidget);
    });
  });
}
