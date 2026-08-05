import 'package:audioplayers/audioplayers.dart';

/// Short, distinct sound effects for sending vs receiving a chat message
/// -- previously chat was completely silent, easy to miss a new message
/// while the screen was open but not focused on it. See DECISIONS.md.
class ChatSoundService {
  static final _sentPlayer = AudioPlayer();
  static final _receivedPlayer = AudioPlayer();

  static Future<void> playSent() async {
    try {
      await _sentPlayer.play(AssetSource('sounds/sent.wav'), volume: 0.6);
    } catch (_) {
      // Sound is a nice-to-have, never worth surfacing an error over.
    }
  }

  static Future<void> playReceived() async {
    try {
      await _receivedPlayer.play(AssetSource('sounds/received.wav'), volume: 0.6);
    } catch (_) {}
  }
}
