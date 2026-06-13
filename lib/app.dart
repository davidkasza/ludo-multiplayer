import 'package:flutter/material.dart';

import 'screens/ludo_app.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo Multiplayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LudoApp(),
    );
  }
}