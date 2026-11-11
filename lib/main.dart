
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  var supabaseConfigured = false;

  if (url.startsWith('https://') && key.isNotEmpty) {
    await Supabase.initialize(url: url, anonKey: key);
    supabaseConfigured = true;
  }

  runApp(ChatWaveApp(supabaseConfigured: supabaseConfigured));
}

class ChatWaveApp extends StatelessWidget {
  const ChatWaveApp({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF101827);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChatWave',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: navy,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF27C7A5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: SetupScreen(supabaseConfigured: supabaseConfigured),
    );
  }
}

class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, required this.supabaseConfigured});

  final bool supabaseConfigured;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.forum_rounded, size: 76,
                      color: Color(0xFF27C7A5)),
                  const SizedBox(height: 20),
                  const Text(
                    'ChatWave',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Messages that move with you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 36),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.login),
                    label: const Text('Google sign-in — setup next'),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    supabaseConfigured
                        ? 'Supabase configuration detected. Authentication is the next milestone.'
                        : 'Setup required: add your Supabase URL and publishable key to the .env file.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white60, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Flutter + Dart + Supabase',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF27C7A5), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
