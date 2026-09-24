# Wind Chimes — Design

A physically simulated wind chime for iOS and Android, built with Flutter + Flame. Its movement and
sound respond to real-world wind and to how the phone is held, tilted and shaken.

**Status:** Phases 0–7 done (simulation core, 2.5D renderer, drag/fling, wind model, tuning harness,
camera framing, audio engine, motion sensors, real weather, UI shell, polish). Still to do on real
phones: the 60 fps and battery checks (`tool/battery_check.sh`). See
[Phase 2 tuning notes](#phase-2-tuning-notes), [Phase 3 audio notes](#phase-3-audio-notes),
[Phase 4 motion notes](#phase-4-motion-notes), [Phase 5 weather notes](#phase-5-weather-notes),
[Phase 6 UI notes](#phase-6-ui-notes) and [Phase 7 polish notes](#phase-7-polish-notes).

---

## Key decisions

These are the decisions that differ from the original brief, and why.

1. **Simulate in 3D, render in 2D ("2.5D").** In a flat 2D side view with rods in a row, the clapper
   can only reach the rod directly left or right of it: two notes, forever. Real chimes put the rods
   in a ring around the clapper. The simulation models that ring in 3D (particles use three
   coordinates instead of two; the collision math is identical) and the renderer draws it with a fixed,
   slightly-low camera and painter's-order depth sorting. Wind direction becomes meaningful as a
   result: a north wind drives the clapper into the rods on the south side.
2. **Physics is a pure-Dart package, not Flame components.** Flame runs the loop and draws. The
   simulation is `step(dt, inputs) → state + events` with no Flutter or Flame imports
   (`packages/chime_sim`), so it can be tested headless and tuned with scripts. Flame's collision
   system (`HasCollisionDetection`, hitboxes) is overlap detection only — no impulse, no contact
   velocity, evaluated per frame rather than per substep — so it is not used at all.
3. **A weather API returns a mean, not wind.** Open-Meteo returns a 10-minute average at 10 m height.
   A constant force pushes the chime to a new resting angle and it goes quiet: **steady wind doesn't
   ring chimes, fluctuations do.** A wind synthesizer sits between the API and the physics: mean (from
   the API) + turbulence (Ornstein–Uhlenbeck) + discrete gusts (sized by the API's gust value).
4. **Tilt rotates gravity; shake is an inertial force.** Treating the phone as a window onto a real
   chime, tilting it keeps the chime plumb in the real world, which on screen means gravity rotates.
   That yields "tilt right → chime swings right", and the transient swing produces collisions.
   Shaking applies the phone's linear acceleration as a pseudo-force (−m·a) to every body — the
   physically exact model of a chime hanging inside the phone — rather than "shake detected → add a
   random force".
5. **Audio is its own module, fed by an event buffer, using `flutter_soloud`.** `flame_audio` /
   `audioplayers` is built for occasional sound effects: high Android latency, one platform player per
   sound, weak polyphony. A chime needs 10–20 overlapping, pitch-varied, long-tailed voices at low
   latency.
6. **Touch is part of the MVP.** Dragging and flinging the clapper, and swiping to make a gust, is the
   first thing anyone tries and the fastest way to test the physics.

---

## A. System Architecture

```
┌──────────────────────────── FLUTTER APP SHELL ────────────────────────────┐
│ UI: ChimeScreen = GameWidget + overlays (wind chip, controls, debug)      │
│        ▲ observes ≤5 Hz                         │ user actions             │
│ ┌──────┴──────────── Application layer (Riverpod) ▼──────────────────┐    │
│ │ WindController  MotionController  SettingsController  Lifecycle    │    │
│ └─────┬───────────────┬─────────────────┬────────────────────────────┘    │
│  WeatherProvider   MotionSource     SettingsRepo                          │
│  + Location        (sensors_plus;   (shared_prefs)                        │
│  (Open-Meteo/MET)   native later)                                         │
└───────┬───────────────┬─────────────────┬─────────────────────────────────┘
        │ WindTarget    │ MotionSample    │ SimConfig / AudioConfig
        │ (~30 min)     │ (50 Hz)         │ (on change)
        ▼               ▼                 ▼
   ┌────────────── SimInputs: latest-value snapshot ──────────────┐
   └──────────────────────────────┬────────────────────────────────┘
                                  │ read once per fixed step
┌───── FLAME: loop + view ────────┼──┐   ┌──── chime_sim (pure Dart pkg) ────┐
│ WindChimeGame.update(dt)        ▼  │   │ FixedStepper 120 Hz × 4 substeps  │
│   accumulator ─────────────────────┼──►│ WindField  mean·turbulence·gusts  │
│   drain events ◄───────────────────┼───│ Particles  SoA Float64List        │
│ ChimeRenderer (3D→2.5D, interp) ◄──┼───│ Constraints strings, rigid rods   │
│ Sky · particles · touch→SimInputs  │   │ Collisions → EventRing            │
└──────────────┬─────────────────────┘   └───────────────────────────────────┘
               │ CollisionEvent batch, once per frame
        ┌──────▼──────────────────────────────────┐
        │ AudioEngine (interface) → flutter_soloud │
        │ HitMapper · VoiceAllocator · reverb ·    │
        │ wind ambience · HapticsSink (later)      │
        └──────────────────────────────────────────┘
```

### Data-flow rules

- **Write inputs when data arrives; read them once per physics step.** Sensor and weather callbacks
  write their latest value into `SimInputs`; each fixed step reads whatever is there. No streams cross
  into the simulation, and nothing calls `setState` per sensor event.
- **Everything runs on the main isolate.** The simulation is about 15 particles and takes
  microseconds per step; an isolate would only add latency and copying. The one exception is baking
  procedural audio samples, which uses `Isolate.run`.
- **The simulation has two outputs:** state (position arrays the renderer reads each frame) and events
  (a preallocated ring buffer, drained once per frame into audio and haptics).
- **"Intensity" is not a simulation concept.** The simulation reports physical quantities (impulse,
  normal speed, strike position); turning those into loudness is the audio module's job.
- **The UI observes at low rate.** The wind readout comes from the `WindController` (API data), not
  from the simulation each frame. A live gust meter, if wanted, is a `ValueNotifier` the game updates
  at about 5 Hz.
- **Settings produce immutable config objects** (`SimConfig`, `AudioConfig`) that are swapped
  atomically; geometry changes rebuild the chime, which is rare.

### Module boundaries

`chime_sim` is a separate package with no Flutter dependency, so the compiler enforces the first row.

| Module | May know | Must not know |
|---|---|---|
| `chime_sim` | math | Flutter, Flame, sensors, HTTP, audio |
| `game` (Flame) | sim, `SimInputs`, `CollisionSink` / `AudioEngine` interfaces | HTTP, sensors, widget state |
| `audio` | `CollisionEvent`, `AudioConfig` | Flame, physics internals |
| `weather` / `motion` | their platform APIs | Flame, sim internals |
| UI | controllers | sim internals |

### What runs when

| Cadence | Work |
|---|---|
| Every rendered frame (60/90/120 Hz) | Add `dt` to the accumulator and run k fixed steps; drain events to audio; render state interpolated between steps; push UI readouts at ≤5 Hz |
| Fixed step (120 Hz, 4 substeps) | Wind field, forces, constraints, collisions, events |
| Sensor event (~50 Hz) | Filter; write a `MotionSample` into `SimInputs` |
| Weather (every 30–60 min, or on resume if stale) | Fetch, cache, update `WindTarget` |
| Once per second | Interpolate the forecast timeline to get the current mean-wind target |
| User interaction | Settings → new config; drag → soft spring constraint on a body; swipe → gust |
| App lifecycle | **Pause:** stop sensors, fade and pause audio, cancel timers (Flame's `pauseWhenBackgrounded` only stops the loop). **Resume:** reset the accumulator and filters, refresh stale weather, fade audio in |

### Performance checklist

- **No allocations inside the physics step.** Positions, previous positions, velocities and inverse
  masses are structure-of-arrays `Float64List`s. The event ring is preallocated. `Paint` and `Path`
  objects are reused in `render`.
- **Protect the loop from hitches:** clamp frame `dt` to 0.1 s and run at most 12 fixed steps per frame.
- **Rendering:** cache the static background; avoid `saveLayer` and blur filters per frame (use
  pre-rendered glow sprites). iPhone 120 Hz requires `CADisableMinimumFrameDurationOnPhone` in
  Info.plist (already set).
- **Components:** one `ChimeRenderer` draws all bodies in depth order, instead of ~15 components
  re-sorting priorities every frame. It is rebuilt only when the chime preset changes.
- **Screen sizes:** the world is defined in meters; the camera scales the chime's bounding box to about
  65–75% of the safe-area height (or width, whichever is tighter). The sky fills the whole screen.
- **Battery:** sensors at `SensorInterval.gameInterval`, never `fastest`. Optional 60 fps cap as a
  battery saver on 120 Hz screens.

---

## B. Physics Model

### B1. Engine choice

| Option | Verdict |
|---|---|
| Flame collision detection | Not physics: per-frame overlap checks, no impulses or contact velocity. ❌ |
| Forge2D (`flame_forge2d`) | 2D only, so it can't model the rod ring. Joint chains get springy, resting contacts jitter, and wind drag must be hand-written anyway. Fallback only if the design stays 2D. |
| 3D physics ports in Dart | Niche and too heavy for ~15 bodies. ❌ |
| **Custom substepped XPBD** | ✅ ~500–700 lines. Stable, full control over damping and contacts, exact contact velocity for audio. |

Flame is appropriate as the loop, renderer, camera, particle system and overlay host — not as the
physics engine. A `CustomPainter` + `Ticker` would suffice for the MVP; Flame pays off in polish.

### B2. Bodies and forces

Units are SI (m, kg, s). Axes: x right, y up, z toward the viewer.

| Body | Model |
|---|---|
| Hook | Fixed point at the origin |
| Mount | 1 particle hanging from the hook on a rope. Translates but does not rotate (MVP). |
| Rods (5–8) | 2 particles joined by a rigid distance constraint, on a ring of radius R, each hung by a string. The particles sit at ±L/(2√3) from the rod's center (m/2 each) so the rod has the rotational inertia of a uniform tube (mL²/12); the rod's ends are linear extrapolations of the two particles. |
| Clapper | 1 particle (sphere, radius r_c) on a string from the mount's center |
| Sail | 1 particle below the clapper: large drag area, low mass. **It catches the wind and drives the clapper.** |

The ring is rotated so the camera looks between two rods; otherwise the front rod hides the clapper.

**Collisions need relative motion.** Four sources create it:

1. The sail and clapper respond ~3× more strongly to wind than the heavy rods (drag relative to mass).
2. Rods of different lengths have different natural frequencies (ω = √(g/L_eff)) and drift out of phase.
3. The wind fluctuates.
4. A gust reaches the upwind side of the chime slightly before the downwind side.

**Force on each particle:**

```
F_i = m_i·g_s  +  k_i·|u_i − v_i|·(u_i − v_i)  −  m_i·a_dev  −  c·m_i·v_i
      gravity     drag on relative velocity        phone accel.   small linear damping
k_i = ½·ρ·C_d·A_i   (ρ = 1.2 kg/m³)
```

- Drag on *relative* velocity gives aerodynamic damping for free.
- **Cross-flow drag for the tubes and the sail:** only the part of the relative wind across the
  body's axis pushes it (for the sail, the axis is its string). A sail blown up at an angle θ catches
  wind in proportion to cos²θ, so it can't fly flat out; without this, strong wind drove the clapper
  straight through the ring.
- The small linear damping term lets the chime settle in still air, because quadratic drag vanishes
  at low speed.

**Starting values (default preset):**

| Part | Value |
|---|---|
| Top rope | 0.12 m |
| Mount | Wood disc r = 0.07 m, 0.12 kg |
| Rods | Aluminium tube Ø18 mm, 1 mm wall (~0.144 kg/m), 5 cm strings, ring R = 4.6 cm (12 mm clearance to the clapper). Lengths from pitch: a free tube's frequency goes as 1/L², so **L_k = L_ref·√(f_ref / f_k)**. Longer rods look and sound lower. |
| Clapper | Ø50 mm, 35 g, centered at ~60% of the shortest rod's length. It must be wider than the opening between neighbouring tubes (36 mm here), or it escapes the ring. |
| Sail | 9 × 13 cm, 15 g, C_d 1.2, hanging clear below the longest rod |
| Restitution e | 0.65 (0.5 wood to 0.75 metal) |
| Linear damping | 0.05/s: a swing takes ~20 s to die away in still air |

Real units and real wind speeds land in a believable regime, so tuning happens in exposure,
turbulence and a few physical parameters rather than arbitrary constants. These values came out of
the Phase 2 tuning sweep (see the notes below).

### B3. Integration and collisions

Substepped XPBD (Macklin et al., *Small Steps in Physics Simulation*, 2019):

```
Δt = 1/120 s, n = 4 substeps, h = Δt/n
per substep:
  for each particle: v += h·F/m;  x_prev = x;  x += h·v
  solve each constraint once   (strings only when taut; rods rigid)
  detect + push apart contacts (record the normal velocity before the push)
  v = (x − x_prev)/h
  velocity pass: v_n ← −e·v_n_pre (restitution), tangential friction
  emit events for new contacts
```

**Distance constraint** between two points, where each point is a weighted sum of particles plus an
offset (this covers extrapolated rod ends and the mount's attachment points):

```
C = |p_a − p_b| − ℓ,   n = (p_a − p_b)/|p_a − p_b|
w_a = Σ α_i²·w_i  over the particles defining p_a   (w = inverse mass)
λ = −C / (w_a + w_b + α_c/h²)                          (α_c = compliance)
Δx_i = ±α_i·w_i·λ·n
```

Strings are one-sided: they are only enforced when C > 0, so a violent shake can let a rod jump.

**Clapper (sphere) vs. rod (capsule from p₀ to p₁):**

```
t = clamp(((c−p₀)·(p₁−p₀)) / |p₁−p₀|², 0, 1),   q = p₀ + t(p₁−p₀)
δ = r_c + r_r − |c−q|,   n = (c−q)/|c−q|         contact if δ > 0
w_q = Σ α_i(t)²·w_i        rod's effective inverse mass at the hit point
v_n = (v_c − v_q)·n         negative = approaching
J   = (1+e)·|v_n| / (w_c + w_q)     impulse, used by audio
```

Because w_q depends on t, a hit near the bottom of a rod spins it more than a hit near the top.

**Low-speed bounces.** Impacts slower than 1 cm/s don't bounce, so resting contact settles. (The
usual 2·g·h threshold, 4 cm/s here, swallowed most of a breeze's gentle taps and left the clapper
stuck to the tube.) After contacts, the constraints get a second pass so a clapper jammed against a
tube can't stretch its string.

**Events** are emitted only when all of these hold: the contact just began (with ~1 mm of separation
hysteresis before it can begin again), |v_n| is above ~2 cm/s, and at least 30 ms have passed since
that rod's last event. The clapper leaning on a rod in steady wind stays silent.

```dart
class CollisionEvent {       // preallocated, reused in the ring buffer
  int rodId;
  double impulse;            // J, N·s
  double normalSpeed;        // |v_n|, m/s
  double strikePos;          // t along the rod: 0 = top, 1 = bottom
  double glancing;           // 0 = square hit, 1 = grazing
  double simTime;
}
```

**Safety limits.** At a max speed of 6 m/s and 480 Hz substeps, the clapper moves 12.5 mm per
substep; clapper + rod radii are ~34 mm, so it cannot tunnel and no continuous collision detection is
needed. Speeds are clamped at 6 m/s. A non-finite state resets the chime to its rest pose. The renderer
draws `lerp(previousStep, currentStep, accumulator/Δt)`.

**Cage.** Tubes are free pendulums, so a clapper pressed hard between two of them can force them
apart and slip out of the ring. While the clapper is inside and level with the tubes, its center is
kept within the circle of tube axes at its own height. It only stops crossings (a clapper lifted out
over the top by a finger is left alone) and engages in under 1% of substeps below gale force.

**2.5D projection.** Orthographic, camera pitched ~10° upward (you look up at a hanging chime), weak
perspective scale `D/(D − depth)`, painter's order by depth, back rods slightly darkened.

**Camera framing.** A chime blown sideways is wide and short, and on a portrait screen it would leave
the frame. The camera frames a box from the hook to the chime's lowest point across its horizontal
extent: it pans to the box, zooms out (never in past the rest framing) if the box doesn't fit, and
centers it vertically. The box widens at once and narrows over ~4 s, so gust peaks stay in view
without the camera hunting. It holds still while a finger drags.

### B4. Wind: from API to force

**APIs**

| API | Key | Free limits | Commercial use | Notes |
|---|---|---|---|---|
| **Open-Meteo** | None | ~10k calls/day | ❌ free tier is non-commercial | Best developer experience: current, 15-minute and hourly wind and gusts, `wind_speed_unit=ms`, `is_day`, free geocoding |
| **MET Norway** Locationforecast | None (identifying User-Agent required) | Fair use; must cache and honour `Expires` | ✅ free with attribution | Gusts only in `/complete` |
| OpenWeatherMap | Yes | 60/min, 1M/month | ✅ | A key shipped in the app can be extracted; needs a proxy |
| Apple WeatherKit (REST) | JWT | 500k/month with developer membership | ✅ | Needs a server to sign tokens |

Use Open-Meteo while building; switch to MET Norway to ship commercially without paying. Both sit
behind a `WeatherProvider` interface. At scale, a small caching proxy (e.g. a Cloudflare Worker) can
round coordinates, cache for 15 minutes, hide keys and swap providers without an app update.

**Fetching.** Fetch a short forecast timeline rather than a single value, and interpolate along it:
fewer calls, smooth transitions, and hours of offline data.

```
/v1/forecast?latitude=48.14&longitude=11.58
  &current=wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day
  &minutely_15=wind_speed_10m,wind_direction_10m,wind_gusts_10m
  &forecast_minutely_15=16&wind_speed_unit=ms&timezone=auto
```

- Fetch on launch, and on resume if the data is more than 15 minutes old.
- Refresh every 30–60 minutes in the foreground, with ±10% jitter. Never fetch in the background.
- Round coordinates to 2 decimals (~1 km) for privacy and cache hits.

**Failures and offline**

- Source states: **live** (<30 min old) → **cached** (≤6 h, or while the timeline covers now) →
  **Ambient** (a built-in breeze, clearly labeled) → **Manual**.
- 8 s timeout; exponential backoff 30 s, 1, 2, 4… min, capped at 15 min, with jitter; retry on resume.
- Validate: speed 0–75 m/s, direction 0–360, nulls handled.
- **The simulation never waits for the network.**
- No `connectivity_plus`: "connected" doesn't mean the API is reachable, so just try and fall back.

**Smoothing**

- Interpolate linearly along the timeline.
- Inside the simulation, ease toward new targets with a time constant of ~30 s.
- **Interpolate direction as a vector (u, v), not an angle**, so 350° → 10° passes through 0°.

**Wind speed → force**

1. **Exposure:** U_p = E·U₁₀ with E = 0.4 (sheltered), 0.6 (garden), 0.85 (open). A porch is not a
   10 m mast. Exposed to users as a "Placement" setting.
2. **Soft cap:** U_e = U_c·tanh(U_p/U_c), U_c ≈ 8 m/s. Storms stay wild without breaking.
3. **User sensitivity** multiplier.
4. **Turbulence:** along the wind u = U + σ·n_along + gust(t); across it v = 0.75·σ·n_across;
   σ = I·U.
   - Each n is the sum of two Ornstein–Uhlenbeck processes (unit variance), for large eddies
     (T = 2.5 s, 65% of the variance) and small ones (T = 0.4 s, 35%). A single slow process put almost
     no energy near the chime's ~1 Hz swing, so light wind never rang it. Exact update at any step
     size: `n ← n·e^(−h/T) + √(1−e^(−2h/T))·N(0,1)`
   - Turbulence intensity I ≈ 0.15 (open) to 0.35 (sheltered), tied to exposure, plus up to 0.25 in
     light wind (fading with a 1.5 m/s scale): light winds are relatively gustier.
   - Gusts: Poisson arrivals at (G−1)·(2/15) per second (one per 15 s at G = 1.5), where G =
     gust/mean. Amplitude ≈ U(0.3, 1)·(G−1)·U, shaped as a 1−cos pulse over 2–5 s.
   - Direction meander: θ(t) = θ̄ + 10°·n(t) with T = 6 s.
5. **Gust delay across the chime:** particle i reads the noise at t − (x_i·ê)/U, so upwind rods feel a
   gust first (ring buffer of ~100 ms of noise history).
6. Apply the drag formula from B2.
7. Optional **"Calm days: silent / gentle"** setting: at 0.2 m/s a real chime is silent.

**Direction.** Meteorological direction is where the wind comes *from*, clockwise from north. Scene
frame: x = east, z = toward the viewer, camera facing north by default:
`u = U·(−sin θ, 0, cos θ)`. Later, subtract the compass heading ψ from θ so the chime blows the way the
real wind blows relative to where the user stands. In 3D, a wind blowing straight into the screen
still hits the far rods instead of doing nothing.

---

## C. Sensor Model

| Interaction | Signal | Source | Why |
|---|---|---|---|
| **Tilt** | Gravity in the device frame | Accelerometer, low-pass filtered (MVP); later OS-fused gravity (Android `TYPE_GRAVITY`, iOS `CMDeviceMotion.gravity`) | A gyroscope measures rotation rate and drifts; raw acceleration mixes tilt with motion, and OS fusion uses the gyro to separate them |
| **Shake / jolt** | Linear acceleration (gravity removed) | `sensors_plus` `userAccelerometerEventStream` (already OS-fused) | Exactly what a hook would feel |
| Twist | Rotation rate ω_z | Gyroscope | Optional kick; mostly useful inside OS fusion |
| Heading (later) | Compass | OS heading | Wind direction relative to where the user faces |

**Axes.** `sensors_plus` reports the Android convention on both platforms: x right, y toward the top
of the device, z out of the screen, in m/s². At rest the accelerometer reads the *opposite* of
gravity, so `g_dev = −lowpass(accel)`.

```
accel ──► 1€ filter ──► g_dev ──► γ = atan2(g_x, −g_y) ──► clamp ±40°, fade when flat ──► gravity direction
userAccel ─► dead zone ─► low-pass (τ≈25 ms) ─► soft clamp ─► a_dev (3D) ─► force −m·a_dev on every body
         └─► energy + reversal counter ─► shakeIntensity 0..1 (haptics, ambience swell)
```

**Tilt → gravity**

- `g_s = 9.81·(sin γ', −cos γ', 0)` with `γ' = clamp(γ, ±40°)·smoothstep(0.25, 0.5, |g_xy|/9.81)`.
- Gravity's magnitude stays fixed; only its direction comes from the sensor. When the phone lies flat,
  the in-screen component of gravity is meaningless, so the fade makes the chime hang straight while
  still responding to wind.
- Forward/backward tilt is ignored by the physics; it may drive camera parallax later.

**Smoothing**

- Time constants, not per-sample blend factors: `α = 1 − e^(−Δt/τ)` with Δt from event timestamps.
- Tilt uses the **1€ filter** (heavy smoothing when still, low lag when moving).
- Linear acceleration has a dead zone of 0.1–0.2 m/s² (table noise is ~0.03).
- If no event arrives for 200 ms, `a_dev` decays to zero.
- On resume, filters restart from the first new sample, not from zero.

**Shake detection** (for app-level reactions only; the continuous force already handles the physics)

- Energy `E ← average(|a|², τ=0.3 s)`.
- A shake needs ≥3 sign reversals on the dominant horizontal axis with |a| > 0.5 g within 800 ms, and
  √E > 0.4 g. It ends when √E < 0.2 g for 300 ms.
- Reversal counting rejects walking (vertical spikes of ~0.3 g without back-and-forth motion).

**Limits.** Soft-clamp `|a_dev| ≤ 1.5 g` via `a·a_max·tanh(|a|/a_max)/|a|`, after the sensitivity
multiplier (0.3–2×).

**Orientation.** Portrait is locked on phones. Sensor axes are device-fixed; landscape support would
require remapping by display rotation, which Flutter can't distinguish (left vs right) without native
code.

**Rate and permissions.** `SensorInterval.gameInterval` (20 ms). No motion permission is needed on
either platform at this rate.

---

## D. Audio Model

```
CollisionEvent ─► HitMapper (pure, testable) ─► VoiceAllocator ─► SoLoud voice
                  loudness, layer, brightness,     polyphony,       volume, pan,
                  detune, pan, variant             stealing, rules  playback speed
master bus: reverb (freeverb) ─► limiter ─► out
ambience: looped wind bed; volume and filter follow the live wind speed
```

**Collision → loudness**

```
s       = clamp( ln(J/J_min) / ln(J_max/J_min), 0, 1 )   // impulse spans ~100×; hearing is logarithmic
gain_dB = −30 + 30·s  ± 1.5 dB random
layer   = soft / medium / hard by s
bright  = low-pass cutoff 2 kHz → 12 kHz with s (or carried by the layer)
variant = strikePos near the end vs. the middle → "edge" / "center" sample
pan     = rod's screen x → ±0.35
detune  = ±6 cents random  (speed = 2^(cents/1200))
```

Strike position changes a tube's timbre, because modes with a node at the strike point aren't
excited; selecting the sample variant by `strikePos` captures that.

**Sample strategy**

| Option | Use? |
|---|---|
| One sample per rod | ❌ Too repetitive |
| **Multiple samples per rod**: 2–3 loudness layers × 2–3 alternates, never repeating the last | ✅ Core approach |
| Pitch shifting | ✅ Micro-detune only; never stretch one sample more than 2–3 semitones |
| Volume variation | ✅ From the impulse, plus small jitter |
| Procedural (modal) synthesis | ✅ Later, baked once at startup rather than in real time |
| Audio package | ✅ **`flutter_soloud`** (SoLoud via FFI) |
| Native audio APIs | ❌ Only if SoLoud fails a latency test on target devices. Real-time DSP, if ever needed, is C++ via FFI, not Swift + Kotlin |

**Preventing repetition:** loudness layers, alternates, strike-position variants, micro-detune, gain
jitter, pan by position, overlapping voices on the same rod (natural beating), a shared reverb and a
wind bed. The physics' irregular timing does half the work.

**Voice management**

- Raise SoLoud's active-voice limit from 16 to ~24–32.
- At most 3 voices per rod; a new strike starts a voice and fades the oldest over 30–80 ms (no clicks).
- Density limiter: after >10 hits in a second, raise the hit threshold and lower the gain slightly.
- Contact damping: if the clapper stays pressed against a ringing rod for >100 ms, fade that rod faster.

**Procedural samples (later).** A tube's sound is a sum of decaying partials; free-tube mode ratios are
~1 : 2.76 : 5.40 : 8.93, with higher modes decaying faster. Split each mode into two partials 0.1–0.3%
apart for the slow shimmer of real (imperfectly round) tubes. Add a 2–5 ms filtered-noise strike
transient. Generate in `Isolate.run` at startup and load from memory.

**Practical details**

- Memory: SoLoud stores decoded samples as float32, ~0.9 MB per 5 s mono sample; 5 rods × 2 layers ×
  2 alternates ≈ 18 MB. Ship `.ogg`.
- Latency: tune SoLoud's buffer size; target <50 ms end to end; test a low-end Android device early.
- Audio session (`audio_session`): iOS **playback** category (a sound-first app muted by the ringer
  switch looks broken), with a "mix with other audio" option; handle interruptions.
- Sample quality matters more than any engine trick.

---

## E. Project Structure

```
wind_chimes/
├── packages/chime_sim/            # PURE DART — no Flutter/Flame
│   ├── lib/src/
│   │   ├── config/     chime_config, presets, pitch → rod length
│   │   ├── core/       particles (SoA), links (constraints), simulation, fixed stepper
│   │   ├── collision/  sphere–capsule, contact cache
│   │   ├── wind/       wind_field, ou_noise, gust_scheduler        (Phase 2)
│   │   ├── inputs/     sim_inputs
│   │   └── events/     collision_event, event_ring
│   ├── test/           rest stability, bounded energy, no NaN, no chatter on resting contact
│   └── tool/harness.dart   # headless: hits/sec vs wind speed → CSV (Phase 2)
├── lib/
│   ├── main.dart
│   ├── app/            app widget, theme; later providers + lifecycle orchestrator
│   ├── game/           WindChimeGame (loop, event drain), debug stats
│   │   ├── render/     projection, sky, chime renderer
│   │   └── input/      drag → touch constraint
│   ├── weather/ location/ storage/ wind/ motion/ audio/ settings/  (Phases 2–6)
│   └── ui/             chime_screen, wind_chip, controls/ (sheet, dial, location), overlays/ (stats)
├── assets/audio/<preset>/<rod>_<layer>_<rr>.ogg, assets/audio/ambience/wind_loop.ogg
└── test/
```

---

## F. Packages

| Package | Phase | Why |
|---|---|---|
| `flame` | 0 | Loop, rendering, overlays, particles |
| `flutter_soloud` | 2 | Low-latency polyphonic audio, per-voice pitch/volume/pan, reverb and filters |
| `audio_session` | 3 | iOS category and mixing, interruptions, route changes; Android audio focus |
| `sensors_plus` | 4 | Accelerometer, linear acceleration, gyroscope, magnetometer |
| `geolocator` | 5 | Coarse location only |
| `http` | 5 | Weather calls |
| `flutter_riverpod` | 6, if needed | DI and app state. Not used so far: three controllers owned by the screen, with constructor injection, have been enough |
| `shared_preferences` | 5–6 | Settings and cached forecast |
| `wakelock_plus` | optional | Bedside "keep screen on" mode |
| `flame_test`, `mocktail` | as needed | Tests |

Not used: `flame_forge2d`, `flame_audio` / `audioplayers`, `just_audio`, `connectivity_plus`, Flame
collision detection.

---

## G. Implementation Roadmap

Audio moves earlier than in the original brief because physics is tuned by ear; touch moves earlier
because it is how the physics gets tested.

| Phase | Build | Done when |
|---|---|---|
| **0. Skeleton** | `chime_sim` package, `GameWidget`, portrait lock, debug overlay | App runs and shows step count and FPS |
| **1. Simulation core** | Particles, strings, rigid rods, ring layout, 2.5D renderer with interpolation, sphere–capsule contacts, contact cache, event ring, drag/fling | Flinging the clapper hits rods around the ring; events show sensible impulses; no NaNs over 10 simulated minutes; headless tests pass |
| **2. Wind + feel** | Wind field (mean + turbulence + gusts + delay), manual wind in the debug panel, placeholder "ding" through SoLoud, headless harness | Hit-rate curve in the target bands and it looks right |
| **3. Audio** | Sample bank, `HitMapper`, `VoiceAllocator`, variation, reverb + limiter, wind bed, `audio_session` | 5 minutes at a gentle breeze doesn't sound looped; no clicks; storms stay musical |
| **4. Motion** | Sensor source, processor (1€, tilt → gravity, inertial force, shake), sensitivity | Tilt swings the chime; shaking makes a flurry; stable flat on a table; walking only jiggles it |
| **5. Real weather** | Provider interface, Open-Meteo, coarse location / manual city, cache + staleness states, backoff, timeline, exposure | Airplane-mode launch still plays; live updates cause no audible jumps |
| **6. UI shell** | Controls sheet, settings persistence, first-run flow, auto-hiding overlays | Sound within ~1 s of opening; no permission prompt blocks it |
| **7. Polish** | Tube shading, sail cloth look, time-of-day sky, wind-carried particles, haptics during touch/shake, mount rotation, rod–rod clinks, low-end Android profiling, battery test | 60 fps on a mid-range Android; ≤~5%/h battery |

Phase 2 hit-rate targets, by reported 10 m wind in a garden with gust factor 1.5: 1 m/s ≤ 0.1
hits/s, 3 m/s 0.5–1.5, 6 m/s 1.5–3.5, 10 m/s 2–5. See [Phase 2 tuning notes](#phase-2-tuning-notes)
for why these differ from the first draft.

### UI / UX

- **Main screen:** full-bleed sky, chime slightly above center, no app bar.
- **Top left:** a quiet chip such as `11 km/h ↗ NW ●`; the dot shows the source (live, cached,
  ambient, manual). Tapping it shows gusts, location, "updated 5 min ago" and the Beaufort description.
- **Bottom:** a pill that pulls up into one sheet: mode (Live / Manual), manual speed slider with
  Beaufort detents and a direction dial, volume and ambience, motion sensitivity, placement
  (Sheltered / Garden / Open), and a chime preset carousel.
- **Settings:** a section at the bottom of the same sheet — units, location, haptics, attributions
  (MET Norway requires one).
- **Overlays** fade after ~4 s; tapping empty space brings them back. Touching the chime plays it.
- **First run:** start immediately in Ambient mode; the wind chip offers "Use live wind?", and only that
  asks for location.

---

### Phase 2 tuning notes

Measured with `dart run tool/harness.dart` in `packages/chime_sim` (garden, gust factor 1.5, 120 s per
speed):

| 10 m wind (m/s) | 1 | 2 | 3 | 4 | 6 | 10 | 14 | 20 |
|---|---|---|---|---|---|---|---|---|
| hits/s | 0 | 0.32 | 1.18 | 1.68 | 2.03 | 2.77 | 3.27 | 3.42 |
| clapper caged | 0% | 0% | 0% | 0% | 0% | 0.1% | 0.9% | 3% |

- **The first draft's targets were revised.** 1 m/s → 0.1–0.3 hits/s was not physically reachable: at
  1 m/s the chime feels ~0.6 m/s, which pushes the sail with ~0.5% of its weight, a ~1 mm sway against
  a 12 mm gap. Real chimes are essentially silent in light air too; the planned "Calm days: gentle"
  setting is the answer for users who want sound. At the top end a single clapper saturates around
  3 hits/s, so 10 m/s was 3–8 and is now 2–5. Rod–rod clinks (Phase 7) will add to it, and wind
  strength also shows in how hard tubes are struck: median impulse rises from 1.7 mN·s at 3 m/s to
  2.4 mN·s at 10 m/s.
- **What moved the curve:** cross-flow drag (stops the clapper wedging out in strong wind), two-scale
  turbulence and light-wind gustiness (make 2–3 m/s ring), a heavier clapper and sail (35 g, 15 g) and
  a smaller gap (12 mm).
- **Tests pin the curve:** `test/wind_response_test.dart` fails if a change moves any target speed out
  of its band, if stronger wind stops striking harder, or if the clapper leaves the ring in a gale.

**Placeholder audio.** Until recorded samples arrive (Phase 3), each tube's tone is synthesized at
startup from the tube's physics: decaying partials at the free-tube mode ratios, higher modes dying
faster, each split into two close frequencies for shimmer, plus a strike click. `HitMapper` maps the
impulse to loudness logarithmically (−30 dB to 0 dB), pans by the tube's place on the ring and adds
±6 cents of detune and ±1.5 dB of jitter. On web, audio starts on the first touch (browser autoplay
rule).

### Phase 3 audio notes

**Sample bank, synthesized from the tube physics** (`lib/audio/tube_synth.dart`, `tube_bank.dart`).
There are no recordings yet, so every sample is generated at startup in a background isolate
(~0.2 s): per tube, 2 strike hardnesses × 2 strike positions × 2 takes = 40 samples of 5 s at
32 kHz (12.8 MB as WAV, ~26 MB once decoded by SoLoud), plus an 8 s seamless wind loop.

- **Hardness** is the strike's contact time (0.6 ms soft, 0.25 ms hard); the half-sine pulse
  spectrum `|cos(πfτ) / (1 − 4f²τ²)|` shapes which partials a strike reaches, so hard hits are
  brighter.
- **Strike position** weights each mode by the free–free mode shape at the contact point. The
  middle (50%) cannot excite mode 2; off-center (62%) brings it in. The simulation's hits land at
  45–62%, so both variants get used.
- **Takes** differ in partial phases, the shimmer split and a hint of inharmonicity (±0.2% on
  overtones only, so the tuning holds).
- The layout is data (`TubeBankLayout`), so recorded samples can later replace synthesis without
  touching the mapper or allocator.

**Hit mapping** (`hit_mapper.dart`): intensity → dB as before; layer by intensity with a random
overlap so the soft/hard switch is never audible, glancing blows darker; position variant nearest
the contact point; takes chosen so a tube never plays the same sample twice running.

**Voice allocation** (`voice_allocator.dart`, pure Dart, tested with a fake output):
- ≤3 voices per tube, ≤24 overall; the oldest is stolen with a 60 ms fade, never cut.
- Voice lifetimes come from sample length ÷ playback speed: nothing is polled from the engine.
- Density limiter above 10 hits/s: hits below 0.2 intensity are skipped, the rest lose up to 6 dB.
- Contact damping: when the clapper *presses* on a tube (actual contact, not the 1 mm re-strike
  hysteresis) for 100 ms, that tube's voices fade to 35% over 0.4 s. Measured over 5 minutes, 22% of
  voices get damped at 3 m/s and 43% at 6 m/s, where steady wind leans the clapper on the downwind
  tubes.

**Mix:** global freeverb (room 0.6, damp 0.5, wet 0.25), then a limiter (−3 dB threshold, −1 dB
ceiling) last. Per-sound filters don't work on web, which is why brightness is baked into layers
rather than filtered live.

**Wind bed** (`wind_bed.dart`): the loop's volume and playback speed follow the instantaneous wind
at the chime (silent below 0.3 m/s, up to −9 dB and 1.3× speed), so gusts are heard arriving.

**Session and lifecycle:** iOS playback category with mix-with-others (not silenced by the ringer
switch; music can play alongside); Android plays as media without taking audio focus. Interruptions
and the app leaving the screen fade out over 250 ms and stop the audio device; returning restarts
it and fades in over 800 ms. Background playback is not in the MVP.

**Soak results** (5 simulated minutes, real impacts through mapper and allocator): at 3 m/s, 346
voices, no tube ever repeated a sample back to back, peak 9 voices; in a 20 m/s gale, peak 15 of 24,
no hits skipped. Every steal is a fade of ≥ 30 ms.

### Phase 4 motion notes

`lib/motion/`: `MotionSource` (sensors_plus at 50 Hz, replaceable by a native fused-motion plugin),
`MotionProcessor` (pure, tested with synthetic sensor data), `ShakeDetector`, `OneEuroFilter`, and
`MotionController`, which feeds readings to the processor as they arrive and writes tilt and
acceleration into `SimInputs` once per frame, before the physics steps.

- **Tilt:** accelerometer minus the OS's linear acceleration (paired within 0.1 s), so shaking
  doesn't read as tilting; 1€ filter (0.8 Hz at rest, β = 1 in g units); roll clamped to ±40°;
  faded out as the phone lies flat or turns upside down. Tested: 20° right-edge-down reads 20°,
  also when the phone is leaned back 50° as people hold it; ±0.3 m/s² noise moves it < 1.5°.
- **Push:** soft dead zone of 0.15 m/s², 25 ms smoothing, × sensitivity (0–2), then a soft knee
  that passes pushes unchanged up to 0.9 g and compresses toward 1.5 g. Fades out if readings stop
  for 0.2 s.
- **No gyroscope:** a phone without the OS's linear-acceleration sensor (the stream errors with
  `NO_SENSOR`, or stays silent for 1 s) derives it from the accelerometer minus a slow gravity
  estimate (0.6 s, trusting readings less the further their magnitude is from 1 g), and takes tilt
  from that estimate. Tilt then follows in about half a second.
- **Shake detection:** ≥3 sideways reversals over 0.5 g within 0.8 s and RMS > 0.4 g; ends about
  1.2 s after shaking stops. Walking and single bumps don't count. Reported to the UI; haptics
  will use it in Phase 7.
- **Lifecycle:** sensors stop when the app is hidden and restart when it returns; without sensors
  (desktop, most desktop browsers) motion reports "no motion sensors" and the chime hangs straight.
- **Physics checks** (`packages/chime_sim/test/motion_response_test.dart`): a 20° gravity tilt makes
  the chime hang at 20 ± 2°; a 3 s side-to-side shake with no wind produces a flurry of ≥5 hits;
  10 s of walking-like vertical bobbing produces ≤2.
- **Emulator check:** injected accelerometer values tilted the chime 20° and a synthetic shake read
  "push 7.2 m/s², shaking 51%" with 4–5 hits/s. During that synthetic shake tilt briefly read 25°:
  instant ±9 m/s² steps with no matching gyroscope rotation fool the emulator's sensor fusion. If
  tilt wobbles while shaking a real phone, the fix is the native fused-motion plugin.

### Phase 5 weather notes

`lib/weather/`: `WeatherProvider` (interface), `OpenMeteoProvider`, `WindTimeline`, `WeatherCache`,
`Backoff`, `AmbientWind`. `lib/location/`: `LocationChoice` (the phone's location or a searched
`Place`), `GeolocatorLocationService`, `OpenMeteoPlaceSearch`. `lib/storage/`: `KeyValueStore`
(shared preferences; in memory for tests). `lib/wind/`: `WindController`, which picks the wind and
writes it into `SimInputs`, and `WindServices`, the bundle tests replace.

- **Fetch:** one Open-Meteo call returns 24 h of 15-minute steps (wind speed, direction, gusts in
  m/s, Unix times) for coordinates rounded to 2 decimals. Steps with missing or implausible values
  are skipped; a missing gust is 1.5 × the mean. 8 s timeout. Any failure to get an answer is
  "offline"; an error status or unusable body is a "service error".
- **Timeline:** speed and gust interpolated linearly, direction as a speed-weighted vector, held at
  the ends for up to 15 minutes. The controller writes it into `SimInputs` once a second.
- **Source states:** *live* while the forecast is under 40 minutes old (refreshes are every
  30 minutes ± 10%, so a normal refresh never shows "cached"), then *cached* while it still covers
  now (up to 24 h), then the *ambient* breeze. *Manual* mode plays the sliders and fetches nothing.
  A cached forecast is used only for the location it was fetched for.
- **Ambient breeze:** a pure function of the clock: 2.6 m/s ± 0.9 over periods of 3–7 minutes, from
  about 255° ± 25°, gust factor 1.5. It plays on first run (no location yet) and whenever there's
  no usable forecast.
- **Refresh and retry:** fetch on launch; every 30 minutes (± 10%) in the foreground; on return to
  the app if the data is over 15 minutes old or the last attempt failed. Failures back off 30 s, 1,
  2, 4, 8, 15 minutes (± 20%). Nothing is fetched while the app is hidden. A result for a location
  the user has since changed is dropped.
- **No audible jumps:** the first wind after launch is applied at once (`windResponseTime` 0 for
  1 s), so a cached forecast plays from the first frame. After that, forecast changes ease in over
  30 s, and changes the user makes (mode, placement, location) over 5 s for the next 10 s.
  `wind_response_test.dart` checks it in the physics: a forecast jump from 3 to 10 m/s leaves the
  hits in the next 5 s at the level of the 40 s before, while the same jump applied at once more
  than doubles them. (Measured: 22 vs 20 hits eased, 42 vs 20 at once, over three seeds.)
- **Location:** permission is asked only when the user taps "Mine"; a launch never prompts. Coarse
  only: Android declares `ACCESS_COARSE_LOCATION` alone, iOS sets
  `NSLocationDefaultAccuracyReduced`. A fix under 30 minutes old is reused. On Android, an app with
  only coarse permission can't switch on GPS, so its fix comes from network location ("Location
  Accuracy"). When that is off, Play Services' location client shows a dialog offering to turn it
  on. So a tap on "Mine" uses Play Services (the dialog is a fair answer to "use my location"), and
  launches and refreshes use the platform location manager, which never shows a dialog. With no
  fix on a refresh, the last good position is reused. Declining the permission keeps the previous
  choice. Otherwise the user can search a city (Open-Meteo geocoding).
- **Platform setup:** Android `INTERNET` in the main manifest (release builds need it); macOS
  `network.client` and location entitlements plus usage strings (not built: no Xcode here).
- **Checked on the web** (Playwright, real API): first launch plays the breeze without any request;
  "Mine" with a Berlin position gave live wind in ~1 s; a reload with the API blocked played the
  cached forecast from the first frame; the city search lists same-named places with region and
  country, fails politely offline, and a pick plays that city's wind.
- **Checked on the Android emulator** (a separate emulator, Android 16): the permission prompt offers
  approximate location only; the chime keeps playing behind it. After "Turn on" for Location
  Accuracy, live wind arrived (4.9 m/s NW, gusts 11.2). The very first fetch on the freshly booted
  emulator failed and the 30 s retry succeeded. An airplane-mode relaunch played the cached forecast
  from the first frame (2 hits/s) and showed "offline, retrying in 11 s".
- **Not done yet:** MET Norway provider (for a commercial release; needs an identifying
  User-Agent, which browsers don't allow, so web would stay on Open-Meteo or go through a proxy);
  persisting mode and placement (Phase 6 settings); Beaufort wording and the wind chip (Phase 6).

### Phase 6 UI notes

`lib/settings/`: `AppSettings` (everything the user sets, as JSON that tolerates missing and bad
values) and `SettingsController` (saves 500 ms after the last change, and at once when the app is
hidden). `lib/ui/`: `WindChip` with the first-run `LiveWindOffer`, `controls/ControlsSheet`,
`DirectionDial`, `LocationSection`, `OverlayVisibility`, `WindText` (units, Beaufort, status words).
`lib/app/AppServices` bundles weather, location, place search, storage and motion for tests.

- **Settings before the first frame:** `main` awaits the saved settings (a few milliseconds) so the
  app never opens in the wrong mode and flips. Units default by region: mph in the US, UK, Liberia
  and Myanmar, km/h elsewhere.
- **Wind chip** (top left): speed in the chosen units, an arrow the way the wind blows, the compass
  point it comes from, a dot for the source. Tapped: Beaufort name, gusts, source, place and age,
  any problem and the attribution.
- **First run:** the ambient breeze plays at once and the chip asks "Hear the real wind where you
  are?": *Use my location* (the only thing that ever shows the permission prompt), *Pick a city*
  (opens the sheet with the search focused) or *Not now*. A declined permission explains itself
  and points to picking a city. The answer is remembered; choosing a location in the sheet counts.
- **Controls sheet:** a pill at the bottom that pulls or taps open to 60% and 92% of the screen,
  morphing from pill to sheet by clipping (layout stays full width, touches outside the pill reach
  the chime). Collapsed, only the pill is built, so hidden controls never reach a screen reader.
  Sections: *Wind* (Live: location and status; Manual: speed on a Beaufort slider in quarter-force
  steps, B = (v / 0.836)^(2/3), a direction dial in 5° steps that claims its drag so it never
  scrolls the sheet, gustiness), *Placement* (with the share of the reported wind it feels),
  *Sound* (volume with gain = v², wind sound level), *Motion* (live status, shaking sensitivity,
  tilt), *Settings* (units, stats panel, attribution and a note on location privacy). No preset
  carousel (one preset in the MVP) and no haptics switch (Phase 7).
- **Chime above the sheet:** the projection has a visible height; an open sheet shrinks and
  re-centres the chime into the space above it (never less than 40% of the screen), eased like the
  rest of the camera.
- **Fading overlays:** the chip and pill fade after 4 s without interaction (10 s while the offer
  waits) and stay while the sheet or chip details are open. A tap that misses every body is an
  "empty sky" tap: it toggles them, and closes an open sheet or chip first. A tap where a faded
  overlay was only brings it back.
- **Already moving:** 6 s of wind are simulated (impacts discarded) before the chime is first seen,
  so it opens mid-swing rather than dead still.
- **Sound within ~1 s:** the sample bank now builds in two steps: one sample per tube (the soft,
  centre-struck one) plus the wind loop first, a seventh of the synthesis, then the other 35 in the
  background while the first ones stand in. On the Android emulator: audio ready 140–220 ms after it
  starts (was 720–1080 ms, 80% of it synthesis) and the full bank ~0.7 s; process start to audio
  ready 1.07–1.11 s (was 1.6–2.9 s), most of it the engine starting on a software-rendered
  emulator. Browsers only allow audio after a gesture, so the web build shows "Tap anywhere for
  sound" until then. No permission prompt appears on launch.
- **Bugs found on the way:** Flame calls `onGameResize` whenever the widget above the game rebuilds,
  so every settings change refitted the camera and snapped it back to rest (this also hit the
  earlier debug panels' sliders). The game now refits only on a real size change, and the
  `GameWidget` is built once. The controls header lacked a semantic tap action (TalkBack couldn't
  open the sheet).
- **Checked:** widget tests on a phone-sized screen (offer, permission declined, fading and
  tap-to-show, sheet, manual wind, placement and units reaching the chip, settings restored on the
  first frame); on the web (first run, fading, sheet with the chime reframed, dial and Beaufort
  slider); on the Android emulator (first run, *Pick a city* with the keyboard, live Oslo wind, a
  relaunch that remembered everything, chip details, launch timings).

### Phase 7 polish notes

**Mount twist.** The mount now turns about its rope. `Yaw` holds the angle; the tubes hang from
`PointRef.onBody` points whose offsets turn with it, and a string correction applied at such a point
is shared between moving the mount and turning it, by its lever arm: the point's generalized
inverse mass along n gains (r × n)²_y / I, and the turn changes by (r × Δ)_y / I (I = ½·m·r² of the
disc). The twisted rope pulls back with 4·10⁻⁴ N·m/rad and damps with 3·10⁻⁴ N·m·s/rad, soft as a
real cord: pushing a tube sideways turns the whole chime. In wind, the tubes' unequal lengths and
the gusts' delay across the ring turn it to and fro: RMS 1° at 1 m/s, 5° at 3, 10° at 6, 13° at 10,
15° at 20 (peaks to ~45° in a gale). Hit rates stay in their bands (3 m/s: 1.23/s; 6: 2.24; 10:
2.72). Energy includes the turn (½Iω² + ½kθ²).

**Tube against tube.** `RodContacts` handles the ten pairs of tubes as capsules: closest points
of the two axes (Ericson §5.1.9), push apart weighted by where on each tube the contact is,
restitution 0.6 and friction in the velocity pass, a contact cache with hysteresis, per-pair
retrigger. A knock is reported twice, once per tube (`CollisionEvent.otherRodId`), so audio, the
strike flash and stats need nothing new. Harness (180 s per speed): clinks start near 4 m/s
(0.02/s) and reach 0.3/s at 10 m/s and 0.57/s at 20. Tested: a knock is reported for both tubes;
tubes pushed together never pass through each other and lean together silently. The harness now
counts clinks apart from clapper hits and reports the twist. No allocation in either solver.

**Clinks sound.** A knock between tubes plays both tubes, brighter than a clapper hit (+0.4 in
brightness: a brief metal contact) and 6 dB quieter each.

**Sky and light.** `SkyModel` works out the sun's elevation (NOAA's low-accuracy equations, good to
a fraction of a degree) where the chime is: the chosen place, the phone's last fix, or a guess from
the time zone (standard offset for the longitude, daylight saving's direction for the hemisphere).
Palettes are keyed to elevation: night (−18°, full stars), dusk (−8°, the old look), twilight (−2°),
golden hour (+3°, warm horizon), day (+12°). Rechecked every 20 s; shaders rebuilt only when it
changes. 90 stars in three twinkle groups (`drawRawPoints`). "Sky follows the time of day" can be
switched off (always dusk). With stats on, a slider previews the sky at any hour (local solar time at
the chime's place).

**Tube shading.** The metal reflects the sky: edges take the upper sky's colour, the lower half the
horizon's; everything dims at night and brightens a little by day. A soft glint slides across each
tube as the chime turns (its side of the ring against the light) and as the tube tilts.

**Sail.** Drawn as cloth on a wooden dowel: sides bow and the hem ripples, more and faster as the
wind rises (the flutter phase is accumulated, so a change of wind never jumps it), soft vertical
folds, a stitched hem line. No cloth simulation: the sail is still one body in the physics.

**Mount.** Eyelets at the tubes' attachment points and grain marks on the underside turn with the
mount, so its twist is visible.

**Wind motes.** 40 specks drift behind the chime on the same wind, nearer ones bigger, brighter
and faster (parallax), re-entering from upwind; they fade in calm air and speed up in gusts, just as
the chime answers them. Arrays only; one circle each per frame.

**Haptics.** `ChimeHaptics` taps the phone on strikes only while you are playing the chime:
dragging it, for 1 s after letting go (a fling's hits come after the finger leaves), or while
shaking. Light, medium or heavy by the hit's intensity, at most one tap per 60 ms. The wind alone
never buzzes the phone. Setting: "Vibrate when you play it".

**Profiling.** The stats panel now shows the engine's build and raster times per frame, the slowest
frame, and physics time per frame. On the Android emulator (software-rendered, so raster times stand
for a GPU at its worst): build 0.5 ms and physics 0.05–0.26 ms per frame in a breeze and in a gale,
raster ~26 ms. Per thread: raster 55–58 % of a core, the UI thread (Dart: physics, drawing
commands) ~5 %, audio < 1 %. On desktop Chrome: build 0.5 ms, raster 0.4–0.6 ms. The Dart side is
far inside budget; whether a real mid-range GPU holds 60 fps needs a phone (raster times appear in
the stats panel of a profile build).

**Battery.** `tool/battery_check.sh [minutes] [serial]` resets Android's battery statistics, runs
the app with the screen on, and reports the drain Android attributes to the app (mAh, and % an hour
of the phone's capacity) along with the level drop. Over wireless debugging the level drop is real;
over USB only the estimate is. Checked for correctness on the emulator (whose battery is simulated,
so its numbers mean nothing).

**Fixed on the way.** The glint gradient lacked stops (a crash in paint); the collapsed pill could
keep a 12 px scroll after the open sheet was scrolled (its bottom padding made it scrollable), which
hid the handle; a widget test depended on the clock-driven ambient breeze.

**Not done.** A frame-rate cap for 120 Hz screens needs the platform's display-mode API; left until
real-device measurements say it is needed.

## H. MVP Definition

The MVP proves one thing: *a physically simulated chime, driven by real wind and your hands, sounds
good enough to leave running.*

**In:** one preset (5 aluminium rods, pentatonic, clapper, sail, mount on rope), 3D simulation with
2.5D rendering, wind synthesizer + Open-Meteo timeline + coarse location or manual city + cached and
Ambient fallbacks + Manual mode, tilt and shake via `sensors_plus`, drag and fling, SoLoud with
2 layers × 2 alternates per rod plus detune/gain/pan/reverb/wind bed, one screen (wind chip, controls
sheet, hidden debug panel), portrait, foreground only.

**Deliberately out:** presets, chime builder and materials; procedural audio; compass and parallax;
cloth simulation; background audio and sleep timer; tablet and landscape layouts; native plugins,
proxy server, accounts, analytics; Forge2D; isolates. (Mount rotation, rod–rod collisions, haptics,
wind particles and time-of-day lighting, first listed here, came in with Phase 7.)

---

## I. Future Enhancements

- **"True window" mode:** compass-accurate wind direction plus forward/backward tilt as camera parallax.
- **Real-time modal synthesis** (C++ via FFI): timbre that varies continuously with strike position and
  force, contact damping, sympathetic resonance between rods.
- **Chime builder:** rod count, scale (pentatonic, Aeolian, Corinthian bells, custom), material; rod
  lengths derived from pitch.
- **Weather-reactive scene:** rain (drops ticking the rods), snow, night sky from `is_day`,
  thunderstorm gust fronts.
- **"Blow on the mic"** to make a gust.
- **Listen elsewhere:** pick a place on a world map and hear its wind now; replay historical storms.
- **Sleep mode:** background playback, timer, lock-screen controls.
- Multiple chimes in one spatial scene; head-tracked spatial audio.
- Record/replay of all simulation inputs, for bug reports and shareable audio clips.

---

## Native code

Start with none. Add only when a package proves insufficient:

- A fused-motion plugin (`CMDeviceMotion` / `TYPE_GRAVITY` + linear acceleration in one timestamped
  stream), ~150 lines per platform, if filtered `sensors_plus` data lags or jitters.
- Compass heading.
- Display rotation, if landscape is ever supported.
- Background audio plumbing (iOS background audio mode, Android media foreground service).
- Core Haptics, if `HapticFeedback`'s presets feel too coarse.
- Real-time DSP: C++ via FFI, not platform code.

---

## Hardest parts and how to approach them

1. **Tuning the feel (biggest risk).** Too many hits is noise; too few and the app feels dead. Rod
   lengths, masses, the gap, exposure, turbulence and restitution all interact. Approach: headless
   harness with target hit-rate bands, debug sliders bound live to `SimConfig`, recorded inputs so
   tuning runs against the same gust every time, and sound on from Phase 2.
2. **Audio that doesn't sound looped.** Engine tricks can't save weak samples. Get good recordings or
   baked samples by Phase 3; judge them in 10-minute listening sessions, not single hits.
3. **Contacts.** Resting contacts, double hits and jitter produce machine-gun sound. Contact cache with
   hysteresis, minimum approach speed, per-rod retrigger limit, restitution in the velocity pass.
   Tested: a clapper held against a rod produces no further events after it settles.
4. **Separating tilt from movement.** Raw acceleration can't distinguish tilting from accelerating;
   filtering trades lag for jitter. Start with `sensors_plus` + 1€; fall back to a small native
   fused-motion plugin. Handle the flat phone explicitly.
5. **Audio lifecycle and latency.** Calls, Siri, headphone disconnects, clicks on resume, low-end
   Android latency. One lifecycle orchestrator using `audio_session`, tested on a device matrix early.
6. **Making sparse weather data feel alive.** Drive the chime physics, the ambience and the particles
   from the same wind field, so a gust is heard and seen just before the chime answers.
