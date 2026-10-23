import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech-to-text behind a small interface, so the voice sheet can be tested
/// without a microphone.
abstract interface class SpeechRecognizer {
  /// Starts listening in German. [onText] gets partial and final results;
  /// [onError] is called when recognition is unavailable or fails.
  /// Returns false if speech recognition cannot be used on this device.
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  });

  Future<void> stop();
}

final speechRecognizerProvider = Provider<SpeechRecognizer>(
  (ref) => _DeviceSpeechRecognizer(),
);

class _DeviceSpeechRecognizer implements SpeechRecognizer {
  final _speech = SpeechToText();

  @override
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
  }) async {
    final available = await _speech.initialize(
      onError: (e) => onError(_describe(e.errorMsg)),
    );
    if (!available) return false;
    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: 'de_DE',
        partialResults: true,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        cancelOnError: true,
      ),
    );
    return true;
  }

  @override
  Future<void> stop() => _speech.stop();

  static String _describe(String code) => switch (code) {
    'error_no_match' || 'error_speech_timeout' => 'Nichts verstanden.',
    'error_network' ||
    'error_network_timeout' => 'Spracherkennung braucht eine Verbindung.',
    'error_insufficient_permissions' => 'Kein Zugriff auf das Mikrofon.',
    _ => 'Spracherkennung fehlgeschlagen.',
  };
}
