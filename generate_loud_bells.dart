import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

void writeWav(String filename, List<double> freqs, List<double> delays, List<double> decays, List<double> durations, double fmAmount, double modRatio, {bool extraLoud = true}) {
  const sampleRate = 44100;
  const totalDuration = 2.5;
  final totalSamples = (sampleRate * totalDuration).toInt();
  final audioData = Float32List(totalSamples);
  
  for (int i = 0; i < freqs.length; i++) {
    final freq = freqs[i];
    final decay = decays[i];
    final delaySamples = (delays[i] * sampleRate).toInt();
    
    for (int j = 0; j < (durations[i] * sampleRate).toInt(); j++) {
      final idx = delaySamples + j;
      if (idx < totalSamples) {
        final t = j / sampleRate;
        final carrier = 2 * pi * freq * t;
        // Inharmonic modulator for metallic bell sound
        final modulator = sin(2 * pi * (freq * modRatio) * t) * fmAmount;
        // Add a secondary higher harmonic for that "ping" attack
        final ping = sin(2 * pi * (freq * 3.14) * t) * exp(-decay * 4 * t) * 0.5;
        
        final tone = sin(carrier + modulator) + ping;
        // Sharp attack, exponential decay
        final envelope = exp(-decay * t);
        audioData[idx] += tone * envelope;
      }
    }
  }
  
  double maxVal = 0.0;
  for (int i = 0; i < totalSamples; i++) {
    if (audioData[i].abs() > maxVal) {
      maxVal = audioData[i].abs();
    }
  }
  
  final int16Data = Int16List(totalSamples);
  for (int i = 0; i < totalSamples; i++) {
    double val = maxVal > 0 ? (audioData[i] / maxVal) : 0;
    
    // Apply compression/clipping to make it extremely loud and bold
    if (extraLoud) {
      val = val * 2.0; // Boost
      if (val > 1.0) val = 1.0;
      if (val < -1.0) val = -1.0;
    }
    
    int16Data[i] = (val * 32767).toInt();
  }
  
  final file = File(filename);
  final byteData = ByteData(44 + int16Data.lengthInBytes);
  
  byteData.setUint32(0, 0x52494646, Endian.big); // "RIFF"
  byteData.setUint32(4, 36 + int16Data.lengthInBytes, Endian.little);
  byteData.setUint32(8, 0x57415645, Endian.big); // "WAVE"
  byteData.setUint32(12, 0x666D7420, Endian.big); // "fmt "
  byteData.setUint32(16, 16, Endian.little);
  byteData.setUint16(20, 1, Endian.little);
  byteData.setUint16(22, 1, Endian.little);
  byteData.setUint32(24, sampleRate, Endian.little);
  byteData.setUint32(28, sampleRate * 2, Endian.little);
  byteData.setUint16(32, 2, Endian.little);
  byteData.setUint16(34, 16, Endian.little);
  byteData.setUint32(36, 0x64617461, Endian.big); // "data"
  byteData.setUint32(40, int16Data.lengthInBytes, Endian.little);
  
  int offset = 44;
  for (int i = 0; i < int16Data.length; i++) {
    byteData.setInt16(offset, int16Data[i], Endian.little);
    offset += 2;
  }
  
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  print('Generated $filename');
}

void main() {
  // Option A: Loud Piercing Ding (Single loud metallic strike)
  writeWav(
    'enything_bell_loud_ding.wav',
    [1046.50, 1055.0], // C6 with slight detune for a thick ringing
    [0.0, 0.0],
    [2.0, 2.1], // Longer decay for a ringing bell
    [2.0, 2.0],
    3.0, // High FM amount for metallic timbre
    1.414,
    extraLoud: true
  );

  // Option B: Loud Rich Chime (Ding-Dong)
  writeWav(
    'enything_bell_loud_chime.wav',
    [880.00, 783.99], // A5 down to G5
    [0.0, 0.3], // Second note hits at 0.3s
    [2.5, 2.5],
    [2.0, 2.0],
    2.5,
    1.618,
    extraLoud: true
  );

  // Option C: Massive Alert Bell (Two fast strikes)
  writeWav(
    'enything_bell_loud_alert.wav',
    [987.77, 987.77], // B5 twice
    [0.0, 0.15],
    [3.0, 3.0],
    [2.0, 2.0],
    4.0, // Very metallic
    1.414,
    extraLoud: true
  );
}
