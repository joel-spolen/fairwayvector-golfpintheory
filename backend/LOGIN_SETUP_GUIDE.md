# PinTheory login setup — step-by-step operator guide

Updated: 2026-10-21. Dashboard labels can change; use the linked official guides when a menu differs.

## Current email + password configuration (supersedes magic-link instructions below)

The app now has **Sign in**, **Create account**, **Forgot password**, and Google browser login. Apple is deferred. URL-scheme routing is integrated; actual account flows have compiled but have not been tested against the live service. Older sections below describe the original passwordless plan and must not be followed for the current email UI.

1. In Authentication → Sign In / Providers → Email, keep **Email enabled**, **new user signups enabled** for your test cohort and **Confirm email enabled**. Password login uses the same Email provider; no new client key is required. Set a suitable server-side password policy (recommended minimum eight characters, stronger as appropriate). The app recommends eight for new passwords; Supabase is authoritative.
2. In Authentication → URL Configuration → Redirect URLs, allowlist BOTH exact values: `golfpintheory://auth/callback` and `golfpintheory://auth/reset-password`. If using a mobile Site URL, set it to `golfpintheory://auth/callback`; an existing HTTPS fallback can remain. Remove the old custom-scheme redirect; this prelaunch app does not support it. Google's HTTPS provider callback remains unchanged.
3. In Authentication → Emails / Email Templates → **Confirm signup**, use a subject such as **Confirm your PinTheory account** and keep the action link as `{{ .ConfirmationURL }}`. This is now the signup email template, NOT Magic Link. Label the button **Confirm email**. Do not paste a literal mobile callback URL or a custom token-hash URL into that button.
4. In Email Templates → **Reset Password**, use **Reset your PinTheory password**, retain `{{ .ConfirmationURL }}` and label the button **Reset password**. Supabase must preserve the request's `redirect_to` destination so this returns to `/reset-password`, not the ordinary `/callback` path.
5. The existing Magic Link template can remain, but it is no longer used by the email/password login screen. Existing SMTP/domain settings still apply to signup confirmation and reset mail. Changing login style does not solve SMTP, recipient restrictions or delivery failures.
6. Keep email sender link/click tracking disabled. Request signup/reset on the device on which you will open its email; PKCE confirmation/reset requires that installation's verifier. If opening confirmation elsewhere, return to the requesting device; cross-device browser completion needs a separately designed web flow.
7. After rebuilding, create a test account, confirm the email, then sign in with email/password. Returning logins do not send email. Existing magic-link/Google-only identities may not have a password: use **Forgot password** for the same email rather than creating duplicates. Apple private-relay emails and provider linking still need deliberate handling.
8. Test Forgot password on the requesting device, open the reset link, enter/confirm a new password, then sign in again. Recovery sessions never expose Home. Restarting during recovery must keep the recovery gate; successful updates clear local credentials and require normal sign-in.

Passwords are entered only in the app's secure fields and sent over HTTPS to Supabase; they are not stored by the app. Do not paste passwords, confirmation/reset URLs, codes, SMTP secrets or tokens into chat. Account deletion and cloud golf-record sync are still unfinished and remain release gates.

**Historical provider setup follows.** No dashboard changes or deployments have been made by writing this guide. Start with development/staging, not real customer data.

## 1. Confirm project and app identity

