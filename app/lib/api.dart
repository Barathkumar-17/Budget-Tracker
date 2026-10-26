import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

const String _configured = String.fromEnvironment('API_URL');

/// Where the API lives. Set with --dart-define=API_URL=http://<host>:8000.
/// `same-origin` means the page and the API share one server (the Docker image).
/// Defaults: 10.0.2.2 (the host as seen from the Android emulator), and
/// 127.0.0.1:8000 for web builds.
final String baseUrl = switch (_configured) {
  'same-origin' => '',
  '' => kIsWeb ? 'http://127.0.0.1:8000' : 'http://10.0.2.2:8000',
  final url => url,
};

/// A failed API call; [toString] is the message shown to the user.
class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

String _errorMessage(http.Response r) {
  try {
    final detail = (jsonDecode(r.body) as Map)['detail'];
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      return detail.map((e) {
        final loc = e['loc'] as List;
        return '${loc.last}: ${e['msg']}';
      }).join('; ');
    }
  } catch (_) {}
  return switch (r.statusCode) {
    413 => 'That is too long to send. Try shorter text.',
    403 => 'The server refused this request. Try different text.',
    _ => 'Server error ${r.statusCode}',
  };
}

class Api {
  /// Login token sent with every request. Set by the auth state.
  static String? token;

  /// How long one request may take before it counts as "server not answering".
  static Duration requestTimeout = const Duration(seconds: 20);

  /// Called when the server rejects the token (expired or revoked session).
  static void Function()? onUnauthorized;

  static Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body, bool auth = true}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = {
      'Content-Type': 'application/json',
      if (auth && token != null) 'Authorization': 'Bearer $token',
    };
    final payload = body == null ? null : jsonEncode(body);
    final Future<http.Response> call = switch (method) {
      'POST' => http.post(uri, headers: headers, body: payload),
      'PUT' => http.put(uri, headers: headers, body: payload),
      'DELETE' => http.delete(uri, headers: headers),
      _ => http.get(uri, headers: headers),
    };
    // A phone that cannot reach the server may wait for minutes without an
    // error; give up after a while so the app can say so (and retry).
    final http.Response r = await call.timeout(requestTimeout);
    if (r.statusCode >= 400) {
      // A 401 on a logged-in call means the session ended. (A 401 from the
      // login call itself just means a wrong password, so it is not routed here.)
      if (r.statusCode == 401 && auth) onUnauthorized?.call();
      throw ApiException(_errorMessage(r), r.statusCode);
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  // ---- accounts ----
  static Future<Map<String, dynamic>> register(
          String username, String password) async =>
      Map<String, dynamic>.from(await _send('POST', '/auth/register',
          body: {'username': username, 'password': password}, auth: false));

  static Future<Map<String, dynamic>> login(
          String username, String password) async =>
      Map<String, dynamic>.from(await _send('POST', '/auth/login',
          body: {'username': username, 'password': password}, auth: false));

  static Future<void> logout() => _send('POST', '/auth/logout');

  static Future<Map<String, dynamic>> me() async =>
      Map<String, dynamic>.from(await _send('GET', '/auth/me'));

  // ---- data ----
  static Future<Map<String, dynamic>> dashboard(String month) async =>
      Map<String, dynamic>.from(
          await _send('GET', '/dashboard', query: {'month': month}));

  static Future<Map<String, dynamic>> account() async =>
      Map<String, dynamic>.from(await _send('GET', '/account'));

  static Future<void> setAccount(double opening, double threshold) =>
      _send('PUT', '/account', body: {
        'opening_balance': opening,
        'low_balance_threshold': threshold,
      });

  static Future<List<dynamic>> expenses(String month) async =>
      await _send('GET', '/expenses', query: {'month': month}) as List<dynamic>;

  /// Returns the response so callers can show overspend / low-balance alerts.
  static Future<Map<String, dynamic>> addExpense(
          double amount, String date, String category, String note) async =>
      Map<String, dynamic>.from(await _send('POST', '/expenses', body: {
        'amount': amount,
        'date': date,
        'category': category,
        'note': note,
      }));

  /// Same response shape as [addExpense] (editing can also trigger an alert).
  static Future<Map<String, dynamic>> updateExpense(int id, double amount,
          String date, String category, String note) async =>
      Map<String, dynamic>.from(await _send('PUT', '/expenses/$id', body: {
        'amount': amount,
        'date': date,
        'category': category,
        'note': note,
      }));

  static Future<void> deleteExpense(int id) => _send('DELETE', '/expenses/$id');

  static Future<List<dynamic>> budgets(String month) async =>
      await _send('GET', '/budgets', query: {'month': month}) as List<dynamic>;

  static Future<void> setBudget(String category, String month, double cap) =>
      _send('PUT', '/budgets',
          body: {'category': category, 'month': month, 'cap': cap});

  static Future<List<dynamic>> recurring() async =>
      await _send('GET', '/recurring') as List<dynamic>;

  static Future<void> addRecurring(
          double amount, String category, String note, int day) =>
      _send('POST', '/recurring', body: {
        'amount': amount,
        'category': category,
        'note': note,
        'day_of_month': day,
      });

  static Future<void> deleteRecurring(int id) =>
      _send('DELETE', '/recurring/$id');

  static Future<int> applyRecurring(String month) async {
    final r = await _send('POST', '/recurring/apply', query: {'month': month});
    return (r['created'] as num).toInt();
  }

  static Future<List<dynamic>> goals() async =>
      await _send('GET', '/goals') as List<dynamic>;

  static Future<void> addGoal(String name, double target) =>
      _send('POST', '/goals', body: {'name': name, 'target': target});

  static Future<void> contribute(int id, double amount) =>
      _send('POST', '/goals/$id/contribute', body: {'amount': amount});

  static Future<void> deleteGoal(int id) => _send('DELETE', '/goals/$id');
}
