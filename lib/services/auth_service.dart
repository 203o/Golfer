import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  GoogleSignIn? _googleSignIn;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String get _apiBaseUrl => getApiBaseUrl();

  String? _referralCodeFromUrl() {
    if (!kIsWeb) return null;
    final code = Uri.base.queryParameters['ref']?.trim() ?? '';
    if (code.isEmpty) return null;
    return code;
  }

  Future<String> _requireIdToken({User? user, bool forceRefresh = false}) async {
    final targetUser = user ?? _auth.currentUser;
    if (targetUser == null) {
      throw Exception('Please sign in first.');
    }

    String? token = await targetUser.getIdToken(forceRefresh);
    if ((token ?? '').isEmpty && !forceRefresh) {
      token = await targetUser.getIdToken(true);
    }
    if ((token ?? '').isEmpty) {
      throw Exception('Unable to get auth token.');
    }
    return token!;
  }

  GoogleSignIn _nativeGoogleSignIn() {
    _googleSignIn ??= GoogleSignIn();
    return _googleSignIn!;
  }

  String _friendlyAuthError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'popup-closed-by-user':
          return 'Google sign-in popup was closed before completion.';
        case 'popup-blocked':
          return 'Popup was blocked by the browser. Allow popups for this site and retry.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled in Firebase Authentication.';
        case 'unauthorized-domain':
          return 'This domain is not authorized in Firebase Authentication.';
        case 'network-request-failed':
          return 'Network error while contacting Firebase. Check connection and retry.';
        default:
          final msg = (error.message ?? '').trim();
          return msg.isEmpty ? 'Google sign-in failed (${error.code}).' : msg;
      }
    }
    final text = error.toString();
    if (text.contains('NotInitializedError')) {
      return 'Google auth is not fully initialized. Reload the page and try again.';
    }
    return text;
  }

  Future<UserCredential> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _registerOrSyncBackend(credential.user);
    return credential;
  }

  Future<UserCredential> createUserWithEmailAndPassword(
    String email,
    String password, {
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    if ((displayName ?? '').trim().isNotEmpty) {
      await credential.user?.updateDisplayName(displayName!.trim());
      await credential.user?.reload();
    }

    await _registerOrSyncBackend(credential.user);
    return credential;
  }

  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        final userCredential = await _auth.signInWithPopup(provider);
        await _registerOrSyncBackend(userCredential.user);
        return userCredential;
      }

      final googleUser = await _nativeGoogleSignIn().signIn();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      await _registerOrSyncBackend(userCredential.user);
      return userCredential;
    } catch (e) {
      throw Exception(_friendlyAuthError(e));
    }
  }

  Future<void> _registerOrSyncBackend(User? user) async {
    if (user == null) {
      throw Exception('No authenticated Firebase user found.');
    }

    final idToken = await _requireIdToken(user: user);
    final uri = Uri.parse('$_apiBaseUrl/api/golf/auth/register');
    final referralCode = _referralCodeFromUrl();
    final payload = <String, dynamic>{'id_token': idToken};
    if ((referralCode ?? '').isNotEmpty) {
      payload['referral_code'] = referralCode;
    }

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 400) {
      var detail = 'Backend registration failed.';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        detail = (body['detail'] ?? body['message'] ?? detail).toString();
      } catch (_) {}
      throw Exception(detail);
    }
  }

  Future<void> ensureBackendRegistration() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _registerOrSyncBackend(user);
  }

  Future<Map<String, dynamic>> fetchMyProfile() async {
    final token = await _requireIdToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/me/profile');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception('Failed to load profile (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMyReferral() async {
    final token = await _requireIdToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/me/referral');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception('Failed to load referral (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> completeProfileSetup({
    required String displayName,
    required String skillLevel,
    required String clubAffiliation,
  }) async {
    final token = await _requireIdToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/me/profile/setup');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'display_name': displayName,
        'skill_level': skillLevel,
        'club_affiliation': clubAffiliation,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception('Profile setup failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchMyWallet() async {
    final token = await _requireIdToken();
    final uri = Uri.parse('$_apiBaseUrl/api/golf/me/wallet');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode >= 400) {
      throw Exception('Failed to load wallet (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> topUpWallet({
    required double amount,
    String paymentProvider = 'stripe_mock',
  }) async {
    final token = await _requireIdToken();
    final uri =
        Uri.parse('$_apiBaseUrl/api/golf/me/wallet/topup/checkout-complete');
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'amount': amount,
        'payment_provider': paymentProvider,
      }),
    );
    if (response.statusCode >= 400) {
      throw Exception('Wallet top-up failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  Future<void> signOut() async {
    if (!kIsWeb) {
      try {
        await _nativeGoogleSignIn().signOut();
      } catch (_) {
        // Best-effort local provider signout; Firebase signOut below is authoritative.
      }
    }
    await _auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> resetPassword(String email) async {
    await sendPasswordResetEmail(email);
  }
}