1. Open [your Supabase project](https://supabase.com/dashboard/project/hdeiikpgtralsfnwbxft).
2. Decide whether this is the development/staging project. Recommended: use it for staging and create a separate production project before release.
3. Check the selected region and billing settings. Enable multifactor authentication on your operator accounts; keep recovery codes in your password manager.
4. In Xcode, check the app target's Signing & Capabilities → Bundle Identifier. The implementation plan uses `com.fairwayvector.app.pintheory`; confirm the actual identifier before registering Apple/Google clients. If this replaces an existing App Store app, retain that app's registered bundle identity rather than changing it casually.
5. Select the Apple Developer team that owns the app. An Apple Developer Program membership is needed for native Sign in with Apple capabilities.

The supplied project URL and publishable key are already in the ignored local app configuration. Do not repeat the key in documentation. Provider secrets, SMTP passwords, database passwords, Apple signing keys and Supabase administrative keys belong only in trusted dashboards/secret storage, never chat or the mobile app.

## 2. Configure the Supabase redirect URLs

1. Open Supabase → Authentication → URL Configuration.
2. For a mobile-only staging setup, set **Site URL** to `golfpintheory://auth/callback`. Supabase supports mobile URI schemes as the default destination. If using an HTTPS fallback instead, it must be a real page you own that explains how to return to the app—not an invented callback page.
3. Under **Redirect URLs**, add exactly `golfpintheory://auth/callback` and `golfpintheory://auth/reset-password`.
4. Save. Avoid wildcard redirects in production.

There are TWO different callbacks. Do not interchange them:

| Purpose                                                       | Value for this project                                      |
| ------------------------------------------------------------- | ----------------------------------------------------------- |
| Apple/Google → Supabase (enter in the provider console)       | `https://hdeiikpgtralsfnwbxft.supabase.co/auth/v1/callback` |
| Supabase → PinTheory (enter in Supabase's redirect allowlist) | `golfpintheory://auth/callback`                             |

The app registers only the `golfpintheory` URL scheme and routes both ordinary and password-reset callbacks. A future staging-specific scheme/universal-link design may require updating both code and allowlist together. Repeat all project-specific URLs for a separate production project.

## 3. Enable email sign-in

1. Open Authentication → Sign In / Providers (sometimes labelled Providers).
2. Select **Email** and enable it.
3. Keep email verification enabled; do not enable automatic email confirmation to bypass delivery problems.
4. Allow new-user signups for the intended test cohort. Leave anonymous sign-ins and unused providers disabled.
5. Keep normal security defaults for session/JWT lifetimes. Do not enable a single-session-per-user restriction if users should stay signed in on multiple devices.

### Email template

1. Open Authentication → Email Templates → Magic Link (or Magic Link / OTP).
2. Use a recognizable subject such as **Sign in to PinTheory**.
3. Preserve Supabase's `{{ .ConfirmationURL }}` as the sign-in link destination. Do not replace it with a direct app URL or a token-hash callback; the staged service expects a PKCE authorization-code callback, not an implicit token fragment or token-hash URL.
4. Optionally include `{{ .Token }}` as the code for the app's email-code fallback. This requires the corresponding code-entry UI, which is not yet connected.
5. Disable click/link tracking for authentication emails at your sending provider; tracking rewrites and automated scanners can interfere with one-time links.
6. Save. After app integration, request a link from the app and open it on the same device that requested it: PKCE needs that device's stored verifier. Use code entry for cross-device email reading once supported by the UI.

## 4. Configure email delivery (custom SMTP)

Supabase's built-in sender is for limited testing, not production. Currently it sends only to organization team addresses and has a very small quota. Do not invite customers to your Supabase organization just to bypass this limit.

1. Choose a transactional email provider, for example Resend, Postmark or Amazon SES.
2. Add a sending domain/subdomain that you own. Choose the actual domain first; there is no requirement to purchase a particular new domain.
3. In your DNS provider, add the exact DKIM/SPF verification records requested by the email service. Configure DMARC appropriately. Do not create multiple competing SPF records for the same domain.
4. Wait until the provider reports the sender/domain verified. If the provider account is sandboxed, complete its production-access requirements before inviting arbitrary recipients.
5. Obtain the provider's SMTP host, port, username and password. Store these securely.
6. Open Supabase → Authentication → Email / SMTP Settings, then enable custom SMTP.
7. Enter those SMTP settings, sender name **PinTheory**, and a verified sender address on your domain.
8. Save. Review Authentication → Rate Limits and the provider's quota; choose conservative limits suitable for testing, then revisit before launch.
9. After app integration, test delivery to addresses outside your Supabase organization and check inbox/spam, sender identity and link behavior. Never share a live link/code in chat.

Email delivery is separate from Google/Apple sign-in. You can configure email first while the social providers are pending.

## 5. Configure Google login — current browser-PKCE flow

The foundation currently opens Google in a browser authentication session. Start with a **Web application** OAuth client even though PinTheory itself is an iOS app. Native Google SDK integration is deferred.

1. Open [Google Cloud Console](https://console.cloud.google.com/) and create/select a project for PinTheory.
2. Open **Google Auth Platform** (older consoles may use APIs & Services → OAuth consent screen).
3. Under **Branding**, enter **PinTheory**, a monitored support email, developer contact, and your real homepage/privacy-policy/terms URLs. Do not use the current outdated local-only privacy text for a public launch.
4. Add/verify domains you own if Google requests it. Do not attempt to claim ownership of `supabase.co`.
5. Under **Audience**, choose **External** for a consumer app. While in Testing, add each tester's Google account under Test users.
6. Under **Data Access**, request only `openid`, `userinfo.email` and `userinfo.profile`. Do not add Gmail, Drive or unrelated scopes.
7. Under **Clients**, create an OAuth client of type **Web application**. Name it something like **PinTheory staging browser login**.
8. Under **Authorized redirect URIs**, add exactly `https://hdeiikpgtralsfnwbxft.supabase.co/auth/v1/callback`.
9. A native browser redirect flow does not require JavaScript origins. Only add a real web origin if you later implement browser-hosted Google UI; never enter the custom mobile scheme in that field.
10. Create the client. Copy its client ID and secret directly into Supabase → Authentication → Providers → Google.
11. Enable Google and save. If multiple client IDs are configured later, put the web client ID first. Leave **Skip nonce check** disabled for this flow; do not weaken security just to troubleshoot.
12. Before public release, complete Google's publishing/brand/domain-verification requirements shown for your project; testing status limits who can sign in.

Later native Google setup requires an iOS OAuth client with the final bundle ID and an Android client with its final package name and signing certificate fingerprints. Do not guess the Android identifier now. Those additions are not required for the current browser-based foundation.

## 6. Configure native Sign in with Apple for iOS

1. Open [Apple Developer → Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Under **Identifiers → App IDs**, find or register the confirmed app bundle ID.
3. Enable **Sign in with Apple**, configure it as the primary App ID where appropriate, and save. Do not create a second identity if the existing app already has one.
4. Open Supabase → Authentication → Providers → Apple.
5. Enable Apple and add the actual bundle ID to its accepted **Client IDs**.
6. Save. Native-only identity-token sign-in does not require the browser OAuth Services ID/client secret in the next section.

The code integration will also add the matching Sign in with Apple capability/entitlement in Xcode and refresh signing/provisioning as needed. Dashboard configuration alone does not add that entitlement.

## 7. Add Apple browser login for Android (can wait until Android work)

This lets an Apple-first user access the same service from Android using Apple's browser flow. Grouping it with the native App ID helps preserve the intended Apple identity; verify the resulting identity in staging rather than assuming emails match.

1. In Apple Developer → Identifiers, create a **Services ID**. A proposed identifier is `com.fairwayvector.app.pintheory.auth`; confirm availability and ownership before using it.
2. Enable Sign in with Apple for that Services ID and select the native app's **Primary App ID**.
3. Configure Domains and Subdomains with `hdeiikpgtralsfnwbxft.supabase.co` (no scheme/path).
4. Configure Return URLs with `https://hdeiikpgtralsfnwbxft.supabase.co/auth/v1/callback`.
5. Save. Follow any additional requirements Apple shows for your account.
6. Under **Keys**, create a Sign in with Apple key associated with the primary app. Download its private signing key once and store it in a secure vault. Record the Key ID and Apple Team ID.
7. Generate an Apple client-secret JWT using trusted tooling and the Team ID, Key ID, private key and Services ID, following the official Supabase guide. The downloaded private key is NOT itself the client secret. Do not paste it into online tools you have not reviewed, the app, source control or chat.
8. In Supabase's Apple provider, list the **Services ID first**, then the native bundle ID in Client IDs, and enter the generated client secret in its secret field.
9. Save and assign a reminder/owner to renew the Apple client secret **before expiry, at most six months**. Missing renewal breaks browser Apple login; native-only token login has a different setup.
10. In Apple Developer → Services → Sign in with Apple for Email Communication, register the actual sending domains/addresses used to email Apple private-relay users and complete the sender authentication requirements. Check relay delivery with your SMTP provider.

## 8. Prepare the sync database — staging only, after review

Authentication can be configured without the custom sync migration. **Do not apply the current foundation migration to production just to make login work.**

1. Read [backend provisioning and blockers](README.md) and [the wire contract](CONTRACT.md).
2. Use a disposable staging project. If this supplied project will be production, create staging first and use its own URLs/provider callbacks.
3. Have the migration reviewed. Typed content allowlists, account deletion/purge, retention and app integration are still release blockers.
4. Once approved, open Supabase → SQL Editor → New query as the project/database owner.
5. Paste the **complete** [migration](migrations/202610190001_sync_foundation.sql), including its transaction boundaries; run once in staging and record the outcome. Do not run selected fragments, rerun blindly, or drop tables to resolve an error.
6. In Data API settings, keep the private `pintheory_sync` schema **unexposed**. Public RPCs are the intended access route. Do not grant anonymous access or disable RLS, and do not enable Realtime on private sync tables.
7. Coordinate authorized security/concurrency regression runs and two-user API checks before promotion. The SQL scripts have not been executed; writing them is not proof of database correctness.
8. Do not test account deletion against sync history yet: immutable-history triggers deliberately block erasure until a narrowly privileged deletion workflow is implemented.

## 9. Tell the implementation work what is ready

Send status only, for example:

- Project designated as staging or production.
- Confirmed bundle ID and Apple team selection.
- Supabase mobile redirect saved.
- Email provider enabled; SMTP verified or still pending.
- Google web OAuth provider configured; test users added.
- Apple native provider configured.
- Apple browser configuration done or deferred.
- Sync migration not deployed, or exact staging deployment outcome.

Client IDs, bundle IDs and public URLs are not administrative secrets. Do not send client secrets, private keys, SMTP passwords, database credentials, session tokens or live email links/codes. Redact them from screenshots.

## 10. Application work and acceptance before launch

This remains implementation work, not a dashboard checklist you can complete:

- Login UI, callback routing, native Apple capability, account-scoped storage and bootstrap gate.
- Actual saved-content sync, offline queue application, conflict-resolution UI and safe logout handling.
- Server-side account deletion/provider revocation and retention/purge handling.
- Updated in-app/public privacy policy, App Store data disclosures, support/reviewer access and backup/monitoring setup.

Once integrated, test each provider with an authorized staging account, cancellation, expired/reused links, offline restart, two devices, conflicting changes, logout/account switching and deletion. The same email across Apple/Google/email does not guarantee one account; do not promise automatic merging. Use the same login method across devices until linking behavior is deliberately supported and verified.

## Troubleshooting

| Symptom                                           | First check                                                                                                 |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Google `redirect_uri_mismatch`                    | Google's redirect URI must be the HTTPS Supabase callback, exactly.                                         |
| Google denies a tester                            | External Testing audience and Test users list.                                                              |
| Email says address not authorized                 | Built-in Supabase sender restrictions; configure custom SMTP.                                               |
| Link opens a website/localhost instead of the app | Exact Supabase mobile allowlist, template destination, app callback routing and installed build.            |
| Link opens app but sign-in fails                  | Same-device PKCE, expired/used link, correct project and registered scheme; do not share the link to debug. |
| Apple browser login fails after native works      | Services ID first in Client IDs, correct Return URL, current client-secret JWT.                             |
| App still has no login screen                     | Expected today: service setup does not enable unfinished app integration.                                   |
| Login works but records do not appear elsewhere   | Authentication is not sync; repository/sync integration and staging migration must also be ready.           |

## Official references

- [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Supabase email passwordless authentication](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Supabase custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp)
- [Supabase Google provider](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Supabase Apple provider](https://supabase.com/docs/guides/auth/social-login/auth-apple)
