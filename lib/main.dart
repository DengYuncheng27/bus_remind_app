import 'theme.dart';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'demo.dart';
import 'screens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    CommuteApp(api: const bool.fromEnvironment('DEMO') ? DemoApi() : Api()),
  );
}

class CommuteApp extends StatefulWidget {
  final Api api;
  const CommuteApp({super.key, required this.api});
  @override
  State<CommuteApp> createState() => _CommuteAppState();
}

class _CommuteAppState extends State<CommuteApp> {
  bool loading = true;
  bool signedIn = false;
  String? error;
  final navigatorKey = GlobalKey<NavigatorState>();
  @override
  void initState() {
    super.initState();
    widget.api.onUnauthorized = () {
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      if (mounted) setState(() => signedIn = false);
    };
    restore();
  }

  Future<void> restore() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.api.restore();
      if (widget.api.token != null) {
        await widget.api.request('/api/me');
        signedIn = true;
      }
    } catch (e) {
      if (widget.api.token != null) error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    title: '下班王',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    theme: commuteTheme(),
    home: loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : error != null
        ? Scaffold(body: Center(child: ErrorNotice(error!, restore)))
        : signedIn
        ? HomeScreen(
            api: widget.api,
            onLogout: () => setState(() => signedIn = false),
          )
        : AuthScreen(
            api: widget.api,
            onSuccess: () => setState(() => signedIn = true),
          ),
  );
}
