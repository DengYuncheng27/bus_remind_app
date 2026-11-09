import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiabanwang/demo.dart';
import 'package:xiabanwang/main.dart';
import 'package:xiabanwang/screens/auth_screen.dart';
import 'package:xiabanwang/screens/password_screen.dart';

class RestoringApi extends DemoApi {
  final ready = Completer<void>();
  RestoringApi() : super(latency: Duration.zero);
  @override
  Future<void> restore() => ready.future;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final platformCalls = <String>[];
  setUp(() {
    platformCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => platformCalls.add(call.method),
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  testWidgets('installed app cannot exit during startup or on login', (
    tester,
  ) async {
    final api = RestoringApi();
    await tester.pumpWidget(CommuteApp(api: api, preventRootExit: true));
    await binding.handlePopRoute();
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    api.ready.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AuthScreen), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    expect(find.byType(AuthScreen), findsOneWidget);
    expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'installed app pops subpages once and keeps the selected root tab',
    (tester) async {
      await tester.pumpWidget(
        CommuteApp(api: DemoApi(latency: Duration.zero), preventRootExit: true),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tab-profile')));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('我的账号'));
      final navigator = Navigator.of(context);
      for (final gesture in [false, true]) {
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  PasswordScreen(api: DemoApi(latency: Duration.zero)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (gesture) {
          await tester.dragFrom(const Offset(5, 250), const Offset(700, 0));
        } else {
          await binding.handlePopRoute();
        }
        await tester.pumpAndSettle();
        expect(find.byType(PasswordScreen), findsNothing);
        expect(find.text('我的账号'), findsOneWidget);
        expect(navigator.canPop(), isFalse);
      }
      for (var i = 0; i < 3; i++) {
        await binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(find.text('我的账号'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({TargetPlatform.iOS}),
  );

  testWidgets('normal browser and native app retain platform back behavior', (
    tester,
  ) async {
    await tester.pumpWidget(CommuteApp(api: DemoApi(latency: Duration.zero)));
    await tester.pumpAndSettle();
    await binding.handlePopRoute();
    expect(platformCalls, contains('SystemNavigator.pop'));
    await tester.pumpWidget(const SizedBox());
  });
}
