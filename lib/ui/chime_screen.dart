import 'package:chime_sim/chime_sim.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_services.dart';
import '../audio/chime_audio.dart';
import '../game/debug_stats.dart';
import '../game/render/sky.dart';
import '../game/wind_chime_game.dart';
import '../haptics/chime_haptics.dart';
import '../motion/motion_controller.dart';
import '../settings/app_settings.dart';
import '../settings/settings_controller.dart';
import '../wind/wind_controller.dart';
import 'controls/controls_sheet.dart';
import 'controls/location_section.dart';
import 'overlay_visibility.dart';
import 'overlays/debug_panel.dart';
import 'wind_chip.dart';

/// The app's only screen: the chime, full-bleed, with a wind chip in the corner and the controls
/// pill at the bottom. Both fade after a few seconds; tapping the sky brings them back.
class ChimeScreen extends StatefulWidget {
  const ChimeScreen({
    super.key,
    required this.services,
    this.settings = const AppSettings(),
    this.audioEnabled = true,
  });

  final AppServices services;

  /// As loaded before the first frame.
  final AppSettings settings;

  /// Off in widget tests, where there is no audio device.
  final bool audioEnabled;

  @override
  State<ChimeScreen> createState() => _ChimeScreenState();
}

class _ChimeScreenState extends State<ChimeScreen> {
  /// The wind the chime has "already been hanging in" when first seen, s.
  static const _warmUpSeconds = 6.0;
  static const _sheetMotion = Duration(milliseconds: 300);

  late final _settings = SettingsController(widget.services.store, widget.settings);
  late var _applied = widget.settings;
  final _stats = DebugStats();
  late final _simulation = ChimeSimulation(ChimeConfig.pentatonicAluminium());
  late final _audio = ChimeAudio(_simulation.rods);
  late final _motion = MotionController(source: widget.services.motion, inputs: _simulation.inputs);
  late final _wind = WindController(
    inputs: _simulation.inputs,
    weather: widget.services.weather,
    location: widget.services.location,
    store: widget.services.store,
    mode: widget.settings.mode,
    manual: widget.settings.manual,
    placement: widget.settings.placement,
  );
  late final _isPressing = _simulation.isPressingRod;
  final _haptics = ChimeHaptics();
  final _sky = SkyModel();
  late final _game = WindChimeGame(
    simulation: _simulation,
    sky: _sky,
    collisionSinks: [_audio, _stats, _haptics],
    beforePhysics: _motion.update,
    onFrame: _audioFrame,
    onEmptyTap: _onEmptyTap,
    stats: _stats,
  );
  // Built once: rebuilding it would needlessly re-layout the game on every settings change.
  late final _gameView = GameWidget<WindChimeGame>(game: _game);
  final _overlays = OverlayVisibility();
  final _sheet = DraggableScrollableController();
  final _searchFocus = FocusNode();
  late final AppLifecycleListener _lifecycle;
  var _windReady = false;
  var _chipOpen = false;
  var _sheetOpen = false;
  var _offerBusy = false;
  String? _offerError;

  /// Hour of the day to preview the sky at, while tuning; null shows now.
  double? _skyPreview;

