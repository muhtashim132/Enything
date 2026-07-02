import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

void main() {
  const sampleRate = 44100;
  
  // Frequency of notes (F5, A5, C6)
  const freqs = [698.46, 880.00, 1046.50];
  const durations = [1.5, 1.5, 1.5];
  const decays = [3.0, 3.0, 3.0];
  const delays = [0.0, 0.15, 0.30];
  
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
        final modulator = sin(2 * pi * (freq * 1.414) * t) * 2.0;
        final tone = sin(carrier + modulator);
        final envelope = exp(-decay * t);
        audioData[idx] += tone * envelope;
      }
    }
  }
  
  // Normalize and apply some overdrive
  double maxVal = 0.0;
  for (int i = 0; i < totalSamples; i++) {
    if (audioData[i].abs() > maxVal) {
      maxVal = audioData[i].abs();
    }
  }
  
  final int16Data = Int16List(totalSamples);
  for (int i = 0; i < totalSamples; i++) {
    double val = (audioData[i] / maxVal) * 1.5;
    if (val > 1.0) val = 1.0;
    if (val < -1.0) val = -1.0;
    int16Data[i] = (val * 32767).toInt();
  }
  
  // Write WAV file
  final file = File('enything_bell.wav');
  final byteData = ByteData(44 + int16Data.lengthInBytes);
  
  // RIFF chunk descriptor
  byteData.setUint32(0, 0x52494646, Endian.big); // "RIFF"
  byteData.setUint32(4, 36 + int16Data.lengthInBytes, Endian.little);
  byteData.setUint32(8, 0x57415645, Endian.big); // "WAVE"
  
  // fmt sub-chunk
  byteData.setUint32(12, 0x666D7420, Endian.big); // "fmt "
  byteData.setUint32(16, 16, Endian.little); // Subchunk1Size
  byteData.setUint16(20, 1, Endian.little); // AudioFormat (PCM)
  byteData.setUint16(22, 1, Endian.little); // NumChannels
  byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
  byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
  byteData.setUint16(32, 2, Endian.little); // BlockAlign
  byteData.setUint16(34, 16, Endian.little); // BitsPerSample
  
  // data sub-chunk
  byteData.setUint32(36, 0x64617461, Endian.big); // "data"
  byteData.setUint32(40, int16Data.lengthInBytes, Endian.little);
  
  int offset = 44;
  for (int i = 0; i < int16Data.length; i++) {
    byteData.setInt16(offset, int16Data[i], Endian.little);
    offset += 2;
  }
  
  file.writeAsBytesSync(byteData.buffer.asUint8List());
  print('Generated enything_bell.wav');
}
