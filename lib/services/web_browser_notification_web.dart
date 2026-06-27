import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('eaccShowBrowserNotification')
external JSFunction? get _eaccShowBrowserNotification;

@JS('eaccShowBrowserNotification')
external JSPromise<JSBoolean> _showEaccBrowserNotification(
  JSString title,
  JSString body,
  JSString courseId,
  JSString threadId,
  JSString studentName,
  JSString senderName,
);

Future<void> showWebBrowserNotification({
  required String title,
  required String body,
  required String courseId,
  required String threadId,
  required String studentName,
  required String senderName,
}) async {
  try {
    if (_eaccShowBrowserNotification == null) {
      debugPrint('Browser notification bridge is not available on this page.');
      return;
    }

    final shown = await _showEaccBrowserNotification(
      title.toJS,
      body.toJS,
      courseId.toJS,
      threadId.toJS,
      studentName.toJS,
      senderName.toJS,
    ).toDart;

    debugPrint(
      shown.toDart
          ? 'Browser notification shown from foreground message.'
          : 'Browser notification was not shown by the browser.',
    );
  } catch (error, stackTrace) {
    debugPrint('Browser notification bridge failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}
