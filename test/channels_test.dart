import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/channels.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/screens/extensions_screen.dart';
import 'package:xiabanwang/screens/password_screen.dart';

class ChannelApi extends DemoApi {
  String? lastPath, lastMethod;
  Json? lastBody;
  ChannelApi() : super(latency: Duration.zero);
  @override
  Future<void> saveToken(String value) async {
    token = value;
  }

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    if (method != 'GET') {
      lastPath = path;
      lastMethod = method;
      lastBody = body;
      return {
        'data': {'id': 5},
        'token': 'renewed',
      };
    }
    return super.request(path, method: method, body: body, query: query);
  }
}

void main() {
  test('robot URLs normalize tokens and reject lookalike hosts', () {
    expect(
      channelConfig('dingtalk', {
        'accessToken':
            'https://oapi.dingtalk.com/robot/send?access_token=token123',
      }, editing: false),
      {'accessToken': 'token123'},
    );
    expect(
      channelConfig('wecom', {
        'key': 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=key123',
      }, editing: false),
      {'key': 'key123'},
    );
    expect(
      () => channelConfig('dingtalk', {
        'accessToken': 'https://oapi.dingtalk.com.evil.test/?access_token=x',
      }, editing: false),
      throwsA(isA<ApiException>()),
    );
    expect(
      channelConfig('telegram', {
        'botToken': 'abc',
        'chatId': '-123',
      }, editing: false)['chatId'],
      -123,
    );
    expect(
      () => channelConfig('telegram', {
        'botToken': 'abc',
        'chatId': '1.2',
      }, editing: false),
      throwsA(isA<ApiException>()),
    );
  });
  test(
    'editing omits blank credentials to preserve encrypted existing fields',
    () {
      expect(
        channelConfig('dingtalk', {
          'accessToken': '',
          'secret': '',
        }, editing: true),
        isEmpty,
      );
      expect(
        channelConfig('dingtalk', {
          'accessToken': 'new',
          'secret': '',
        }, editing: true),
        {'accessToken': 'new'},
      );
    },
  );
  testWidgets('renaming a channel preserves credentials and template', (
    tester,
  ) async {
    final api = ChannelApi();
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelEditor(
          api: api,
          channel: {
            'id': 5,
            'type': 'dingtalk',
            'label': '旧群',
            'template': {'title': '标题', 'body': '正文', 'customized': true},
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '新群');
    await tester.tap(find.text('保存扩展'));
    await tester.pumpAndSettle();
    expect(api.lastMethod, 'PATCH');
    expect(api.lastPath, '/api/channels/5');
    expect(api.lastBody, {'label': '新群'});
  });
  testWidgets('password form uses the existing change-password contract', (
    tester,
  ) async {
    final api = ChannelApi();
    await tester.pumpWidget(MaterialApp(home: PasswordScreen(api: api)));
    await tester.enterText(find.byType(TextField).at(0), 'old-password');
    await tester.enterText(find.byType(TextField).at(1), 'new-password');
    await tester.enterText(find.byType(TextField).at(2), 'new-password');
    await tester.tap(find.text('更新密码'));
    await tester.pumpAndSettle();
    expect(api.lastPath, '/api/auth/change-password');
    expect(api.token, 'renewed');
  });
}
