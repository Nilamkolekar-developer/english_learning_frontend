import 'package:flutter/material.dart';
import 'api.dart';
import 'session.dart';
import 'auth_screens.dart';
import 'app_screens.dart';

const brand = Color(0xFF0F7B63);
const amber = Color(0xFFE8A33D);
const ground = Color(0xFFF2F6F4);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = Session();
  await session.load();
  // If the subscription ends while the app is open, go straight to the subscribe screen.
  Api.onSubscriptionRequired = () {
    if (session.subscribed) session.refreshStatus();
  };
  runApp(App(session));
}

class App extends StatelessWidget {
  final Session session;
  const App(this.session, {super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'English Practice',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        scaffoldBackgroundColor: ground,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      // Login once -> Subscribe once -> Home. No re-login on restart.
      home: ListenableBuilder(
        listenable: session,
        builder: (_, __) {
          if (!session.loggedIn) return LoginScreen(session);
          if (!session.subscribed) return SubscribeScreen(session);
          return HomeShell(session);
        },
      ),
    );
  }
}