  @override
  void initState() {
    super.initState();
    // Off screen: fade the sound out, switch the sensors off, stop fetching weather and save the
    // settings; back on screen, the reverse.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _audio.suspend();
        _motion.stop();
        _wind.pause();
        _settings.flush();
      },
      onShow: () {
        _audio.resume();
        _motion.start();
        _wind.resume();
      },
    );
    _settings.settings.addListener(_onSettings);
    _wind.status.addListener(_onWindStatus);
    _searchFocus.addListener(_onSearchFocus);
    _applyToEngines(widget.settings);
    _motion.start();
    _wind.start().then((_) {
      if (!mounted) return;
      // Don't show the chime starting from dead still: it has been hanging in this wind all along.
      if (_simulation.time < 1) _simulation.warmUp(_warmUpSeconds);
      setState(() => _windReady = true);
      _overlays.linger = _offerPending;
    });
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
    _settings.settings.removeListener(_onSettings);
    _wind.status.removeListener(_onWindStatus);
    _settings.dispose();
    _motion.dispose();
    _wind.dispose();
    _audio.dispose();
    _stats.dispose();
    _overlays.dispose();
    _sheet.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The first-run offer shows until answered, or until a location is chosen some other way.
  bool get _offerPending =>
      _windReady &&
      !_settings.value.liveWindOffered &&
      _settings.value.mode == WindMode.live &&
      _wind.status.value.location == null;

  void _audioFrame(double dt) {
    _audio.update(dt, windSpeed: _simulation.wind.speed, isPressing: _isPressing);
    _haptics.update(
      dt,
      playing: _simulation.inputs.isTouching || _motion.processor.shake.shaking,
    );
  }

  void _changeSettings(AppSettings Function(AppSettings current) change) => _settings.update(change);

  void _onSettings() {
    final s = _settings.value, old = _applied;
    _applied = s;
    if (s.mode != old.mode) _wind.setMode(s.mode);
    if (!identical(s.manual, old.manual)) _wind.setManual(s.manual);
    if (s.placement != old.placement) _wind.setPlacement(s.placement);
    _applyToEngines(s);
    _overlays.linger = _offerPending;
    setState(() {});
  }

  void _applyToEngines(AppSettings s) {
    if (s.showStats) _stats.watchFrameTimings();
    s.motion.applyTo(_motion.processor);
    _audio
      ..volume = s.volume
      ..ambience = s.ambience;
    _haptics.enabled = s.haptics;
    if (_sky.followsTime != s.skyFollowsTime) {
      _sky
        ..followsTime = s.skyFollowsTime
        ..invalidate();
    }
  }

  void _setSkyPreview(double? hour) {
    setState(() => _skyPreview = hour);
    _sky
      ..previewHour = hour
      ..invalidate();
  }

  void _onWindStatus() {
    // The sky follows the sun where the wind comes from.
    final at = _wind.status.value.coordinates;
    if (at != null && (at.latitude != _sky.latitude || at.longitude != _sky.longitude)) {
      _sky
        ..latitude = at.latitude
        ..longitude = at.longitude
        ..invalidate();
    }
    // A location chosen in the sheet answers the offer too.
    if (_wind.status.value.location != null && !_settings.value.liveWindOffered) {
      _changeSettings((s) => s.copyWith(liveWindOffered: true));
    }
  }

  void _onSearchFocus() {
    if (_searchFocus.hasFocus) _moveSheet(ControlsSheet.fullSize);
  }

  void _onEmptyTap() {
    if (_sheetOpen) {
      _moveSheet(null);
    } else if (_chipOpen) {
      _toggleChip();
    } else {
      _overlays.toggle();
    }
  }

  void _toggleChip() {
    setState(() => _chipOpen = !_chipOpen);
    _overlays.hold(#chip, _chipOpen);
  }

  /// Opens the sheet to [size], or closes it to the pill when null.
  void _moveSheet(double? size) {
    if (!_sheet.isAttached) return;
    final media = MediaQuery.of(context);
    _sheet.animateTo(
      size ?? ControlsSheet.minSizeFor(media.size.height, media.padding.bottom),
      duration: _sheetMotion,
      curve: Curves.easeOutCubic,
    );
    if (size == null) _searchFocus.unfocus();
  }

  void _onSheetExtent(double extent, bool open) {
    // Keep the chime in view above the open sheet.
    final height = MediaQuery.sizeOf(context).height;
    _game.projection.visibleHeight = open ? height * (1 - extent) : height;
    if (open == _sheetOpen) return;
    _sheetOpen = open;
    _overlays.hold(#sheet, open);
    if (!open) _searchFocus.unfocus();
  }

  Future<void> _useLocationFromOffer() async {
    setState(() {
      _offerBusy = true;
      _offerError = null;
    });
    final failure = await _wind.useDeviceLocation();
    if (!mounted) return;
    setState(() {
      _offerBusy = false;
      _offerError = failure == null ? null : locationFailureText(failure);
    });
    if (failure == null) _changeSettings((s) => s.copyWith(liveWindOffered: true));
  }

  void _pickCityFromOffer() {
    _changeSettings((s) => s.copyWith(liveWindOffered: true));
    _moveSheet(ControlsSheet.fullSize);
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings.value;
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
          backgroundColor: SkyPalette.dusk.top,
          // The keyboard covers the sheet's lower part rather than squeezing the chime.
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              Positioned.fill(child: _gameView),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Fading(visible: _overlays, child: _buildChip(settings)),
                      if (settings.showStats) ...[
                        const SizedBox(height: 8),
                        DebugPanel(
                          stats: _stats,
                          audioStatus: _audio.status,
                          onReset: _simulation.reset,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _Fading(
                visible: _overlays,
                child: ControlsSheet(
                  controller: _sheet,
                  settings: settings,
                  onChanged: _changeSettings,
                  wind: _wind,
                  places: widget.services.places,
                  motion: _motion.snapshot,
                  searchFocus: _searchFocus,
                  onExtentChanged: _onSheetExtent,
                  skyPreviewHour: _skyPreview,
                  onSkyPreview: _setSkyPreview,
                ),
              ),
              if (kIsWeb && widget.audioEnabled) _TapForSound(status: _audio.status),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChip(AppSettings settings) {
    return ValueListenableBuilder<WindStatus>(
      valueListenable: _wind.status,
      builder: (context, status, _) => WindChip(
        status: status,
        units: settings.units,
        expanded: _chipOpen,
        onTap: _toggleChip,
        offer: _offerPending
            ? LiveWindOffer(
                busy: _offerBusy,
                error: _offerError,
                onUseLocation: _useLocationFromOffer,
                onPickCity: _pickCityFromOffer,
                onDismiss: () => _changeSettings((s) => s.copyWith(liveWindOffered: true)),
              )
            : null,
      ),
    );
  }
}

/// Fades [child] with the overlays; touching it keeps them up.
class _Fading extends StatelessWidget {
  const _Fading({required this.visible, required this.child});

  final OverlayVisibility visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: visible,
      builder: (context, shown, child) => IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: child,
        ),
      ),
      child: Listener(onPointerDown: (_) => visible.poke(), child: child),
    );
  }
}

/// Browsers start audio only from a gesture: say so until the first touch.
class _TapForSound extends StatelessWidget {
  const _TapForSound({required this.status});

  final ValueNotifier<String> status;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: status,
      builder: (context, s, _) => s != 'starts on first touch'
          ? const SizedBox.shrink()
          : const Align(
              alignment: Alignment(0, 0.55),
              child: IgnorePointer(
                child: Chip(
                  avatar: Icon(Icons.volume_up_outlined, size: 18),
                  label: Text('Tap anywhere for sound'),
                ),
              ),
            ),
    );
  }
}
