import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'sherpa_model_manager.dart';

final class SherpaAsrService {
  SherpaAsrService({SherpaModelManager? modelManager, this.numThreads = 2})
      : modelManager = modelManager ?? SherpaModelManager();

  final SherpaModelManager modelManager;
  final int numThreads;

  Future<String> transcribePcm16({
    required String modelId,
    required Uint8List pcm16,
    required int sampleRate,
    String language = 'auto',
    Directory? modelDirectory,
    String? modelDirectoryPath,
  }) async {
    return '';
  }

  static Float32List pcm16ToFloat32(Uint8List pcm16) => Float32List(0);

  /// Rejects silence/very short captures and trims quiet edges before native
  /// decoding. The detector intentionally uses a conservative energy gate,
  /// not a language-specific VAD, so it works for every bundled model.
  static Uint8List? preparePcm16ForRecognition(
    Uint8List pcm16, {
    required int sampleRate,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'Must be positive');
    }
    if (pcm16.length.isOdd) {
      throw const FormatException('PCM16 data must contain complete samples');
    }

    final sampleCount = pcm16.length ~/ 2;
    final minimumSamples = (sampleRate * 0.30).round();
    if (sampleCount < minimumSamples) return null;

    final data = ByteData.sublistView(pcm16);
    final frameSamples = math.max(1, sampleRate ~/ 50); // 20 ms
    final frameRms = <double>[];
    for (var start = 0; start < sampleCount; start += frameSamples) {
      final end = math.min(start + frameSamples, sampleCount);
      var sumSquares = 0.0;
      for (var index = start; index < end; index++) {
        final value = data.getInt16(index * 2, Endian.little) / 32768.0;
        sumSquares += value * value;
      }
      frameRms.add(math.sqrt(sumSquares / (end - start)));
    }

    final sortedRms = List<double>.of(frameRms)..sort();
    final noiseFloor = sortedRms[(sortedRms.length * 0.2).floor()];
    final activeThreshold = math.min(math.max(noiseFloor * 2.5, 0.004), 0.025);
    final peakRms = sortedRms.last;
    if (peakRms < math.max(0.006, noiseFloor * 1.35)) return null;

    var activeFrames = 0;
    var consecutiveActiveFrames = 0;
    var longestActiveRun = 0;
    var firstActive = -1;
    var lastActive = -1;
    for (var index = 0; index < frameRms.length; index++) {
      if (frameRms[index] < activeThreshold) {
        consecutiveActiveFrames = 0;
        continue;
      }
      activeFrames++;
      consecutiveActiveFrames++;
      longestActiveRun = math.max(longestActiveRun, consecutiveActiveFrames);
      firstActive = firstActive < 0 ? index : firstActive;
      lastActive = index;
    }
    if (activeFrames < 8 || longestActiveRun < 5 || firstActive < 0) {
      return null;
    }

    final paddingSamples = (sampleRate * 0.20).round();
    final startSample = math.max(
      0,
      firstActive * frameSamples - paddingSamples,
    );
    final endSample = math.min(
      sampleCount,
      (lastActive + 1) * frameSamples + paddingSamples,
    );
    return Uint8List.fromList(
      Uint8List.sublistView(pcm16, startSample * 2, endSample * 2),
    );
  }
}

typedef SherpaOnnxAsrService = SherpaAsrService;
