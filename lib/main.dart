import 'package:flutter/material.dart';
import 'login.dart';
import 'japanFolder/loginJP.dart';
import 'phorjapan.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? phOrJp = prefs.getString('phorjp');

  runApp(MyApp(initialRoute: phOrJp == null ? '/phorjapan' : phOrJp == 'ph' ? '/login' : '/loginJP'));
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARK LOG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      initialRoute: initialRoute,
      routes: {
        '/phorjapan': (context) => const PhOrJpScreen(),
        '/login': (context) => const LoginScreen(),
        '/loginJP': (context) => const LoginScreenJP(),
      },
    );
  }
}