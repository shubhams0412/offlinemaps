import 'package:flutter/material.dart';

class AuthViewModel extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  String? _token;
  String? get token => _token;

  Future<void> login(String email, String password) async {
    // Mock API Call
    await Future.delayed(const Duration(seconds: 1));
    _isAuthenticated = true;
    _token = "mock_jwt_token_12345";
    notifyListeners();
  }

  void logout() {
    _isAuthenticated = false;
    _token = null;
    notifyListeners();
  }
}
