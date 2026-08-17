import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class AuthService {
  /// Signs out of Firebase Auth, Google Sign-In, and Facebook Auth.
  static Future<void> signOut() async {
    try {
      await Future.wait([
        GoogleSignIn().signOut(),
        FacebookAuth.instance.logOut(),
      ]);
    } catch (e) {
      print('Error signing out of social providers: $e');
    }
    
    await FirebaseAuth.instance.signOut();
  }
}
