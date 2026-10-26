import 'dart:async';

import 'package:budget_tracker/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() => Api.requestTimeout = const Duration(seconds: 20));

  test('a server that never answers ends in a timeout, not a hang', () async {
    Api.requestTimeout = const Duration(milliseconds: 50);
    await http.runWithClient(() async {
      await expectLater(Api.me(), throwsA(isA<TimeoutException>()));
    },
        () => MockClient((_) async {
              await Future<void>.delayed(const Duration(milliseconds: 400));
              return http.Response('{"username": "x"}', 200);
            }));
  });

  test('a prompt answer is unaffected by the timeout', () async {
    Api.requestTimeout = const Duration(milliseconds: 500);
    await http.runWithClient(() async {
      expect((await Api.me())['username'], 'x');
    }, () => MockClient((_) async => http.Response('{"username": "x"}', 200)));
  });
}
