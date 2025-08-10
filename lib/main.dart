import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_firebase/features/app/splash_screen/splash_screen.dart';
import 'package:flutter_firebase/features/user_auth/presentation/pages/home_page.dart';
import 'package:flutter_firebase/features/user_auth/presentation/pages/login_page.dart';
import 'package:flutter_firebase/features/user_auth/presentation/pages/sign_up_page.dart';
import 'package:provider/provider.dart';
import 'package:flutter_firebase/features/user_auth/presentation/pages/theme_notifier.dart';
import 'package:flutter_firebase/features/user_auth/presentation/pages/settings_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase for web or mobile
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyDDf34EtpXTK11gYjbwIrKWqED1snT7RCs",
        appId: "1:725186798816:web:6572e0fe4c8c2ac3fc1c85",
        messagingSenderId: "725186798816",
        projectId: "flutter-firebase-2d37a",
        databaseURL: "https://flutter-firebase-2d37a-default-rtdb.firebaseio.com", // Add database URL
      ),
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsNotifier()),
        ChangeNotifierProvider(
          create: (_) => ThemeNotifier(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  // Define a global navigator key for navigation outside of widget tree
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeNotifier>(
      builder: (context, themeNotifier, child) {
        return MaterialApp(
          navigatorKey: navigatorKey, // Assign navigator key
          debugShowCheckedModeBanner: false,
          title: 'Flutter Firebase',
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeNotifier.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const AuthWrapper(),
          routes: {
            '/login': (context) => const LoginPage(),
            '/signUp': (context) => const SignUpPage(),
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen(
            child: CircularProgressIndicator(), // Show loading indicator
          );
        } else if (snapshot.hasData) {
          // User is logged in, navigate to HomePage
          return HomePage(user: snapshot.data!);
        } else {
          // User is not logged in, navigate to LoginPage
          return const LoginPage();
        }
      },
    );
  }
}