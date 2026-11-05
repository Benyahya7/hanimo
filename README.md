# Hanimo

Hanimo is an anime app for Android, plus its official website — both built with Flutter.

**Website:** https://benyahya7.github.io/hanimo/
**Latest APK:** https://github.com/benyahya7/hanimo/releases/download/v1.0.2/Hanimo-1.0.2.apk (version 1.0.2, Android, ~56 MB)

## What Hanimo does

- Browse categories with posters, series, movies and live channels
- Play links the owner adds, and import an M3U playlist you already have — it becomes categories and channels
- Share any title with friends in one tap
- Sign in with Google for a private profile, favourites, and messages (messages are seen only by sender and recipient)
- The owner account gets Admin automatically — no UID to copy, no setup step

Content comes from links and playlists the owner adds. The app itself bundles no streams.

## Repo layout

- `website/` — Flutter web source for the official site. Pushed to GitHub Pages automatically by `.github/workflows/pages.yml`.
- `app/` — Flutter Android source for the Hanimo app (package `com.example.animeapp`, version 1.0.2+3). Launcher icon files (`mipmap-*/ic_launcher*.png`) and website images are uploaded separately because they are binary files.
- `website/assets/` — anime artwork for the site (hero, series, movie) and the Hanimo icon.

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

Note: Android builds sign with the debug key by default in this project. If you switch to a release keystore, add that build's SHA-1/SHA-256 fingerprints to the Hanimo Android app in Firebase, or Google sign-in will fail with an invalid-cert-hash error.
