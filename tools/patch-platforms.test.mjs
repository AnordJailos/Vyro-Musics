import assert from 'node:assert/strict';
import { test } from 'node:test';
import { patchAndroidManifest, patchEntitlements, patchInfoPlist } from './patch-platforms.mjs';

const ANDROID = `<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="vyro_music"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data android:name="flutterEmbedding" android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
`;

const PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>vyro_music</string>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
	</array>
</dict>
</plist>
`;

const ENTITLEMENTS = `<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
`;

test('Android: adds permissions, the audio activity, service and receiver', () => {
  const { text, changes } = patchAndroidManifest(ANDROID);
  assert.ok(changes.length >= 4);
  assert.match(text, /xmlns:tools="http:\/\/schemas.android.com\/tools"/);
  for (const p of ['INTERNET', 'WAKE_LOCK', 'FOREGROUND_SERVICE', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK', 'POST_NOTIFICATIONS', 'READ_MEDIA_AUDIO']) {
    assert.ok(text.includes(`android.permission.${p}"`), p);
  }
  assert.match(text, /READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/);
  assert.match(text, /android:name="com.ryanheise.audioservice.AudioServiceActivity"/);
  assert.doesNotMatch(text, /android:name="\.MainActivity"/);
  assert.match(text, /<service android:name="com.ryanheise.audioservice.AudioService"/);
  assert.match(text, /<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"/);
  assert.ok(text.indexOf('<service') < text.indexOf('</application>'));
  assert.ok(text.includes('${applicationName}'), 'existing content is untouched');
});

test('Android: running it twice changes nothing the second time', () => {
  const once = patchAndroidManifest(ANDROID).text;
  const twice = patchAndroidManifest(once);
  assert.deepEqual(twice.changes, []);
  assert.equal(twice.text, once);
});

test('Android: warns when the main activity cannot be found', () => {
  const { changes } = patchAndroidManifest(ANDROID.replace('.MainActivity', '.OtherActivity'));
  assert.ok(changes.some((c) => c.startsWith('WARNING')));
});

test('iOS: adds the audio background mode once', () => {
  const once = patchInfoPlist(PLIST);
  assert.match(once.text, /<key>UIBackgroundModes<\/key>\s*<array>\s*<string>audio<\/string>/);
  assert.equal(once.text.trimEnd().endsWith('</plist>'), true);
  assert.deepEqual(patchInfoPlist(once.text).changes, []);
});

test('iOS: adds audio to an existing background modes list', () => {
  const withOther = PLIST.replace('</dict>', '\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>fetch</string>\n\t</array>\n</dict>');
  const { text, changes } = patchInfoPlist(withOther);
  assert.equal(changes.length, 1);
  assert.match(text, /<string>audio<\/string>/);
  assert.match(text, /<string>fetch<\/string>/);
});

test('macOS: allows network and picked files, turns the sandbox off, and is repeatable', () => {
  const once = patchEntitlements(ENTITLEMENTS);
  assert.match(once.text, /app-sandbox<\/key>\s*<false\/>/);
  assert.match(once.text, /network\.client<\/key>\s*<true\/>/);
  assert.match(once.text, /files\.user-selected\.read-only<\/key>\s*<true\/>/);
  assert.match(once.text, /keychain-access-groups<\/key>\s*<array\/>/);
  assert.match(once.text, /cs\.allow-jit<\/key>\s*<true\/>/, 'other entitlements are kept');
  assert.deepEqual(patchEntitlements(once.text).changes, []);
});
