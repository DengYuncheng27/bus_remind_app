import 'package:flutter/material.dart';

import '../api.dart';
import '../palette.dart';
import '../ui.dart';

class AuthScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onSuccess;
  const AuthScreen({super.key, required this.api, required this.onSuccess});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      invite = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false;
  String? mode, error;
  @override
  void initState() {
    super.initState();
    loadPolicy();
  }

  Future<void> loadPolicy() async {
    try {
      final data = await widget.api.data('/api/auth/registration');
      if (mounted) setState(() => mode = data['mode']);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    invite.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.request(
        '/api/auth/${register ? 'register' : 'login'}',
        method: 'POST',
        body: {
          'email': email.text.trim(),
          'password': password.text,
          if (register) 'inviteCode': invite.text.trim(),
        },
      );
      await widget.api.saveToken(data['token']);
      if (mounted) widget.onSuccess();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: pageWidth(
        ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 64),
            const Align(
              alignment: Alignment.centerLeft,
              child: Icon(Icons.directions_bus_rounded, size: 44, color: green),
            ),
            const SizedBox(height: 20),
            Text('下班王', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text(
              '车快到了，叫你出发。',
              style: TextStyle(fontSize: 18, color: Color(0xFF66756C)),
            ),
            const SizedBox(height: 48),
            Text(
              register ? '创建账号' : '登录，开始你的通勤',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Form(
              key: form,
              child: Column(
                children: [
                  TextFormField(
                    controller: email,
                    decoration: InputDecoration(
                      labelText: register ? '邮箱' : '邮箱或账号',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? '请输入账号' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    decoration: const InputDecoration(labelText: '密码'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) {
                      if (!busy) submit();
                    },
                    validator: (v) => v == null || v.isEmpty
                        ? '请输入密码'
                        : register && v.length < 8
                        ? '密码至少 8 位'
                        : null,
                  ),
                  if (register && mode == 'invite_only') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: invite,
                      decoration: const InputDecoration(labelText: '邀请码'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请输入邀请码' : null,
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy
                            ? '请稍候…'
                            : register
                            ? '创建并登录'
                            : '登录',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (mode != null && mode != 'closed')
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        register = !register;
                        error = null;
                      }),
                child: Text(register ? '已有账号，去登录' : '还没有账号？创建一个'),
              ),
            if (mode == null)
              TextButton(onPressed: loadPolicy, child: const Text('重新检查注册状态')),
          ],
        ),
      ),
    ),
  );
}
