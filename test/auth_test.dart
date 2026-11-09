import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/api.dart';
import 'package:xiabanwang/screens/auth_screen.dart';

class AuthApi extends Api {
  final calls = <(String, Json?)>[];
  bool available = true;
  String? existingEmail;
  ApiException? mailFailure;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? body,
    Map<String, String>? query,
  }) async {
    calls.add((path, body));
    if (path == '/api/auth/registration') {
      return {
        'data': {'mode': 'public', 'emailAvailable': available},
      };
    }
    if (path.endsWith('email-code') || path.endsWith('/code')) {
      if (mailFailure != null) throw mailFailure!;
      if (body?['purpose'] == 'register' && body?['email'] == existingEmail) {
        throw ApiException('该邮箱已注册，请登录', 409);
      }
      return {
        'data': {'challengeId': 'test-challenge', 'retryAfter': 60},
      };
    }
    if (path.endsWith('/register') || path.endsWith('/login')) {
      return {'token': 'test-token'};
    }
    return {
      'data': {'verified': true},
    };
  }

  @override
  Future<void> saveToken(String value) async {
    token = value;
  }
}

void main() {
  Future<void> setup(
    WidgetTester tester,
    AuthApi api, {
    String? verificationEmail,
    VoidCallback? success,
  }) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          api: api,
          verificationEmail: verificationEmail,
          onSuccess: success ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> credentials(WidgetTester tester) async {
    await enter(tester, 'auth-code', '123456');
    await enter(tester, 'auth-password', 'test-password');
    await enter(tester, 'auth-confirm', 'test-password');
  }

  testWidgets(
    'registration requires matching confirmation and submits email proof',
    (tester) async {
      final api = AuthApi();
      var successes = 0;
      await setup(tester, api, success: () => successes++);
      await tap(tester, find.text('还没有账号？创建一个'));
      await enter(tester, 'auth-email', 'New@Example.com');
      await tap(tester, find.byKey(const ValueKey('send-code')));
      expect(api.calls.last.$2?['purpose'], 'register');
      expect(find.textContaining('注册验证码已提交邮件服务'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('send-code')))
            .onPressed,
        isNull,
      );
      await credentials(tester);
      await enter(tester, 'auth-confirm', 'different-password');
      await tap(tester, find.byKey(const ValueKey('auth-submit')));
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(api.calls.where((c) => c.$1.endsWith('/register')), isEmpty);
      await enter(tester, 'auth-confirm', 'test-password');
      await tap(tester, find.byKey(const ValueKey('auth-submit')));
      expect(api.calls.last.$2?['challengeId'], 'test-challenge');
      expect(api.calls.last.$2?['code'], '123456');
      expect(api.token, 'test-token');
      expect(successes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'registration fields follow email, password, confirmation, then code',
    (tester) async {
      await setup(tester, AuthApi());
      await tap(tester, find.text('还没有账号？创建一个'));
      final fields = [
        'auth-email',
        'auth-password',
        'auth-confirm',
        'auth-code',
      ];
      for (var i = 0; i < fields.length - 1; i++) {
        expect(
          tester.getTopLeft(find.byKey(ValueKey(fields[i]))).dy,
          lessThan(tester.getTopLeft(find.byKey(ValueKey(fields[i + 1]))).dy),
        );
      }
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'existing email shows a clear error without a countdown and allows correcting the address',
    (tester) async {
      final api = AuthApi()..existingEmail = 'existing@qq.com';
      await setup(tester, api);
      await tap(tester, find.text('还没有账号？创建一个'));
      await enter(tester, 'auth-email', 'Existing@qq.com');
      await tap(tester, find.byKey(const ValueKey('send-code')));
      expect(find.text('该邮箱已注册，请登录'), findsOneWidget);
      expect(find.textContaining('秒后重新发送'), findsNothing);
      expect(find.textContaining('注册验证码已提交邮件服务'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('send-code')))
            .onPressed,
        isNotNull,
      );
      await enter(tester, 'auth-email', 'new@qq.com');
      expect(find.text('该邮箱已注册，请登录'), findsNothing);
      await tap(tester, find.byKey(const ValueKey('send-code')));
      expect(find.textContaining('秒后重新发送'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'invalid mailbox syntax is blocked before the send-code API call',
    (tester) async {
      final api = AuthApi();
      await setup(tester, api);
      await tap(tester, find.text('还没有账号？创建一个'));
      for (final email in ['a..b@qq.com', 'a@qq..com', 'a@q_q.com']) {
        await enter(tester, 'auth-email', email);
        await tap(tester, find.byKey(const ValueKey('send-code')));
        expect(find.text('请输入有效的邮箱地址'), findsOneWidget);
      }
      expect(api.calls.where((c) => c.$1.endsWith('email-code')), isEmpty);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('send-code')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'changing recipient clears proof and cannot reuse old email code',
    (tester) async {
      final api = AuthApi();
      await setup(tester, api);
      await tap(tester, find.text('还没有账号？创建一个'));
      await enter(tester, 'auth-email', 'first@example.com');
      await tap(tester, find.byKey(const ValueKey('send-code')));
      await enter(tester, 'auth-email', 'second@example.com');
      await credentials(tester);
      await tap(tester, find.byKey(const ValueKey('auth-submit')));
      expect(find.text('请先为当前邮箱获取验证码'), findsOneWidget);
      expect(api.calls.where((c) => c.$1.endsWith('/register')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('password recovery returns to login without creating a session', (
    tester,
  ) async {
    final api = AuthApi();
    await setup(tester, api);
    await tap(tester, find.text('忘记密码？'));
    expect(find.textContaining('无需先登录，旧账号也可找回'), findsOneWidget);
    await enter(tester, 'auth-email', 'verified@example.com');
    await tap(tester, find.byKey(const ValueKey('send-code')));
    expect(api.calls.last.$2?['purpose'], 'reset');
    await credentials(tester);
    await tap(tester, find.byKey(const ValueKey('auth-submit')));
    expect(api.calls.last.$1, '/api/auth/reset-password');
    expect(api.calls.last.$2?['newPassword'], 'test-password');
    expect(api.token, isNull);
    expect(find.text('密码已重置，请使用新密码登录。'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('auth-email')))
          .controller!
          .text,
      'verified@example.com',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'failed recovery mail shows its error without a success countdown',
    (tester) async {
      final api = AuthApi()
        ..mailFailure = ApiException('验证码邮件发送失败，请稍后重新获取', 502);
      await setup(tester, api);
      await tap(tester, find.text('忘记密码？'));
      await enter(tester, 'auth-email', 'legacy@qq.com');
      await tap(tester, find.byKey(const ValueKey('send-code')));
      expect(find.text('验证码邮件发送失败，请稍后重新获取'), findsOneWidget);
      expect(find.textContaining('秒后重新发送'), findsNothing);
      expect(find.textContaining('重置验证码已提交至'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('send-code')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('legacy email verification only calls authenticated endpoints', (
    tester,
  ) async {
    final api = AuthApi();
    var done = false;
    await setup(
      tester,
      api,
      verificationEmail: 'old@example.com',
      success: () => done = true,
    );
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey('auth-email')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    await tap(tester, find.byKey(const ValueKey('send-code')));
    expect(api.calls.last, ('/api/auth/email-verification/code', null));
    await enter(tester, 'auth-code', '123456');
    await tap(tester, find.byKey(const ValueKey('auth-submit')));
    expect(api.calls.last.$1, '/api/auth/email-verification');
    expect(done, isTrue);
    expect(api.calls.last.$2?.containsKey('email'), isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'unconfigured mail disables registration but leaves login available',
    (tester) async {
      final api = AuthApi()..available = false;
      await setup(tester, api);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('auth-submit')))
            .onPressed,
        isNotNull,
      );
      await tap(tester, find.text('还没有账号？创建一个'));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('auth-submit')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('send-code')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
