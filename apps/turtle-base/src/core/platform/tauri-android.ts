import { invoke } from '@tauri-apps/api/core';
import type { GoogleAuthenticator, KeyValueStore } from '@turtle-base/platform';

/** Runs `command` of the shell's AndroidPlatformPlugin.kt - what Tauri's own plugins don't cover on Android. */
export function androidPlatform<T = void>(command: string, args: Record<string, unknown> = {}): Promise<T> {
  return invoke<T>('android_platform', { command, args });
}

/** The Google account Drive sync is connected with - set while connected. */
const googleAccountKey = 'google_drive_account';

/** How long an access token is reused before Play services is asked again (it hands out tokens valid for an hour). */
const accessTokenReuseMs = 5 * 60 * 1000;

/**
 * Google sign-in for Drive sync through Play services' AuthorizationClient.
 * Connected is remembered in the prefs, so a silent sign-in works offline;
 * tokens come from Play services when needed.
 */
export function androidGoogleAuth(prefs: KeyValueStore): GoogleAuthenticator {
  let reusable: { token: string; until: number } | undefined;

  async function authorize(interactive: boolean) {
    const result = await androidPlatform<{ accessToken: string; account?: string }>('authorize', { interactive });
    reusable = { token: result.accessToken, until: Date.now() + accessTokenReuseMs };
    return result;
  }

  return {
    signInSilently: () => Promise.resolve(prefs.get(googleAccountKey) !== undefined),
    signIn: async () => {
      const { account } = await authorize(true);
      await prefs.set(googleAccountKey, account ?? '');
    },
    signOut: async () => {
      const account = prefs.get(googleAccountKey);
      reusable = undefined;
      await prefs.remove(googleAccountKey);
      if (account !== undefined && account.length > 0) await androidPlatform('signOut', { account });
    },
    accessToken: async () =>
      reusable !== undefined && reusable.until > Date.now() ? reusable.token : (await authorize(false)).accessToken,
  };
}
