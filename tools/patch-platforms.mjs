#!/usr/bin/env node
// One-time platform settings for the Vyro app, applied to a freshly generated Flutter app folder.
// Safe to run more than once: it only adds what is missing.
//
//   node tools/patch-platforms.mjs app
import { readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const ANDROID_PERMISSIONS = [
  ['android.permission.INTERNET', ''],
  ['android.permission.WAKE_LOCK', ''],
  ['android.permission.FOREGROUND_SERVICE', ''],
  ['android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK', ''],
  ['android.permission.POST_NOTIFICATIONS', ''],
  ['android.permission.READ_MEDIA_AUDIO', ''],
  ['android.permission.READ_EXTERNAL_STORAGE', ' android:maxSdkVersion="32"'],
];

const SERVICE_AND_RECEIVER = `
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
`;

export function patchAndroidManifest(xml) {
  const changes = [];
  let out = xml;

  if (!/xmlns:tools=/.test(out)) {
    out = out.replace(/<manifest\b([^>]*)>/, (_m, attrs) => `<manifest${attrs} xmlns:tools="http://schemas.android.com/tools">`);
    changes.push('added the tools namespace');
  }

  const missing = ANDROID_PERMISSIONS.filter(([name]) => !out.includes(`"${name}"`));
  if (missing.length > 0) {
    const lines = missing.map(([name, extra]) => `    <uses-permission android:name="${name}"${extra}/>`).join('\n');
    out = out.replace(/(<manifest\b[^>]*>)/, (m) => `${m}\n${lines}`);
    changes.push(`added permissions: ${missing.map(([n]) => n.split('.').pop()).join(', ')}`);
  }

  if (!out.includes('com.ryanheise.audioservice.AudioServiceActivity')) {
    if (out.includes('android:name=".MainActivity"')) {
      out = out.replace('android:name=".MainActivity"', 'android:name="com.ryanheise.audioservice.AudioServiceActivity"');
      changes.push('switched the main activity to AudioServiceActivity');
    } else {
      changes.push('WARNING: could not find ".MainActivity"; set the activity to com.ryanheise.audioservice.AudioServiceActivity by hand');
    }
  }

  if (!out.includes('com.ryanheise.audioservice.AudioService"')) {
    out = out.replace('</application>', () => `${SERVICE_AND_RECEIVER}    </application>`);
    changes.push('added the audio service and media button receiver');
  }
  return { text: out, changes };
}

export function patchInfoPlist(plist) {
  const changes = [];
  let out = plist;
  const keyRe = /<key>UIBackgroundModes<\/key>\s*<array>/;
  if (keyRe.test(out)) {
    const block = out.match(/<key>UIBackgroundModes<\/key>\s*<array>[\s\S]*?<\/array>/)[0];
    if (!block.includes('<string>audio</string>')) {
      out = out.replace(keyRe, (m) => `${m}\n\t\t<string>audio</string>`);
      changes.push('added the audio background mode');
    }
  } else {
    const at = out.lastIndexOf('</dict>');
    out = `${out.slice(0, at)}\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n${out.slice(at)}`;
    changes.push('added the audio background mode');
  }
  return { text: out, changes };
}

function setBool(plist, key, value, changes) {
  const re = new RegExp(`(<key>${key.replace(/\./g, '\\.')}</key>\\s*)<(true|false)/>`);
  const found = plist.match(re);
  if (found) {
    if (found[2] === String(value)) return plist;
    changes.push(`${key} set to ${value}`);
    return plist.replace(re, (_m, head) => `${head}<${value}/>`);
  }
  const at = plist.lastIndexOf('</dict>');
  changes.push(`${key} set to ${value}`);
  return `${plist.slice(0, at)}\t<key>${key}</key>\n\t<${value}/>\n${plist.slice(at)}`;
}

/**
 * macOS: allow network access, user-selected files and the Keychain, and turn the App Sandbox off so the
 * app can read the real Music folder. Fine for development and for apps shipped outside the
 * Mac App Store; a store release needs the sandbox back on, with saved folder permissions.
 */
export function patchEntitlements(plist) {
  const changes = [];
  let out = plist;
  out = setBool(out, 'com.apple.security.network.client', true, changes);
  out = setBool(out, 'com.apple.security.files.user-selected.read-only', true, changes);
  out = setBool(out, 'com.apple.security.app-sandbox', false, changes);
  // Keychain access, so the login can be saved securely (flutter_secure_storage asks for this).
  if (!out.includes('<key>keychain-access-groups</key>')) {
    const at = out.lastIndexOf('</dict>');
    out = `${out.slice(0, at)}\t<key>keychain-access-groups</key>\n\t<array/>\n${out.slice(at)}`;
    changes.push('keychain-access-groups added');
  }
  return { text: out, changes };
}

const TARGETS = [
  ['android/app/src/main/AndroidManifest.xml', patchAndroidManifest],
  ['ios/Runner/Info.plist', patchInfoPlist],
  ['macos/Runner/DebugProfile.entitlements', patchEntitlements],
  ['macos/Runner/Release.entitlements', patchEntitlements],
];

async function main() {
  const appDir = process.argv[2] ?? '.';
  for (const [file, patch] of TARGETS) {
    const path = join(appDir, file);
    let text;
    try {
      text = await readFile(path, 'utf8');
    } catch {
      console.log(`skipped   ${file} (not found)`);
      continue;
    }
    const result = patch(text);
    if (result.changes.length === 0) {
      console.log(`unchanged ${file}`);
      continue;
    }
    await writeFile(path, result.text);
    console.log(`patched   ${file}`);
    for (const c of result.changes) console.log(`            - ${c}`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) await main();
