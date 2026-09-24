import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../ui/chime_screen.dart';
import 'app_services.dart';

class WindChimesApp extends StatelessWidget {
  const WindChimesApp({
    super.key,
    required this.services,
    this.settings = const AppSettings(),
    this.audioEnabled = true,
  });

  final AppServices services;
  final AppSettings settings;
  final bool audioEnabled;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wind Chimes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFB7C0C9),
      ),
      home: ChimeScreen(services: services, settings: settings, audioEnabled: audioEnabled),
    );
  }
}
