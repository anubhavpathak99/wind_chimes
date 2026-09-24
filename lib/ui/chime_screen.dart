import 'package:chime_sim/chime_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/chime_audio.dart';
import '../game/debug_stats.dart';
import '../game/render/sky_background.dart';
import '../game/wind_chime_game.dart';
import '../motion/motion_controller.dart';
import '../motion/motion_settings.dart';
import '../motion/motion_source.dart';
import '../wind/manual_wind.dart';
import 'overlays/debug_panel.dart';
import 'overlays/motion_panel.dart';
import 'overlays/wind_panel.dart';

/// The app's only screen: the chime, full-bleed, with overlays on top.
class ChimeScreen extends StatefulWidget {
  const ChimeScreen({super.key, this.audioEnabled = true, this.motionSource});

  /// Off in widget tests, where there is no audio device.
  final bool audioEnabled;

  /// Where phone motion comes from; the device's sensors by default.
  final MotionSource? motionSource;

  @override
  State<ChimeScreen> createState() => _ChimeScreenState();
}

class _ChimeScreenState extends State<ChimeScreen> {
  static const _debugOverlay = 'debug';

  final _stats = DebugStats();
  late final _simulation = ChimeSimulation(ChimeConfig.pentatonicAluminium());
  late final _audio = ChimeAudio(_simulation.rods);
  late final _motion = MotionController(
    source: widget.motionSource ?? const SensorsPlusMotionSource(),
    inputs: _simulation.inputs,
  );
  late final _isPressing = _simulation.isPressingRod;
  late final _game = WindChimeGame(
    simulation: _simulation,
    collisionSinks: [_audio, _stats],
    beforePhysics: _motion.update,
    onFrame: _audioFrame,
    stats: _stats,
  );
  late final AppLifecycleListener _lifecycle;
  var _wind = const ManualWind();
  var _motionSettings = const MotionSettings();
  var _windPanelOpen = false;
  var _motionPanelOpen = false;

  @override
  void initState() {
    super.initState();
    // Off screen: fade the sound out and switch the sensors off; back on screen, the reverse.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _audio.suspend();
        _motion.stop();
      },
      onShow: () {
        _audio.resume();
        _motion.start();
      },
    );
    _wind.applyTo(_simulation.inputs);
    _motionSettings.applyTo(_motion.processor);
    _motion.start();
    if (!widget.audioEnabled) {
      _audio.status.value = 'disabled';
    } else if (kIsWeb) {
      // Browsers only allow audio to start from a user gesture.
      _audio.status.value = 'starts on first touch';
    } else {
      _audio.start();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _motion.dispose();
    _audio.dispose();
    _stats.dispose();
    super.dispose();
  }

  void _audioFrame(double dt) =>
      _audio.update(dt, windSpeed: _simulation.wind.speed, isPressing: _isPressing);

  void _setMotion(MotionSettings settings) {
    setState(() => _motionSettings = settings);
    settings.applyTo(_motion.processor);
  }

  void _setWind(ManualWind wind) {
    setState(() => _wind = wind);
    wind.applyTo(_simulation.inputs);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Listener(
        onPointerDown: (_) {
          if (widget.audioEnabled) _audio.start();
        },
        child: Scaffold(
          backgroundColor: SkyBackground.top,
          body: GameWidget<WindChimeGame>(
            game: _game,
            overlayBuilderMap: {_debugOverlay: (context, game) => _buildDebugOverlay()},
            initialActiveOverlays: kReleaseMode ? const [] : const [_debugOverlay],
          ),
        ),
      ),
    );
  }

  Widget _buildDebugOverlay() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: DebugPanel(
                stats: _stats,
                audioStatus: _audio.status,
                onReset: _simulation.reset,
              ),
            ),
            const Spacer(),
            MotionPanel(
              motion: _motion.snapshot,
              settings: _motionSettings,
              onChanged: _setMotion,
              expanded: _motionPanelOpen,
              onToggle: () => setState(() => _motionPanelOpen = !_motionPanelOpen),
            ),
            const SizedBox(height: 8),
            WindPanel(
              wind: _wind,
              onChanged: _setWind,
              expanded: _windPanelOpen,
              onToggle: () => setState(() => _windPanelOpen = !_windPanelOpen),
            ),
          ],
        ),
      ),
    );
  }
}
