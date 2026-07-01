import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  Map<String, dynamic>? _user;

  bool get isAuthenticated => _isAuthenticated;
  Map<String, dynamic>? get user => _user;

  Future<void> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token != null) {
      try {
        final response = await ApiClient.get('/me');
        if (response.statusCode == 200) {
          _user = jsonDecode(response.body)['user'];
          _isAuthenticated = true;
        } else {
          await prefs.remove('auth_token');
          _isAuthenticated = false;
        }
      } catch (e) {
        // If offline, assume authenticated if token exists for MVP offline mode
        _isAuthenticated = true; 
      }
    }
    notifyListeners();
  }

  Future<bool> login(String loginId, String password, {bool isPin = false}) async {
    final data = isPin 
      ? {'pin': loginId} 
      : {'email': loginId, 'password': password};
      
    try {
      final response = await ApiClient.post('/login', data);
      
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final token = body['token'];
        _user = body['user'];
        _isAuthenticated = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint("Login failed: $e");
    }
    return false;
  }
  
  Future<void> logout() async {
    try {
      await ApiClient.post('/logout', {});
    } catch (e) {
      // Ignore network errors on logout
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _isAuthenticated = false;
    _user = null;
    notifyListeners();
  }
}
