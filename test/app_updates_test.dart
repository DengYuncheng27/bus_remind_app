import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:xiabanwang/app_updates.dart';
import 'package:xiabanwang/screens/update_screen.dart';

class FakeUpdater implements ShorebirdUpdater {
  @override
  bool isAvailable = true;
  UpdateStatus status = UpdateStatus.upToDate;
  int downloads = 0;
  bool fail = false;
  Completer<void>? download;
  @override
  Future<Patch?> readCurrentPatch() async => const Patch(number: 2);
  @override
  Future<Patch?> readNextPatch() async => const Patch(number: 2);
  @override
  Future<UpdateStatus> checkForUpdate({UpdateTrack? track}) async {
    if (fail) throw Exception('offline');
    return status;
  }

  @override
  Future<void> update({UpdateTrack? track}) async {
    downloads++;
    await download?.future;
  }
}

Map<String, dynamic> manifest({int build = 10}) => {
  'version': '0.3.7',
  'versionCode': build,
  'tag': 'v0.3.7',
  'applicationId': 'space.su7.xiabanwang',
  'abi': 'arm64-v8a',
  'url':
      'https://github.com/$releaseRepository/releases/download/v0.3.7/$releaseAsset',
};

void main() {
  late FakeUpdater updater;
  AppUpdates create({int build = 9, bool offline = false}) => AppUpdates(
    updater: updater,
    readPackage: () async => PackageInfo(
      appName: '下班王',
      packageName: 'space.su7.xiabanwang',
      version: '0.3.6',
      buildNumber: '$build',
    ),
    readRelease: () async {
      if (offline) throw Exception('GitHub unreachable');
      return AndroidRelease.fromJson(manifest());
    },
  );
  setUp(() => updater = FakeUpdater());

  testWidgets('startup notice and screen coexist and notice can be dismissed', (
    tester,
  ) async {
    final updates = create();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            UpdateNotice(updates: updates, child: child!),
        home: UpdateScreen(updates: updates),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('稍后'), findsOneWidget);
    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();
    expect(find.text('稍后'), findsNothing);
    expect(find.text('下载新版 APK'), findsOneWidget);
  });

  testWidgets('screen offers APK and explains pending restart', (tester) async {
    updater.status = UpdateStatus.restartRequired;
    await tester.pumpWidget(MaterialApp(home: UpdateScreen(updates: create())));
    await tester.pumpAndSettle();
    expect(find.text('下载新版 APK'), findsOneWidget);
    expect(find.text('查看更新说明'), findsOneWidget);
    expect(find.text('小更新已准备好，完全关闭并重新打开应用后生效。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('network failure shows retry without claiming latest', (
    tester,
  ) async {
    updater.fail = true;
    await tester.pumpWidget(
      MaterialApp(home: UpdateScreen(updates: create(offline: true))),
    );
    await tester.pumpAndSettle();
    expect(find.text('重新检查'), findsOneWidget);
    expect(find.text('当前已是最新安装包版本。'), findsNothing);
    expect(find.text('暂时无法检查安装包更新，请稍后重试。'), findsOneWidget);
  });

  test('rejects another app, invalid build and untrusted download URLs', () {
    for (final entry in <String, Object>{
      'applicationId': 'other.app',
      'versionCode': '10',
      'tag': 'v0.3.8',
      'abi': 'x86_64',
      'version': '../bad',
      'url': 'https://example.com/app.apk',
    }.entries) {
      expect(
        () => AndroidRelease.fromJson({...manifest(), entry.key: entry.value}),
        throwsFormatException,
      );
    }
  });

  test(
    'uses installed build number and does not offer equal or older packages',
    () async {
      for (final build in [9, 10, 11]) {
        final updates = create(build: build);
        await updates.check();
        expect(updates.hasNewPackage, build < 10);
        expect(updates.versionLabel, contains('($build)'));
        updates.dispose();
      }
    },
  );

  test('GitHub failure does not prevent a patch from downloading', () async {
    updater.status = UpdateStatus.outdated;
    final updates = create(offline: true);
    await updates.check();
    expect(updates.packageError, isNotNull);
    expect(updates.patchError, isNull);
    expect(updater.downloads, 1);
    expect(updates.restartRequired, isTrue);
    expect(updates.checking, isFalse);
  });

  test('patch failure does not hide a new full package', () async {
    updater.fail = true;
    final updates = create();
    await updates.check();
    expect(updates.hasNewPackage, isTrue);
    expect(updates.patchError, isNotNull);
    expect(updates.checking, isFalse);
  });

  test('coalesces checks while a download is running', () async {
    updater.status = UpdateStatus.outdated;
    updater.download = Completer<void>();
    final updates = create();
    final first = updates.check();
    final second = updates.check();
    await Future<void>.delayed(Duration.zero);
    expect(updater.downloads, 1);
    expect(updates.hasNewPackage, isTrue);
    updater.download!.complete();
    await Future.wait([first, second]);
    expect(updates.restartRequired, isTrue);
  });

  test('pending patch needs restart without another download', () async {
    updater.status = UpdateStatus.restartRequired;
    final updates = create();
    await updates.check();
    expect(updates.restartRequired, isTrue);
    expect(updater.downloads, 0);
  });

  test(
    'ordinary APK can check packages without the Shorebird engine',
    () async {
      updater.isAvailable = false;
      final updates = create();
      await updates.check();
      expect(updates.hasNewPackage, isTrue);
      expect(updates.patchAvailable, isFalse);
      expect(updater.downloads, 0);
    },
  );
}
