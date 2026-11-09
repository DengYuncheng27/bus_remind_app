import 'package:flutter/material.dart';

import '../api.dart';
import '../palette.dart';
import '../ui.dart';

import 'package:permission_handler/permission_handler.dart';

import '../push.dart';

class SettingsScreen extends StatefulWidget {
  final Api api;
  final PhonePush push;
  final VoidCallback onLogout;
  final bool embedded;
  final Json? profile;
  const SettingsScreen({
    super.key,
    required this.api,
    required this.push,
    required this.onLogout,
    this.embedded = false,
    this.profile,
  });
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool busy = false;
  String? message;
  int? deviceId;
  @override
  void initState() {
    super.initState();
    readDevice();
  }

  Future<void> readDevice() async {
    if (widget.api.demo || !widget.push.supported) return;
    try {
      final id = await widget.push.deviceId;
      if (mounted) setState(() => deviceId = id);
    } catch (_) {
      /* Connecting can retry device storage. */
    }
  }

  Future<void> action(Future<void> Function() work) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.embedded
      ? content(context)
      : Scaffold(
          appBar: AppBar(title: const Text('通知与账号')),
          body: content(context),
        );

  Widget content(BuildContext context) => pageWidth(
    ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0xFFE7EEDC),
              child: Icon(Icons.person_outline_rounded, color: green, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '我的账号',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.profile?['email']?.toString() ?? '已登录',
                    style: const TextStyle(color: Color(0xFF66756C)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 48),
        const Text(
          '手机通知',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          !widget.push.supported
              ? '在 Android 或 iPhone 客户端连接通知，即可接收到站提醒。'
              : deviceId == null
              ? '连接这台手机，在系统通知中接收公交提醒。'
              : '这台手机已登记。发送一条测试通知，检查能否收到。',
        ),
        const SizedBox(height: 12),
        if (widget.push.supported)
          const Text(
            '开启后，极光推送服务会使用设备标识来发送通知。仅在你点击连接后初始化。',
            style: TextStyle(fontSize: 13, color: Color(0xFF66756C)),
          ),
        const SizedBox(height: 24),
        if (widget.push.supported)
          FilledButton(
            onPressed: busy
                ? null
                : () => action(() async {
                    final id = await widget.push.connect();
                    if (mounted) {
                      setState(() {
                        deviceId = id;
                        message = '手机已连接，请发送测试通知验证。';
                      });
                    }
                  }),
            child: Text(
              busy
                  ? '请稍候…'
                  : deviceId == null
                  ? '连接手机通知'
                  : '重新连接',
            ),
          ),
        if (deviceId != null) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => action(() async {
                    await widget.api.data(
                      '/api/mobile-push/devices/$deviceId/test',
                      method: 'POST',
                    );
                    if (mounted) {
                      setState(() => message = '推送平台已接受，请检查手机是否收到通知。');
                    }
                  }),
            child: const Text('发送测试通知'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => action(() async {
                    await widget.push.disconnect();
                    if (mounted) {
                      setState(() {
                        deviceId = null;
                        message = '此手机已断开通知';
                      });
                    }
                  }),
            child: const Text('断开此手机通知'),
          ),
        ],
        if (widget.push.supported)
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text('打开系统通知设置'),
          ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(message!),
          ),
        const Divider(),
        const Text('下班王 0.1.0', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          '所有提醒时段均按北京时间执行。\n车辆位置与预计到达时间来自公交数据服务。',
          style: TextStyle(color: Color(0xFF66756C), height: 1.7),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: busy
              ? null
              : () => action(() async {
                  await widget.push.disconnect();
                  await widget.api.logout();
                  if (context.mounted) {
                    Navigator.popUntil(context, (r) => r.isFirst);
                    widget.onLogout();
                  }
                }),
          child: const Text('退出登录'),
        ),
      ],
    ),
  );
}
