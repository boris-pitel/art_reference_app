import 'dart:convert';

/// Android evaluateJavascript JSON-quotes String results; WKWebView returns
/// Strings directly. Consumers expect the JSON.stringify payload in both cases.
String retailerScriptResult(Object? result) {
  if (result is! String) return jsonEncode(result);
  try {
    final decoded = jsonDecode(result);
    if (decoded is String) return decoded;
  } on FormatException {
    // Preserve malformed results so the calling parser reports a failed check.
  }
  return result;
}
