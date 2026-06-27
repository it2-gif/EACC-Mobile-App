import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:flutter/foundation.dart';

Future<String?> requestWebFcmToken(String vapidKey) async {
  try {
    final hasBridge = js_util.hasProperty(html.window, 'eaccGetFcmToken');
    if (!hasBridge) {
      debugPrint('EACC FCM bridge is not available on this page.');
      return null;
    }

    final result = await js_util.promiseToFuture<Object?>(
      js_util.callMethod(html.window, 'eaccGetFcmToken', [vapidKey]),
    );

    final token = result?.toString().trim();
    return token == null || token.isEmpty ? null : token;
  } catch (error, stackTrace) {
    debugPrint('EACC FCM bridge token request failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    return null;
  }
}
