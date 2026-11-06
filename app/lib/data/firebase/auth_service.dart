// Sign-in. Native Google Sign-In only — NEVER signInWithProvider, its
// browser redirect dies on sessionStorage in Android Custom Tabs (the
// 2026-11-05 lesson). google_sign_in 7 on Android REQUIRES the Web OAuth
// Client ID as serverClientId.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'package:animeapp/app_constants.dart';
import 'package:animeapp/core/result.dart';

class AuthService {
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final GoogleSignIn _signIn;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? db, GoogleSignIn? signIn})
      : auth = auth ?? FirebaseAuth.instance,
        db = db ?? FirebaseFirestore.instance,
        _signIn = signIn ?? GoogleSignIn.instance;

  User? get currentUser => auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// One call that does everything the app needs at sign-in time:
  /// native Google sign-in -> Firebase credential -> admin check.
  /// Returns Err with the real message on any failure.
  Future<Result<bool>> signIn() async {
    try {
      await _signIn.initialize(serverClientId: kGoogleWebClientId);
      final account = await _signIn.authenticate();
      final googleAuth = account.authentication;
      final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
      await auth.signInWithCredential(credential);
      return Result.ok(await isAdmin());
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return const Err('Sign-in cancelled.');
      }
      return Err('Google sign-in failed: ${e.code.name}');
    } catch (e) {
      return Err('Sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    await auth.signOut();
  }

  /// Admin = an admins/{uid} doc exists, OR the signed-in email is the
  /// owner's. No UID is shown anywhere in the app.
  Future<bool> isAdmin() async {
    final user = currentUser;
    if (user == null) return false;
    if (user.email == kOwnerEmail) return true;
    try {
      final doc = await db.collection('admins').doc(user.uid).get();
      return doc.exists;
    } catch (_) {
      return false;
    }
  }

  /// Hanimo ID: HNM-XXXXXX from the uid hash. Public, no email in it.
  static String hanimoIdFor(String uid) {
    final hash = uid.hashCode.abs() % 1000000;
    return 'HNM-${hash.toString().padLeft(6, '0')}';
  }
}
