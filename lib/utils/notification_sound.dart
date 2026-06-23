// Platform-conditional notification sound player.
// On web  → calls playNotificationTone() from web/index.html (Web Audio API).
// On mobile → stub (add audioplayers asset implementation when needed).
import 'notification_sound_stub.dart'
    if (dart.library.js_interop) 'notification_sound_web.dart';

/// Plays a short notification chime.
/// Safe to call on any platform — silently does nothing if audio is unavailable.
void playNotificationSound() => playNotificationSoundImpl();
