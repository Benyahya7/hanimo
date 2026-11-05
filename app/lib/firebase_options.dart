// Firebase client config for project anime-app-556c8.
// Public client config by design (security is enforced by Firestore rules).
// NOTE: An Android app is now registered in the Firebase console
// (package com.example.animeapp), and android/app/google-services.json
// is present. The appId below is the Android App ID, so native Android
// Google sign-in works. If Firebase init still fails, the app falls
// back to local demo data.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => const FirebaseOptions(
        apiKey: 'AIzaSyDhbLuN_oqKa3sEvCgg34bkQvZi3-j-Oi8',
        appId: '1:176785196605:android:de37cf677f971f2189cc54',
        messagingSenderId: '176785196605',
        projectId: 'anime-app-556c8',
        authDomain: 'anime-app-556c8.firebaseapp.com',
        storageBucket: 'anime-app-556c8.firebasestorage.app',
      );
}
