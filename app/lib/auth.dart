import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'common.dart' show WakePolicy, isServerAsleep;

enum AuthStatus { loading, loggedOut, loggedIn, unreachable }

/// Who is logged in. Keeps the session token on the device so a reload or an
/// app restart does not ask for the password again.
class AuthState extends ChangeNotifier {
  static const _tokenKey = 'session_token';

  AuthStatus status = AuthStatus.loading;
  String? username;

  /// Shown on the login screen when the session ended without the user asking.
  String? notice;

  /// True while a sleeping server is being retried at start-up.
  bool waking = false;

  AuthState() {
    Api.onUnauthorized = _sessionEnded;
  }

  /// Looks for a saved session and checks it with the server.
  Future<void> restore() async {
    status = AuthStatus.loading;
    notifyListeners();
    final saved = await _readToken();
    if (saved == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }
    Api.token = saved;
    for (var attempt = 0;; attempt++) {
      try {
        username = (await Api.me())['username'] as String;
        status = AuthStatus.loggedIn;
      } on ApiException catch (e) {
        // A 401 already signed us out through Api.onUnauthorized.
        if (e.status != 401) {
          if (isServerAsleep(e) && attempt < WakePolicy.delays.length) {
            waking = true;
            notifyListeners();
            await Future<void>.delayed(WakePolicy.delays[attempt]);
            continue;
          }
          status = AuthStatus.unreachable;
        }
      } catch (e) {
        if (isServerAsleep(e) && attempt < WakePolicy.delays.length) {
          waking = true;
          notifyListeners();
          await Future<void>.delayed(WakePolicy.delays[attempt]);
          continue;
        }
        status = AuthStatus.unreachable;
      }
      break;
    }
    waking = false;
    notifyListeners();
  }

  Future<void> login(String name, String password) async =>
      _start(await Api.login(name, password));

  Future<void> register(String name, String password) async =>
      _start(await Api.register(name, password));

  Future<void> logout() async {
    try {
      await Api.logout();
    } catch (_) {
      // Signing out locally is what matters; the token expires on its own.
    }
    await _clear();
    notice = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> _start(Map<String, dynamic> session) async {
    Api.token = session['token'] as String;
    username = session['username'] as String;
    notice = null;
    status = AuthStatus.loggedIn;
    await _writeToken(Api.token);
    notifyListeners();
  }

  void _sessionEnded() {
    if (status == AuthStatus.loggedOut) return;
    _clear();
    notice = 'Your session ended. Please log in again.';
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  Future<void> _clear() async {
    Api.token = null;
    username = null;
    await _writeToken(null);
  }

  // Storage can be unavailable (private browsing, tests); the session then lasts until the tab closes.
  Future<String?> _readToken() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_tokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToken(String? token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      token == null
          ? await prefs.remove(_tokenKey)
          : await prefs.setString(_tokenKey, token);
    } catch (_) {}
  }
}

class AuthScope extends InheritedNotifier<AuthState> {
  const AuthScope({super.key, required AuthState state, required super.child})
      : super(notifier: state);

  /// Watches the state: the caller rebuilds when the login status changes.
  static AuthState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()!.notifier!;

  /// Reads the state without subscribing (for use in callbacks).
  static AuthState read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AuthScope>()!.widget
              as AuthScope)
          .notifier!;
}
