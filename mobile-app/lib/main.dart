import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const SongBookApp());
}

class SongBookApp extends StatelessWidget {
  const SongBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Песенник',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        inputDecorationTheme: const InputDecorationTheme(
          hintStyle: TextStyle(color: Colors.black38),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
