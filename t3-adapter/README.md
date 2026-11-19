# T3 0.1.7 local route fixture

Pinned source: [v0.1.7](https://github.com/pingdotgg/t3code/tree/v0.1.7).
[Public thread links](https://github.com/pingdotgg/t3code/blob/v0.1.7/docs/user/prompt-links.md#share-a-thread) and [route](https://github.com/pingdotgg/t3code/blob/v0.1.7/apps/web/src/routes/threads.%24environmentId.%24threadId.tsx) show `/threads/<environment>/<thread>` redirects to the exact IDs. This module **only builds a candidate link** for a literally loopback origin; no network, credentials, browser, clipboard, T3 settings, or app process access. The caller is responsible for authenticating the T3 origin, revalidating slot identity at the navigation boundary, and showing/handling any chooser. The scheme and loopback check do not authenticate a process or validate that the browser can resolve the environment.

The installed T3 Code (Beta) app reports 0.1.7. The public hosted redirect
is deliberately disallowed, and no stable standalone status feed was
verified. Use the native route below in preference to the legacy loopback
fixture. Files under .upstream, if present, are a read-only source checkout,
not a dependency.

Test: `PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest -v`.

## Native launcher (source-verified, not runtime-tested)

`native_thread_url("0.1.7", "env-A", "thread_1")` emits only
`t3code://threads/env-A/thread_1`. No HTTP endpoint or query is involved;
an unrecognized version or identifier fails closed. This helper performs no
send and is not wired into the Swift app.

The pinned [macOS handler](https://github.com/pingdotgg/t3code/blob/v0.1.7/apps/desktop/src/app/DesktopClerk.ts#L1059-L1094)
forwards native links accepted by [the parser](https://github.com/pingdotgg/t3code/blob/v0.1.7/packages/shared/src/promptLinks.ts#L184-L215)
to the desktop renderer, whose [coordinator](https://github.com/pingdotgg/t3code/blob/v0.1.7/apps/web/src/components/desktop/DesktopWebLinkCoordinator.tsx)
navigates to the exact path. Generic HTTP(S) validation does not govern this branch.
The macOS URL scheme is not a state feed or acknowledgment; restrict future
delivery to the verified app instance and validate the selected local
environment/thread and generation at dispatch. Do not auto-launch into the
user's existing profile for testing.
