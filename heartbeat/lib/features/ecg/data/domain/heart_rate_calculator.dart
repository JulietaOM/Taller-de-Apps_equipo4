/// Calcula frecuencia cardiaca y zona a partir de muestras ADC del ESP32.
///
/// La señal del ESP32 tiene estas características conocidas:
/// - Rango ADC: 0–4095 (12 bits)
/// - Pico R mapeado: ~3700–3900
/// - Baseline: ~2000 (normalizado al centro)
/// - Sample rate: 250 Hz
/// - Periodo refractario fisiológico: ~200 ms
///
/// Algoritmo:
/// 1. Umbral fijo al 75% del rango ADC conocido (evita calibración lenta)
/// 2. Detección de máximo local con periodo refractario
/// 3. BPM por promedio móvil de intervalos RR
/// 4. Clasificación de zona según % de FCmáx (220 − edad)
class HeartRateCalculator {
  HeartRateCalculator({
    required this.sampleRateHz,
    this.age = 25,
  }) {
    _maxHr             = 220 - age;
    _refractorySamples = (sampleRateHz * _refractoryMs / 1000).round();
  }

  final int sampleRateHz;
  final int age;

  // ── Parámetros ────────────────────────────────────────────────────
  static const double _refractoryMs  = 200;  // ms mínimos entre picos R
  static const int    _rrWindowSize  = 6;    // picos para promedio RR
  static const double _peakThreshold = 2800; // umbral ADC para pico R
  //   La señal del ESP32: baseline ~2000, pico R ~3800
  //   2800 queda bien por encima del ruido y por debajo del pico

  late final int _maxHr;
  late final int _refractorySamples;

  // Estado interno
  double _prev2         = 0;
  double _prev1         = 0;
  int    _sampleCount   = 0;
  int    _lastPeakIdx   = -1;

  final List<int> _rrIntervals = [];

  int           _bpm  = 0;
  HeartRateZone _zone = HeartRateZone.none;

  int           get bpm  => _bpm;
  HeartRateZone get zone => _zone;

  // ── API pública ───────────────────────────────────────────────────

  /// Agrega una muestra. Devuelve true si se actualizó el BPM.
  bool addSample(double sample) {
    _sampleCount++;

    // Necesita 3 muestras para máximo local
    if (_sampleCount < 3) {
      _prev2 = _prev1;
      _prev1 = sample;
      return false;
    }

    // Máximo local: prev1 es mayor que sus vecinos y supera el umbral
    final isPeak = _prev1 > _peakThreshold &&
        _prev1 > _prev2 &&
        _prev1 >= sample;

    _prev2 = _prev1;
    _prev1 = sample;

    if (!isPeak) return false;

    final peakIdx = _sampleCount - 1;

    // Periodo refractario
    if (_lastPeakIdx >= 0 &&
        peakIdx - _lastPeakIdx < _refractorySamples) {
      return false;
    }

    // Calcula intervalo RR
    if (_lastPeakIdx >= 0) {
      final rr = peakIdx - _lastPeakIdx;

      // Sanity check: RR entre 300 ms y 2000 ms (30–200 bpm)
      final rrMs = rr / sampleRateHz * 1000;
      if (rrMs >= 300 && rrMs <= 2000) {
        _rrIntervals.add(rr);
        if (_rrIntervals.length > _rrWindowSize) {
          _rrIntervals.removeAt(0);
        }
        _updateBpm();
      }
    }

    _lastPeakIdx = peakIdx;
    return _bpm > 0;
  }

  void reset() {
    _prev2        = 0;
    _prev1        = 0;
    _sampleCount  = 0;
    _lastPeakIdx  = -1;
    _rrIntervals.clear();
    _bpm  = 0;
    _zone = HeartRateZone.none;
  }

  // ── Privados ──────────────────────────────────────────────────────

  void _updateBpm() {
    if (_rrIntervals.isEmpty) return;

    final avgRr = _rrIntervals.reduce((a, b) => a + b) / _rrIntervals.length;
    final newBpm = (sampleRateHz * 60 / avgRr).round();

    if (newBpm < 30 || newBpm > 220) return;

    _bpm  = newBpm;
    _zone = _classifyZone(_bpm);
  }

  HeartRateZone _classifyZone(int bpm) {
    final pct = bpm / _maxHr * 100;

    if (pct < 50) return HeartRateZone.rest;
    if (pct < 60) return HeartRateZone.zone1;
    if (pct < 70) return HeartRateZone.zone2;
    if (pct < 80) return HeartRateZone.zone3;
    if (pct < 90) return HeartRateZone.zone4;
    return          HeartRateZone.zone5;
  }
}

// ── Zonas ─────────────────────────────────────────────────────────────────────

enum HeartRateZone {
  none,
  rest,   // < 50% FCmáx
  zone1,  // 50–60%
  zone2,  // 60–70%
  zone3,  // 70–80%
  zone4,  // 80–90%
  zone5,  // 90–100%
}

extension HeartRateZoneExt on HeartRateZone {
  String get label {
    switch (this) {
      case HeartRateZone.none:  return '—';
      case HeartRateZone.rest:  return 'Reposo';
      case HeartRateZone.zone1: return 'Zona 1 — Muy ligero';
      case HeartRateZone.zone2: return 'Zona 2 — Quema de grasa';
      case HeartRateZone.zone3: return 'Zona 3 — Aeróbico';
      case HeartRateZone.zone4: return 'Zona 4 — Anaeróbico';
      case HeartRateZone.zone5: return 'Zona 5 — Máximo esfuerzo';
    }
  }

  int get colorValue {
    switch (this) {
      case HeartRateZone.none:  return 0xFF9E9E9E;
      case HeartRateZone.rest:  return 0xFF64B5F6;
      case HeartRateZone.zone1: return 0xFF81C784;
      case HeartRateZone.zone2: return 0xFFFFD54F;
      case HeartRateZone.zone3: return 0xFFFFB74D;
      case HeartRateZone.zone4: return 0xFFFF7043;
      case HeartRateZone.zone5: return 0xFFE53935;
    }
  }
}
