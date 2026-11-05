# Hanimo — Flutter MVP

App display name: Hanimo. Package: com.example.animeapp (unchanged).
Launcher icon: the user's cropped 1024x1024 Hanimo icon, manually resized
into mipmap-mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi ic_launcher.png +
ic_launcher_round.png, and copied to assets/icon/hanimo-icon.png for the
Home header logo. No flutter_launcher_icons package was needed.

Animefy-style, dark theme, custom UI in code (mitesh77 / olayemii kits are
reference only, no kit code is copied here).

Backend: Firebase project anime-app, project ID anime-app-556c8, Spark free.
Firestore collections: categories, items, playlists, admins, users/{uid}.
Rules: viewers read the catalog, only admins in /admins/{uid} write it,
users own their own users/{uid} data.

## Run
```
source ~/workspace/tools/flutter-android-env.sh
cd ~/workspace/anime-app/flutter
flutter pub get
flutter run
flutter build apk --release
```

## Screens
Home (categories grid, recent), Browse, Search, My List (favourites, local),
Import (paste an M3U URL or M3U text, parsed locally; Save to Firestore is
admin-only), Admin, Item detail (Play / Share / favourite), Player.

Player: direct mp4/m3u8 URLs play in-app. Empty URL shows "No link yet".
Other web links open in the browser. No streams, links or playlists are
bundled — only the 2 demo items from the Firestore seed (empty urls).
All real links are added by the admin.

## Storage limitation
Firebase Storage was NOT created for this project: on Spark it now requires
a Blaze upgrade. So the app uses placeholder images when imageUrl is empty,
and external image URLs otherwise. Do not expect Firebase Storage uploads
until a Blaze upgrade is approved.

## How to enable admin writes (required step)
1. Run the app and sign in with Google on the Admin tab.
2. Copy the UID shown there.
3. In the Firebase console, Firestore, create collection `admins`,
   document ID = that UID (any field, e.g. `role: "admin"`).
4. Sign out and back in, or tap refresh — Admin should now show
   "You are an admin" and Add/Edit/Delete buttons appear.
Do not invent a UID. Until step 3 is done, writes are correctly blocked
by the published Firestore rules.

## Firebase Android registration (known limitation)
The Firebase config in lib/firebase_options.dart was registered as a WEB
app in the console. The app tries manual initialization with it and falls
back to local demo data (3 categories + 2 demo items, with an
"offline / demo data" note) if Firebase init fails.
For fully native Android Google sign-in, add an Android app in the Firebase
console with package com.example.animeapp, download
google-services.json, and place it in android/app/, then rebuild.
Viewer reads of Firestore should still be attempted first; the fallback
is only shown when init/read actually fails — it is not presented as live data.

## Test on a real phone
Install the release APK, check: Home categories load, tap a category,
tap an item, Play with an empty URL shows the "No link yet" message,
Share opens the system sheet, favourites persist after restart,
Import parses a pasted M3U sample, Admin shows your UID.
