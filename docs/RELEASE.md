# Putting Monee on the server and the stores

## 1. The server (once)

1. **SkAuth knows Monee (optional).** Sign-in works without it. Listing Monee in `SKAUTH_APPS` on the SkAuth service (Dokploy, Raw compose) brands its sign-in emails as Monee:
   `{"id":"monee","name":"Monee","site":"https://monee.skifi.co","api":"https://monee.skifi.co","color":"#6D4AE8"}`
   then redeploy SkAuth.
2. **Dokploy compose.** New compose `monee` from GitHub `NAVICORP/monee` (a private repo: Dokploy's GitHub connection needs access to it), branch `main`, compose path `./deploy/docker-compose.yml`. Domain `monee.skifi.co` to service `site`, port 8000, HTTPS on. Deploy. Receipt photos live in the volume `monee_storage`.
3. **DNS.** On Cloudflare, skifi.co: an A record `monee` to the VPS (179.198.218.204).
4. Open https://monee.skifi.co/health. It says `{"ok":true}`. The web app is at https://monee.skifi.co/app/.
5. **Redeploy on every push.** Turn on Autodeploy for the compose in Dokploy: each push to `main` builds the image on the server (about 5 minutes, the Flutter web build included) and restarts Monee.

The database moves forward by itself: on start, the API applies any migration it has not run yet.

## 2. Android

1. Make the upload key once and keep it, with its passwords, in your password manager:
   `keytool -genkey -v -keystore monee-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. GitHub > NAVICORP/monee > Settings > Secrets and variables > Actions, add:
   - `ANDROID_KEYSTORE_B64`: the file as base64 (`base64 -i monee-upload.jks | pbcopy` on a Mac)
   - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`upload`), `ANDROID_KEY_PASSWORD`
3. Every push then builds `monee-android-bundle` (the .aab) next to the test APK, under Actions > the run > Artifacts.
4. Play Console > Create app: name **Monee**, package `co.skifi.monee`, free, app.
5. Upload the .aab to **Internal testing** first, then Closed testing, then production.
6. App content:
   - Privacy policy: https://monee.skifi.co/privacy
   - App access: give the review account (section 4).
   - Ads: none. Data safety: collects phone number or email (sign-in), name, the person's own money records and any receipt photos they attach; nothing shared, nothing sold, encrypted in transit, deletion at https://monee.skifi.co/delete-account.
7. **Updates.** Raise `version:` in `app/pubspec.yaml` (1.0.1, 1.0.2, ...). The version code is the App run number, so every build is higher than the last.

## 3. iPhone

No Mac needed: GitHub Actions builds the app and uploads it to TestFlight, the same way as Kuree.

1. Apple Developer > Identifiers: register the bundle id `co.skifi.monee`.
2. App Store Connect > Apps > New App: iOS, name **Monee**, bundle id `co.skifi.monee`, SKU `monee`.
3. Repository secrets (the same values Kuree uses): `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_P8`.
4. Actions > App > Run workflow, tick **testflight**. The build shows in TestFlight once Apple has processed it.

## 4. The review account

Both stores need a way in without a WhatsApp code. Make an email account with a password once (an address you can open, for example review@skifi.co):

```
curl -X POST https://monee.skifi.co/auth/v1/signup -H 'apikey: public' -H 'content-type: application/json' \
  -d '{"email":"review@skifi.co","password":"choose-a-long-one"}'
```

Confirm the email it sends, sign in once in the app with Email > Use a password, and start a book with a few accounts and transactions (or load tools/demo.sql into it on the server). Give that email and password to both stores.

## 5. Store listing

- Name: Monee. Icon: `app/assets/brand/icon.png` (1024 x 1024).
- Screenshots: from the demo book (tools/demo.sql).
- Support email: contact@skifi.co. Website: https://monee.skifi.co
