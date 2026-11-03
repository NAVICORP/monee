# Putting Pursee on the server and the stores

## 0. The sitting at the Mac (Ishaque and Claude, about 45 minutes)

Ready before it: the store texts (`docs/STORE.md`), the store pictures and Play feature graphic (`store-pictures` branch: `store/ios`, `store/play`), the review book for contact@skifi.co (live), the Android upload key (`monee-signing.zip`, sent in chat), and the App Store page filler (Actions > App Store page).

1. **The new address (done 3 Nov).** pursee.skifi.co: an A record `pursee` to 179.198.218.204 on Cloudflare (DNS only), the domain on the Dokploy compose (service `site`, port 8000, HTTPS), and the app, site and server settings switched to it. monee.skifi.co stays on the compose and redirects pages to pursee.skifi.co (`OLD_HOSTS`).
2. **GitHub secrets (you, 5 min).** NAVICORP/monee > Settings > Secrets and variables > Actions: the four `ANDROID_*` values from `github-secrets.txt`, and `APP_STORE_CONNECT_KEY_P8` (the same .p8 text Kuree and Dairee use) unless it is already an organisation secret. The team, key and issuer ids already default to Kuree's in the workflows.
3. **Google Play (you 5 min, then Claude).** Play Console > Create app: the name, English (United States), App, Free, tick the two declarations. Claude then fills the store listing, graphics, app access (you type the review password), ads, content rating, target audience, data safety, financial features and privacy policy; runs Actions > App with **play_bundle**; and uploads the bundle to a testing track, then production.
4. **App Store (you 5 min, then Claude).** Actions > App > Run workflow with **testflight** registers the bundle id `co.skifi.pursee` by itself. Then App Store Connect > New App: iOS, the name, English (U.S.), bundle `co.skifi.pursee`, SKU `pursee`, full access. Run **testflight** again for the first build, then Actions > App Store page (version 1.0.0) fills the text, screenshots, categories and review details. Claude fills age rating and App Privacy; you type the review password, then Add for Review and Submit.
5. **After approval.** Put the App Store link in `STORE.ios` in `web/assets/home.js`, and check the Play link there.

## 1. The server (once)

1. **SkAuth knows Pursee (optional).** Sign-in works without it. Listing Pursee in `SKAUTH_APPS` on the SkAuth service (Dokploy, Raw compose) brands its sign-in emails as Pursee:
   `{"id":"monee","name":"Pursee","site":"https://pursee.skifi.co","api":"https://pursee.skifi.co","color":"#6D4AE8"}`
   then redeploy SkAuth.
2. **Dokploy compose.** New compose `monee` from GitHub `NAVICORP/monee` (a private repo: Dokploy's GitHub connection needs access to it), branch `main`, compose path `./deploy/docker-compose.yml`. Domains `pursee.skifi.co` and `monee.skifi.co` to service `site`, port 8000, HTTPS on. Deploy. Receipt photos live in the volume `monee_storage`.
3. **DNS.** On Cloudflare, skifi.co: A records `pursee` and `monee` to the VPS (179.198.218.204), DNS only.
4. Open https://pursee.skifi.co/health. It says `{"ok":true}`. The web app is at https://pursee.skifi.co/app/.
5. **Redeploy on every push.** Turn on Autodeploy for the compose in Dokploy: each push to `main` builds the image on the server (about 5 minutes, the Flutter web build included) and restarts Pursee.

The database moves forward by itself: on start, the API applies any migration it has not run yet.

## 2. Android

1. Make the upload key once and keep it, with its passwords, in your password manager:
   `keytool -genkey -v -keystore monee-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. GitHub > NAVICORP/monee > Settings > Secrets and variables > Actions, add:
   - `ANDROID_KEYSTORE_B64`: the file as base64 (`base64 -i monee-upload.jks | pbcopy` on a Mac)
   - `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`upload`), `ANDROID_KEY_PASSWORD`
3. Every push then builds `monee-android-bundle` (the .aab) next to the test APK, under Actions > the run > Artifacts.
4. Play Console > Create app: name **Pursee**, package `co.skifi.pursee`, free, app.
5. Upload the .aab to **Internal testing** first, then Closed testing, then production.
6. App content:
   - Privacy policy: https://pursee.skifi.co/privacy
   - App access: give the review account (section 4).
   - Ads: none. Data safety: collects phone number or email (sign-in), name, the person's own money records and any receipt photos they attach; nothing shared, nothing sold, encrypted in transit, deletion at https://pursee.skifi.co/delete-account.
7. **Updates.** Raise `version:` in `app/pubspec.yaml` (1.0.1, 1.0.2, ...). The version code is the App run number, so every build is higher than the last.

## 3. iPhone

No Mac needed: GitHub Actions builds the app and uploads it to TestFlight, the same way as Kuree.

1. Repository secret `APP_STORE_CONNECT_KEY_P8` (the same .p8 Kuree uses). `APPLE_TEAM_ID`, `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID` default to Kuree's values in the workflows; set them only to use another key.
2. Actions > App > Run workflow, tick **testflight**. The first run registers the bundle id `co.skifi.pursee` with Apple by itself.
3. App Store Connect > Apps > New App: iOS, the app's name, bundle id `co.skifi.pursee`, SKU `pursee`.
4. Run **testflight** again. The build shows in TestFlight once Apple has processed it.
5. Actions > App Store page > Run workflow (version 1.0.0): fills the page from `docs/STORE.md` and the `store-pictures` branch, and attaches the newest build.

## 4. The review account

Both stores need a way in without a WhatsApp code. Make an email account with a password once (an address you can open, for example review@skifi.co):

```
curl -X POST https://pursee.skifi.co/auth/v1/signup -H 'apikey: public' -H 'content-type: application/json' \
  -d '{"email":"review@skifi.co","password":"choose-a-long-one"}'
```

Confirm the email it sends, sign in once in the app with Email > Use a password, and start a book with a few accounts and transactions (or load tools/demo.sql into it on the server). Give that email and password to both stores.

## 5. Store listing

- Name: Pursee. Icon: `app/assets/brand/icon.png` (1024 x 1024).
- Screenshots: from the demo book (tools/demo.sql).
- Support email: contact@skifi.co. Website: https://pursee.skifi.co
