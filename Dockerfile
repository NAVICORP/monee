# Pursee on SkiFi's own server (pursee.skifi.co), on the shared SkiFi app base:
# the database API and sign-in through SkAuth.
#
# Dokploy builds this image itself from GitHub on every push to main (the repo
# is private, so nothing has to be pulled from a registry). Two steps: the
# Flutter web app, then the app base with the migrations, the site and the
# web app inside. The same image runs twice (deploy/docker-compose.yml): as
# the API, and as the site in front of it (server/site.mjs).

FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /build/app
COPY app/pubspec.yaml ./
RUN flutter pub get
COPY app ./
RUN flutter build web --release --no-web-resources-cdn --base-href /app/ \
 && rm -f build/web/flutter_service_worker.js

FROM ghcr.io/navicorp/skifi-app:latest
USER root
COPY supabase/migrations /srv/app/migrations
COPY server /srv/site/server
COPY web /srv/site/web
COPY --from=web /build/app/build/web /srv/site/app
# Compressed ahead of time, so the site never makes anyone wait while it
# compresses an engine file (server/pack.mjs).
RUN node /srv/site/server/pack.mjs /srv/site/app /srv/site/web
ENV SITE_ROOT=/srv/site/web APP_ROOT=/srv/site/app
USER node
