import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService;
  User? _currentUser;
  bool _isLoading = false;
  StreamSubscription<User?>? _authSubscription;
  String? _lastBackendSyncUid;
  String _backendRole = 'guest';

  AuthProvider({required AuthService authService})
      : _authService = authService {
    _authSubscription = _authService.authStateChanges.listen((user) {
      _currentUser = user;
      _syncBackendIfNeeded(user);
      notifyListeners();
    });
  }

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String get backendRole => _backendRole;

  bool get isAdmin {
    final role = _backendRole.toLowerCase();
    return role == 'admin' || role == 'admine';
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    _currentUser = _authService.currentUser;
    _syncBackendIfNeeded(_currentUser);
    await _refreshBackendRole();
    _isLoading = false;
    notifyListeners();
  }

  void _syncBackendIfNeeded(User? user) {
    if (user == null) {
      _lastBackendSyncUid = null;
      _backendRole = 'guest';
      return;
    }
    if (_lastBackendSyncUid == user.uid) return;
    _lastBackendSyncUid = user.uid;
    _authService.ensureBackendRegistration().then((_) {
      _refreshBackendRole();
    }).catchError((_) {
      _lastBackendSyncUid = null;
    });
  }

  Future<void> _refreshBackendRole() async {
    final user = _currentUser;
    if (user == null) {
      _backendRole = 'guest';
      return;
    }
    final previousRole = _backendRole;
    try {
      final profile = await _authService.fetchMyProfile();
      final role = (profile['role'] ?? 'guest').toString().trim().toLowerCase();
      _backendRole = role.isEmpty ? 'guest' : role;
    } catch (_) {
      // Keep previous resolved role on transient backend/network failures.
      _backendRole = previousRole.trim().isEmpty ? 'guest' : previousRole;
    }
    notifyListeners();
  }

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signInWithEmailAndPassword(email, password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createUserWithEmailAndPassword(
    String email,
    String password,
    String displayName,
  ) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.createUserWithEmailAndPassword(
        email,
        password,
        displayName: displayName,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signInWithGoogle();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _authService.signOut();
      _backendRole = 'guest';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetPassword(String email) async {
    await _authService.resetPassword(email);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
