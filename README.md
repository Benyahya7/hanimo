# Hanimo

Hanimo is an anime app for Android, plus its official website — both built with Flutter.

**Website:** https://benyahya7.github.io/hanimo/
**Latest APK:** https://github.com/benyahya7/hanimo/releases/download/v2.0.1/Hanimo-2.0.1.apk (version 2.0.1, Android, ~61 MB)

## What Hanimo 2.0.1 does

- Rebuilt from scratch — clean architecture, nothing fails silently
- Catalog, episodes and servers from Animeify, fresh on every open: trending, latest episodes, airing today, this season
- Tap a title, pick an episode and a server, watch in the built-in player (tap controls, ±10s, speed, fullscreen, resume)
- My List favourites, Continue Watching, live search, Arabic UI with full RTL
- Sign in with Google for a private profile and Hanimo ID — the owner account gets Admin automatically, no UID to copy, no setup step
- Admin: import top anime, manage the catalog, publish update notices

Content comes from Animeify's server. The app itself bundles no streams.

## Repo layout

- `website/` — Flutter web source for the official site (download + showcase page). Pushed to GitHub Pages automatically by `.github/workflows/pages.yml` on every push to `website/`.
- `app/` — Flutter Android source snapshot, version 1.0.2. The 2.0.1 source sync is still to come.
- `website/assets/` — anime artwork for the site (hero, series, movie) and the Hanimo icon.

Note: the full app is Android-only for now. Its catalog API does not send CORS headers, so a browser cannot read it directly — that is why this site is a download page instead of the app running in the browser.

## Build the website locally

```sh
cd website
flutter pub get
flutter build web --base-href /hanimo/
```

## Build the Android app locally

```sh
cd app
flutter pub get
flutter build apk --release
```

Note: Android builds must be signed with the release keystore. Add that build's SHA-1/SHA-256 fingerprints to the Hanimo Android app in Firebase, or Google sign-in will fail with an invalid-cert-hash error.
