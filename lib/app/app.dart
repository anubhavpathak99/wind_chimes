import 'package:flutter/material.dart';

import '../ui/chime_screen.dart';

class WindChimesApp extends StatelessWidget {
  const WindChimesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wind Chimes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFB7C0C9),
      ),
      home: const ChimeScreen(),
    );
  }
}
