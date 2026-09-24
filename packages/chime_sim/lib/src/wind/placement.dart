/// Where the chime hangs. A porch is not a 10 m weather mast: this scales the reported wind down
/// to what the chime feels, and sets how gusty it is.
enum Placement {
  sheltered(exposure: 0.4, turbulence: 0.35),
  garden(exposure: 0.6, turbulence: 0.25),
  open(exposure: 0.85, turbulence: 0.15);

  const Placement({required this.exposure, required this.turbulence});

  /// Mean wind at the chime divided by the reported 10 m wind.
  final double exposure;

  /// Turbulence intensity: standard deviation of wind speed over its mean.
  final double turbulence;
}
