import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiabanwang/api.dart';

class MemoryApi extends Api {
  MemoryApi(http.Client client)
    : super(client: client, baseUrl: 'https://example.test');
  @override
  Future<void> saveToken(String value) async {
    token = value;
  }

  @override
  Future<void> logout() async {
    token = null;
  }
}

void main() {
  test(
    'API sends bearer token, encodes query and persists renewed sessions',
    () async {
      final api = MemoryApi(
        MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer old');
          expect(request.url.queryParameters['q'], '北京 107');
          return http.Response(
            jsonEncode({
              'data': [1],
            }),
            200,
            headers: {'x-session-token': 'renewed'},
          );
        }),
      )..token = 'old';
      expect(await api.data('/api/routes/search', query: {'q': '北京 107'}), [1]);
      expect(api.token, 'renewed');
    },
  );
  test('unauthorized clears session while rate limits preserve it and expose the server message', () async {
    var code = 429;
    final api = MemoryApi(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': '稍后重试'},
          }),
          code,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    )..token = 'old';
    var expired = false;
    api.onUnauthorized = () => expired = true;
    await expectLater(
      api.data('/api/me'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', '稍后重试')),
    );
    expect(api.token, 'old');
    expect(expired, false);
    code = 401;
    await expectLater(api.data('/api/me'), throwsA(isA<ApiException>()));
    expect(api.token, isNull);
    expect(expired, true);
  });
  test('204 deletion is successful without JSON body', () async {
    final api = MemoryApi(MockClient((_) async => http.Response('', 204)));
    expect(await api.request('/api/reminders/1', method: 'DELETE'), isNull);
  });
}
