import 'package:flutter/material.dart';

import '../api.dart';
import '../ui.dart';

class PasswordScreen extends StatefulWidget {
  final Api api;
  const PasswordScreen({super.key, required this.api});
  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final current = TextEditingController(),
      next = TextEditingController(),
      repeated = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    repeated.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (next.text.length < 8 ||
        next.text != repeated.text ||
        current.text.isEmpty) {
      setState(() => error = '请填写原密码，新密码至少 8 位，且两次输入一致。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.request(
        '/api/auth/change-password',
        method: 'POST',
        body: {'currentPassword': current.text, 'newPassword': next.text},
      );
      await widget.api.saveToken(result['token'] as String);
      if (mounted) {
        notice(context, '密码已更新');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('修改密码')),
    body: pageWidth(
      ListView(
        padding: const EdgeInsets.all(24),
        children: [
          for (final item in [
            (current, '原密码'),
            (next, '新密码'),
            (repeated, '再次输入新密码'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: TextField(
                controller: item.$1,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                enabled: !busy,
                decoration: InputDecoration(labelText: item.$2),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? '保存中…' : '更新密码'),
          ),
        ],
      ),
    ),
  );
}
