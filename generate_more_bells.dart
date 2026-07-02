import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

void writeWav(String filename, List<double> freqs, List<double> delays, List<double> decays, List<double> durations, double fmAmount) {
  const sampleRate = 44100;
  const totalDuration = 2.0;
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
        final modulator = sin(2 * pi * (freq * 1.414) * t) * fmAmount;
        final tone = sin(carrier + modulator);
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
    if (val > 1.0) val = 1.0;
    if (val < -1.0) val = -1.0;
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
  // Option 1: Soft Bell
  writeWav(
    'enything_bell_soft.wav',
    [523.25, 659.25], // C5, E5
    [0.0, 0.15],
    [5.0, 5.0],
    [1.5, 1.5],
    1.0
  );

  // Option 2: Energetic Bell (Fast Arp)
  writeWav(
    'enything_bell_energetic.wav',
    [523.25, 659.25, 783.99, 1046.50], // C5, E5, G5, C6
    [0.0, 0.08, 0.16, 0.24],
    [4.0, 4.0, 4.0, 4.0],
    [1.0, 1.0, 1.0, 1.5],
    1.5
  );

  // Option 3: Modern Pure Bell
  writeWav(
    'enything_bell_modern.wav',
    [880.00, 1108.73], // A5, C#6
    [0.0, 0.1],
    [2.5, 2.5],
    [1.5, 1.5],
    2.5 // Stronger FM for a more synthetic modern tone
  );
}
