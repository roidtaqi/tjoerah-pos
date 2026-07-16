import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_client.dart';

const _authTokenKey = 'auth_token';
const _authUserKey = 'auth_user';
const _unsetUser = Object();

enum AuthLoginFailure {
  invalidCredentials,
  connection,
  serviceUnavailable,
  unexpectedResponse,
}

class AuthLoginResult {
  const AuthLoginResult.success() : failure = null;

  const AuthLoginResult.failure(this.failure);

  final AuthLoginFailure? failure;

  bool get isSuccess => failure == null;
}

class AuthState {
  final bool isAuthenticated;
  final Map<String, dynamic>? user;

  AuthState({this.isAuthenticated = false, this.user});

  AuthState copyWith({bool? isAuthenticated, Object? user = _unsetUser}) {
    return AuthState(
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: identical(user, _unsetUser)
          ? this.user
          : user as Map<String, dynamic>?,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState();
  }

  Future<void> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_authTokenKey);

    if (token == null) {
      state = AuthState();
      return;
    }

    final cachedUser = _decodeCachedUser(prefs.getString(_authUserKey));
    if (cachedUser != null) {
      state = AuthState(isAuthenticated: true, user: cachedUser);
    }

    try {
      final response = await ApiClient.get('/me');
      if (response.statusCode == 200) {
        final user = Map<String, dynamic>.from(
          jsonDecode(response.body)['user'] as Map,
        );
        await _saveUser(prefs, user);
        state = AuthState(isAuthenticated: true, user: user);
      } else if (response.statusCode == 401) {
        await Future.wait([
          prefs.remove(_authTokenKey),
          prefs.remove(_authUserKey),
        ]);
        state = AuthState();
      }
    } catch (_) {
      // A valid cached session keeps every role usable while offline.
      state = cachedUser == null
          ? AuthState()
          : AuthState(isAuthenticated: true, user: cachedUser);
    }
  }

  Future<AuthLoginResult> login(
    String loginId,
    String password, {
    bool isPin = false,
  }) async {
    final data = isPin
        ? {'pin': loginId}
        : {'email': loginId, 'password': password};

    try {
      final response = await ApiClient.post(
        isPin ? '/auth/pin/login' : '/auth/login',
        data,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is! Map<String, dynamic>) {
          return const AuthLoginResult.failure(
            AuthLoginFailure.unexpectedResponse,
          );
        }
        final token = body['token'];
        final rawUser = body['user'];
        if (token == null || rawUser is! Map) {
          return const AuthLoginResult.failure(
            AuthLoginFailure.unexpectedResponse,
          );
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_authTokenKey, token.toString());

        final user = Map<String, dynamic>.from(rawUser);
        await _saveUser(prefs, user);

        state = AuthState(user: user, isAuthenticated: true);
        return const AuthLoginResult.success();
      }

      if (response.statusCode == 401 || response.statusCode == 422) {
        return const AuthLoginResult.failure(
          AuthLoginFailure.invalidCredentials,
        );
      }
      if (response.statusCode >= 500) {
        return const AuthLoginResult.failure(
          AuthLoginFailure.serviceUnavailable,
        );
      }
      return const AuthLoginResult.failure(AuthLoginFailure.unexpectedResponse);
    } on TimeoutException catch (error) {
      debugPrint('Login timed out: $error');
      return const AuthLoginResult.failure(AuthLoginFailure.connection);
    } on FormatException catch (error) {
      debugPrint('Login response was invalid: $error');
      return const AuthLoginResult.failure(AuthLoginFailure.unexpectedResponse);
    } catch (error) {
      debugPrint('Login request failed: $error');
      return const AuthLoginResult.failure(AuthLoginFailure.connection);
    }
  }

  Future<void> logout() async {
    try {
      await ApiClient.post('/logout', {});
    } catch (e) {
      // Ignore network errors on logout
    }
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_authTokenKey),
      prefs.remove(_authUserKey),
    ]);
    state = AuthState();
  }

  Map<String, dynamic>? _decodeCachedUser(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(value) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveUser(SharedPreferences prefs, Map<String, dynamic> user) {
    return prefs.setString(_authUserKey, jsonEncode(user));
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
