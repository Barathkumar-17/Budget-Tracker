import 'dart:convert';
import 'package:http/http.dart' as http;

/// Override with: flutter run --dart-define=API_URL=http://<host>:8000
/// 10.0.2.2 is the host machine as seen from the Android emulator.
const String baseUrl =
    String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');

class Api {
  static Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final headers = {'Content-Type': 'application/json'};
    final payload = body == null ? null : jsonEncode(body);
    final http.Response r;
    switch (method) {
      case 'POST':
        r = await http.post(uri, headers: headers, body: payload);
        break;
      case 'PUT':
        r = await http.put(uri, headers: headers, body: payload);
        break;
      case 'DELETE':
        r = await http.delete(uri);
        break;
      default:
        r = await http.get(uri);
    }
    if (r.statusCode >= 400) {
      throw Exception('Server error ${r.statusCode}: ${r.body}');
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

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

  static Future<void> deleteRecurring(int id) => _send('DELETE', '/recurring/$id');

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
