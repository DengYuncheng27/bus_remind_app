import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';

class PhonePush {
  final Api api;
  JPushFlutterInterface? _sdk;
  void Function(int)? onOpen;
  PhonePush(this.api);
  String get deviceKey => 'device:${api.baseUrl}';
  Future<int?> get deviceId async =>
      int.tryParse(await api.storage.read(key: deviceKey) ?? '');
  bool get isWeb => false;
  String? get unavailableReason => !supported
      ? '请在 Android 或 iPhone 客户端使用手机通知'
      : const String.fromEnvironment('JPUSH_APP_KEY').isEmpty
      ? '原生手机推送尚未开通。可使用高级扩展接收到站提醒，或在浏览器打开下班王并开启网页通知。'
      : null;
  Future<void> test() async {
    final id = await deviceId;
    if (id == null) throw ApiException('请先连接手机通知');
    await api.data('/api/mobile-push/devices/$id/test', method: 'POST');
  }

  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  Future<int> connect() async {
    if (api.demo || !supported) {
      throw ApiException('请在 Android 或 iPhone 客户端开启手机通知');
    }
    const key = String.fromEnvironment('JPUSH_APP_KEY');
    if (key.isEmpty) throw ApiException('此版本尚未配置手机推送，请联系开发者');
    final status = await api.data('/api/mobile-push') as Json;
    if (status['enabled'] != true) throw ApiException('手机推送服务尚未开通');
    final permission = await Permission.notification.request();
    if (!permission.isGranted && !permission.isProvisional) {
      throw ApiException('请在系统设置中允许下班王发送通知');
    }
    if (_sdk == null) {
      _sdk = JPush.newJPush();
      _sdk!.setup(
        appKey: key,
        channel: 'default',
        production: const bool.fromEnvironment('JPUSH_PRODUCTION'),
        debug: false,
      );
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        _sdk!.applyPushAuthority();
      }
      _sdk!.addEventHandler(
        onOpenNotification: (event) async {
          handleOpen(event);
        },
      );
    }
    await _sdk!.resumePush();
    String registrationId = '';
    for (var i = 0; i < 12; i++) {
      registrationId = await _sdk!.getRegistrationID().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ApiException('手机通知连接超时，请稍后重试'),
      );
      if (registrationId.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (registrationId.isEmpty) throw ApiException('手机通知连接超时，请稍后重试');
    final data = await api.data(
      '/api/mobile-push/devices',
      method: 'POST',
      body: {
        'registrationId': registrationId,
        'platform': defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      },
    ) as Json;
    await api.storage.write(key: deviceKey, value: '${data['deviceId']}');
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final launch = await _sdk!.getLaunchAppNotification();
      if (launch.isNotEmpty) handleOpen(launch);
    }
    return data['deviceId'] as int;
  }

  int? _lastOpened;
  DateTime? _lastOpenedAt;
  void handleOpen(Map<dynamic, dynamic> event) {
    dynamic extra = event['extras'] ?? event['cn.jpush.android.EXTRA'];
    if (extra is String) {
      try {
        extra = jsonDecode(extra);
      } catch (_) {
        extra = null;
      }
    }
    final id = int.tryParse(
      '${extra is Map ? extra['reminderId'] : event['reminderId']}',
    );
    if (id == null || id <= 0) return;
    if (_lastOpened == id &&
        _lastOpenedAt != null &&
        DateTime.now().difference(_lastOpenedAt!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastOpened = id;
    _lastOpenedAt = DateTime.now();
    onOpen?.call(id);
  }

  Future<void> restore() async {
    if (api.demo || !supported) return;
    if (await deviceId != null) await connect();
  }

  Future<void> disconnect() async {
    if (api.demo) return;
    final id = await deviceId;
    if (id != null) {
      await api.request('/api/mobile-push/devices/$id', method: 'DELETE');
    }
    await _sdk?.stopPush();
    await api.storage.delete(key: deviceKey);
  }
}
