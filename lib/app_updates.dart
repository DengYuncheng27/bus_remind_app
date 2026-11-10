import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

const releaseRepository = 'DengYuncheng27/bus_remind_app';
const releaseAsset = 'xiabanwang-android-arm64.apk';
final releaseManifestUrl = Uri.parse(
  'https://github.com/$releaseRepository/releases/latest/download/android-release.json',
);

bool get supportsAppUpdates =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class AndroidRelease {
  final String version;
  final int buildNumber;
  final Uri downloadUrl;
  final Uri notesUrl;
  const AndroidRelease(
    this.version,
    this.buildNumber,
    this.downloadUrl,
    this.notesUrl,
  );

  factory AndroidRelease.fromJson(Object? data) {
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid release manifest');
    }
    final version = data['version'];
    final build = data['versionCode'];
    if (version is! String ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        build is! int ||
        build <= 0 ||
        data['tag'] != 'v$version' ||
        data['applicationId'] != 'space.su7.xiabanwang' ||
        data['abi'] != 'arm64-v8a') {
      throw const FormatException('Invalid Android release');
    }
    final expected =
        'https://github.com/$releaseRepository/releases/download/v$version/$releaseAsset';
    if (data['url'] != expected) {
      throw const FormatException('Unexpected APK download source');
    }
    return AndroidRelease(
      version,
      build,
      Uri.parse(expected),
      Uri.parse('https://github.com/$releaseRepository/releases/tag/v$version'),
    );
  }
}

/// Full packages and patches are independent: GitHub failure must not stop OTA.
class AppUpdates extends ChangeNotifier {
  static final instance = AppUpdates();

  AppUpdates({
    Future<PackageInfo> Function()? readPackage,
    Future<AndroidRelease> Function()? readRelease,
    this.updater,
  }) : _readPackage = readPackage ?? PackageInfo.fromPlatform,
       _readRelease = readRelease ?? fetchRelease;

  final Future<PackageInfo> Function() _readPackage;
  final Future<AndroidRelease> Function() _readRelease;
  ShorebirdUpdater? updater;
  PackageInfo? package;
  AndroidRelease? latest;
  int? patchNumber;
  bool checking = false;
  bool downloadingPatch = false;
  bool restartRequired = false;
  bool patchAvailable = false;
  String? packageError;
  String? patchError;
  Future<void>? _pending;

  bool get hasNewPackage =>
      package != null &&
      latest != null &&
      latest!.buildNumber > (int.tryParse(package!.buildNumber) ?? 0);
  String get versionLabel => package == null
      ? '下班王'
      : '下班王 ${package!.version} (${package!.buildNumber})${patchNumber == null ? '' : ' · 补丁 $patchNumber'}';

  static Future<AndroidRelease> fetchRelease() async {
    final client = http.Client();
    try {
      final response = await client
          .get(releaseManifestUrl)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        throw const FormatException('Release check failed');
      }
      return AndroidRelease.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)),
      );
    } finally {
      client.close();
    }
  }

  Future<void> check() =>
      _pending ??= _check().whenComplete(() => _pending = null);

  Future<void> _check() async {
    checking = true;
    packageError = null;
    patchError = null;
    notifyListeners();
    try {
      await Future.wait([_checkPackage(), _checkPatch()]);
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  Future<void> _checkPackage() async {
    try {
      package ??= await _readPackage();
      latest = await _readRelease();
    } catch (_) {
      packageError = '暂时无法检查安装包更新，请稍后重试。';
    }
    notifyListeners();
  }

  Future<void> _checkPatch() async {
    try {
      final updater = this.updater ??= ShorebirdUpdater();
      patchAvailable = updater.isAvailable;
      if (!patchAvailable) return;
      patchNumber = (await updater.readCurrentPatch())?.number;
      final status = await updater.checkForUpdate();
      restartRequired = status == UpdateStatus.restartRequired;
      if (status == UpdateStatus.outdated) {
        downloadingPatch = true;
        notifyListeners();
        await updater.update();
        restartRequired = true;
      }
    } catch (_) {
      patchError = '小更新暂时未完成，下次打开应用或点击检查更新时重试。';
    } finally {
      downloadingPatch = false;
      notifyListeners();
    }
  }
}
