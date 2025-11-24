import 'package:flutter/material.dart';
import 'package:app/screens/home_screen.dart';

void main() {
  runApp(const AudireApp());
}

class AudireApp extends StatelessWidget {
  const AudireApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audire',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}