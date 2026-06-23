// Web implementation — calls the playNotificationTone() JS function
// defined in web/index.html via the Web Audio API.
import 'dart:js_interop';

@JS('playNotificationTone')
external void _jsPlay();

void playNotificationSoundImpl() {
  try {
    _jsPlay();
  } catch (_) {
    // Silently ignore if Web Audio is unavailable (e.g., browser policy).
  }
}
