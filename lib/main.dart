import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_page.dart';
import 'config/constants.dart';
import 'pages/conversations_list_page.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );

    runApp(const MyApp());
  }, (error, stackTrace) {
    // ignore: avoid_print
    print('Uncaught error: $error');
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Session? _session;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      setState(() => _session = data.session);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhatsApp Dashboard',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFFF7A59),
        useMaterial3: true,
        visualDensity: VisualDensity.comfortable,
      ),
      // App-wide size bump: scales every Text (and anything sized in em-like
      // terms) by 30% on top of the user's own system font setting.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * 1.3)),
          child: child!,
        );
      },
      home: _session == null ? const AuthPage() : const ConversationsListPage(),
    );
  }
}
