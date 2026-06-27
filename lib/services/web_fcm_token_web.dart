import 'dart:js_interop';

import 'package:flutter/foundation.dart';

@JS('eaccGetFcmToken')
external JSFunction? get _eaccGetFcmToken;

@JS('eaccGetFcmToken')
external JSPromise<JSString?> _requestEaccFcmToken(JSString vapidKey);

Future<String?> requestWebFcmToken(String vapidKey) async {
  try {
    if (_eaccGetFcmToken == null) {
      debugPrint('EACC FCM bridge is not available on this page.');
      return null;
    }

    final result = await _requestEaccFcmToken(vapidKey.toJS).toDart;
    final token = result?.toDart.trim();
    return token == null || token.isEmpty ? null : token;
  } catch (error, stackTrace) {
    debugPrint('EACC FCM bridge token request failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return null;
  }
}
