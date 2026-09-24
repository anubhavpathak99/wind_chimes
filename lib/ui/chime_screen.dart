import 'package:chime_sim/chime_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/debug_stats.dart';
import '../game/render/sky_background.dart';
import '../game/wind_chime_game.dart';
import 'overlays/debug_panel.dart';

/// The app's only screen: the chime, full-bleed, with overlays on top.
class ChimeScreen extends StatefulWidget {
  const ChimeScreen({super.key});

  @override
  State<ChimeScreen> createState() => _ChimeScreenState();
}

class _ChimeScreenState extends State<ChimeScreen> {
  final _stats = DebugStats();
  late final _simulation = ChimeSimulation(ChimeConfig.pentatonicAluminium());
  late final _game = WindChimeGame(simulation: _simulation, collisionSink: _stats, stats: _stats);

  @override
  void dispose() {
    _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: SkyBackground.top,
        body: GameWidget<WindChimeGame>(
          game: _game,
          overlayBuilderMap: {
            DebugPanel.overlayId: (context, game) =>
                DebugPanel(stats: _stats, onReset: _simulation.reset),
          },
          initialActiveOverlays: kReleaseMode ? const [] : const [DebugPanel.overlayId],
        ),
      ),
    );
  }
}
