// Firebase client config for project anime-app-556c8.
// Public client config by design (security is enforced by Firestore rules).
//
// Android app: com.example.animeapp
//   App ID 1:176785196605:android:de37cf677f971f2189cc54
//   (android/app/google-services.json is present)
// Web app: anime-app-web
//   App ID 1:176785196605:web:0494a91c5c62ed0289cc54
//   (registered in the Firebase console; serves benyahya7.github.io/hanimo)
// If Firebase init still fails, the app falls back to local demo data.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macOS.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for Linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDhbLuN_oqKa3sEvCgg34bkQvZi3-j-Oi8',
    appId: '1:176785196605:web:0494a91c5c62ed0289cc54',
    messagingSenderId: '176785196605',
    projectId: 'anime-app-556c8',
    authDomain: 'anime-app-556c8.firebaseapp.com',
    storageBucket: 'anime-app-556c8.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDhbLuN_oqKa3sEvCgg34bkQvZi3-j-Oi8',
    appId: '1:176785196605:android:de37cf677f971f2189cc54',
    messagingSenderId: '176785196605',
    projectId: 'anime-app-556c8',
    authDomain: 'anime-app-556c8.firebaseapp.com',
    storageBucket: 'anime-app-556c8.firebasestorage.app',
  );
}
