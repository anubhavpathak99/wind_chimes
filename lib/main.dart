import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/app_services.dart';
import 'settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sensor axes are fixed to the device, so the tilt mapping assumes portrait.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final services = AppServices.standard();
  // A few milliseconds: worth it so the first frame is already in the right mode.
  final settings = await SettingsController.load(
    services.store,
    region: PlatformDispatcher.instance.locale.countryCode,
  );
  runApp(WindChimesApp(services: services, settings: settings));
}
