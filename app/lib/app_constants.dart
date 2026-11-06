// Build + identity constants for Hanimo 2.0.
//
// kCurrentBuild MUST match pubspec's build number (2.0.0+16): the in-app
// update banner compares it against Firestore config/app_update.
const int kCurrentBuild = 17;
const String kCurrentVersionName = '2.0.1';

// Verified Web OAuth Client ID (Google Cloud Console, 2026-11-05).
// Passed as serverClientId to GoogleSignIn — a public client ID, not a secret.
const String kGoogleWebClientId = '176785196605-osm2pkehqes1p5npu9e3pbqrgecsjd19.apps.googleusercontent.com';

// The owner signs in as this email and is Admin automatically.
const String kOwnerEmail = 'raiss95@gmail.com';
