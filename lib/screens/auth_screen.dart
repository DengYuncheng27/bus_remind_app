import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../email_address.dart';
import '../palette.dart';
import '../ui.dart';

enum _AuthMode { login, register, reset, verify }

class AuthScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onSuccess;
  final String? verificationEmail;
  const AuthScreen({
    super.key,
    required this.api,
    required this.onSuccess,
    this.verificationEmail,
  });
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirmation = TextEditingController(),
      invite = TextEditingController(),
      code = TextEditingController();
  var form = GlobalKey<FormState>();
  _AuthMode mode = _AuthMode.login;
  bool busy = false, sending = false, emailAvailable = false, hidden = true;
  String? policy, error, message, challengeId, sentEmail;
  int retryAfter = 0;
  Timer? timer;
  bool get login => mode == _AuthMode.login;
  bool get register => mode == _AuthMode.register;
  bool get verify => mode == _AuthMode.verify;
  bool get locked => busy || sending;
  String get normalizedEmail => email.text.trim().toLowerCase();
  bool get validEmail => isValidEmailAddress(normalizedEmail);

  String get codeRequestMessage => switch (mode) {
    _AuthMode.register => '验证码请求已受理，10 分钟内有效。请查看收件箱和垃圾邮件。',
    _AuthMode.reset => '请求已受理，仅已验证邮箱的正常账号会发送重置验证码。旧账号若尚未验证邮箱，请先用原密码登录并到「我的 → 邮箱验证」完成验证。验证码 10 分钟有效，倒计时不代表邮件已送达。',
    _ => '验证请求已受理，请检查收件箱和垃圾邮件。验证码 10 分钟有效，倒计时仅表示再次请求的间隔，不代表邮件已送达。',
  };

  @override
  void initState() {
    super.initState();
    if (widget.verificationEmail != null) {
      mode = _AuthMode.verify;
      email.text = widget.verificationEmail!;
    }
    loadPolicy();
  }

  Future<void> loadPolicy() async {
    try {
      final data = await widget.api.data('/api/auth/registration');
      if (mounted) {
        setState(() {
          policy = data['mode'];
          emailAvailable = data['emailAvailable'] == true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final controller in [email, password, confirmation, invite, code]) {
      controller.dispose();
    }
    super.dispose();
  }

  void clearChallenge() {
    challengeId = null;
    sentEmail = null;
    code.clear();
    message = null;
  }

  void changeMode(_AuthMode value) {
    setState(() {
      mode = value;
      form = GlobalKey<FormState>();
      error = null;
      password.clear();
      confirmation.clear();
      clearChallenge();
    });
  }

  Future<void> sendCode() async {
    if (!validEmail) {
      setState(() => error = '请输入有效的邮箱地址');
      return;
    }
    if (register && policy == 'invite_only' && invite.text.trim().isEmpty) {
      setState(() => error = '请先填写邀请码');
      return;
    }
    final target = normalizedEmail;
    setState(() {
      sending = true;
      error = null;
      message = null;
    });
    try {
      final data = await widget.api.data(
        verify ? '/api/auth/email-verification/code' : '/api/auth/email-code',
        method: 'POST',
        body: verify
            ? null
            : {
                'email': target,
                'purpose': register ? 'register' : 'reset',
                if (register && policy == 'invite_only')
                  'inviteCode': invite.text.trim(),
              },
      );
      if (!mounted) return;
      setState(() {
        challengeId = data['challengeId'];
        sentEmail = target;
        retryAfter = (data['retryAfter'] as num?)?.toInt() ?? 60;
        message = codeRequestMessage;
      });
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          if (retryAfter > 0) retryAfter--;
        });
        if (retryAfter == 0) timer.cancel();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          if (register && e is ApiException && e.status == 409) {
            clearChallenge();
            timer?.cancel();
            retryAfter = 0;
          }
          error = e.toString();
        });
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    if (!login && (challengeId == null || sentEmail != normalizedEmail)) {
      setState(() => error = '请先为当前邮箱获取验证码');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final proof = {'challengeId': challengeId, 'code': code.text.trim()};
      if (verify) {
        await widget.api.request(
          '/api/auth/email-verification',
          method: 'POST',
          body: proof,
        );
        if (mounted) widget.onSuccess();
      } else if (mode == _AuthMode.reset) {
        await widget.api.request(
          '/api/auth/reset-password',
          method: 'POST',
          body: {
            'email': normalizedEmail,
            'newPassword': password.text,
            ...proof,
          },
        );
        if (!mounted) return;
        changeMode(_AuthMode.login);
        setState(() => message = '密码已重置，请使用新密码登录。');
      } else {
        final data = await widget.api.request(
          '/api/auth/${register ? 'register' : 'login'}',
          method: 'POST',
          body: {
            'email': email.text.trim(),
            'password': password.text,
            if (register) ...proof,
            if (register && policy == 'invite_only')
              'inviteCode': invite.text.trim(),
          },
        );
        await widget.api.saveToken(data['token']);
        if (mounted) widget.onSuccess();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: verify ? AppBar(title: const Text('验证邮箱')) : null,
    body: SafeArea(
      child: pageWidth(
        ListView(
          padding: const EdgeInsets.all(28),
          children: [
            SizedBox(height: verify ? 16 : 36),
            const Align(
              alignment: Alignment.centerLeft,
              child: AppBrandIcon(size: 60),
            ),
            const SizedBox(height: 20),
            Text('下班王', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text(
              '车快到了，叫你出发。',
              style: TextStyle(fontSize: 18, color: Color(0xFF66756C)),
            ),
            const SizedBox(height: 32),
            Text(switch (mode) {
              _AuthMode.login => '登录，开始你的通勤',
              _AuthMode.register => '创建账号',
              _AuthMode.reset => '找回密码',
              _AuthMode.verify => '让账号多一份保障',
            }, style: Theme.of(context).textTheme.headlineSmall),
            if (!login) ...[
              const SizedBox(height: 8),
              Text(
                verify
                    ? '验证当前邮箱后，可以在忘记密码时找回账号。'
                    : register
                    ? '填写邮箱和密码，再输入邮箱验证码，即可开启通勤提醒。'
                    : '使用已验证的邮箱重置密码。旧账号若尚未验证邮箱，请先登录并到「我的」完成验证。',
                style: const TextStyle(color: Color(0xFF66756C), height: 1.6),
              ),
              if (policy != null && !emailAvailable)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('邮件服务暂不可用，请稍后重试。已有账号仍可登录。'),
                ),
            ],
            const SizedBox(height: 24),
            Form(
              key: form,
              child: AutofillGroup(
                child: Column(
                  children: [
                    TextFormField(
                      key: const ValueKey('auth-email'),
                      controller: email,
                      readOnly: verify || locked,
                      maxLength: 254,
                      decoration: InputDecoration(
                        labelText: login ? '邮箱或账号' : '邮箱',
                        counterText: '',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      onChanged: (_) => setState(() {
                        clearChallenge();
                        error = null;
                      }),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? '请输入账号'
                          : !login && !validEmail
                          ? '请输入有效的邮箱地址'
                          : null,
                    ),
                    if (register && policy == 'invite_only') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: invite,
                        readOnly: locked,
                        decoration: const InputDecoration(labelText: '邀请码'),
                        onChanged: (_) => setState(clearChallenge),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请输入邀请码' : null,
                      ),
                    ],
                    if (!verify) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('auth-password'),
                        controller: password,
                        textInputAction: login
                            ? TextInputAction.done
                            : TextInputAction.next,
                        readOnly: locked,
                        maxLength: 128,
                        decoration: InputDecoration(
                          labelText: mode == _AuthMode.reset ? '新密码' : '密码',
                          counterText: '',
                          helperText: login ? null : '至少 8 位，建议使用字母、数字与符号',
                          suffixIcon: IconButton(
                            tooltip: hidden ? '显示密码' : '隐藏密码',
                            onPressed: () => setState(() => hidden = !hidden),
                            icon: Icon(
                              hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        obscureText: hidden,
                        autofillHints: [
                          login
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        onFieldSubmitted: (_) {
                          if (!locked && login) submit();
                        },
                        validator: (v) => v == null || v.isEmpty
                            ? '请输入密码'
                            : !login && v.length < 8
                            ? '密码至少 8 位'
                            : null,
                      ),
                      if (!login) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('auth-confirm'),
                          controller: confirmation,
                          textInputAction: TextInputAction.next,
                          readOnly: locked,
                          decoration: const InputDecoration(
                            labelText: '再次输入密码',
                          ),
                          obscureText: hidden,
                          autofillHints: const [AutofillHints.newPassword],
                          validator: (v) =>
                              v != password.text ? '两次输入的密码不一致' : null,
                        ),
                      ],
                    ],
                    if (!login) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const ValueKey('auth-code'),
                        controller: code,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!locked && emailAvailable) submit();
                        },
                        readOnly: locked,
                        decoration: const InputDecoration(
                          labelText: '邮箱验证码',
                          hintText: '6 位数字',
                        ),
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        validator: (v) => v?.length != 6 ? '请输入 6 位验证码' : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const ValueKey('send-code'),
                          onPressed: locked || !emailAvailable || retryAfter > 0
                              ? null
                              : sendCode,
                          child: Text(
                            sending
                                ? '正在发送…'
                                : retryAfter > 0
                                ? '$retryAfter 秒后重新发送'
                                : challengeId == null
                                ? '获取验证码'
                                : '重新发送验证码',
                          ),
                        ),
                      ),
                    ],
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          message!,
                          style: const TextStyle(color: green, height: 1.6),
                        ),
                      ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
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
                        key: const ValueKey('auth-submit'),
                        onPressed: locked || (!login && !emailAvailable)
                            ? null
                            : submit,
                        child: Text(
                          busy
                              ? '请稍候…'
                              : switch (mode) {
                                  _AuthMode.login => '登录',
                                  _AuthMode.register => '验证并创建账号',
                                  _AuthMode.reset => '重置密码',
                                  _AuthMode.verify => '完成验证',
                                },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (login)
              TextButton(
                onPressed: locked ? null : () => changeMode(_AuthMode.reset),
                child: const Text('忘记密码？'),
              ),
            if (!verify && (policy != null && policy != 'closed' || !login))
              TextButton(
                onPressed: locked
                    ? null
                    : () => changeMode(
                        login ? _AuthMode.register : _AuthMode.login,
                      ),
                child: Text(login ? '还没有账号？创建一个' : '已有账号，去登录'),
              ),
            if (policy == null)
              TextButton(onPressed: loadPolicy, child: const Text('重新检查服务状态')),
          ],
        ),
      ),
    ),
  );
}
