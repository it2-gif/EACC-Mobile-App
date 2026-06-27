import 'dart:html' as html;
import 'dart:js_util' as js_util;

Future<String?> requestWebFcmToken(String vapidKey) async {
  final hasBridge = js_util.hasProperty(html.window, 'eaccGetFcmToken');
  if (!hasBridge) return null;

  final result = await js_util.promiseToFuture<Object?>(
    js_util.callMethod(html.window, 'eaccGetFcmToken', [vapidKey]),
  );

  final token = result?.toString().trim();
  return token == null || token.isEmpty ? null : token;
}
