import 'package:flutter/material.dart';

import '../motion/motion_source.dart';
import '../ui/chime_screen.dart';
import '../wind/wind_services.dart';

class WindChimesApp extends StatelessWidget {
  const WindChimesApp({
    super.key,
    this.audioEnabled = true,
    this.motionSource,
    this.windServices,
  });

  final bool audioEnabled;
  final MotionSource? motionSource;
  final WindServices? windServices;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Wind Chimes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFB7C0C9),
      ),
      home: ChimeScreen(
        audioEnabled: audioEnabled,
        motionSource: motionSource,
        windServices: windServices,
      ),
    );
  }
}
