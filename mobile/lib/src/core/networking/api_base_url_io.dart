import 'dart:io' show Platform;

String resolveApiBaseUrl() {
  const defined = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (defined.isNotEmpty) {
    return defined;
  }
  if (Platform.isAndroid) {
    return 'http://10.0.2.2:8080';
  }
  return 'http://localhost:8080';
}

String _devLoopbackReplacement() {
  const defined = String.fromEnvironment('DEV_LOOPBACK_HOST', defaultValue: '');
  if (defined.isNotEmpty) {
    return defined;
  }
  if (Platform.isAndroid) {
    return '10.0.2.2';
  }
  return 'localhost';
}

/// Rewrites localhost/127.0.0.1 in URLs returned by the API (WS, LiveKit, ICE) for Android emulator.
String rewriteDevLocalEndpoints(String value) {
  if (value.isEmpty) {
    return value;
  }
  final host = _devLoopbackReplacement();
  if (host == 'localhost') {
    return value;
  }
  return value.replaceAll('127.0.0.1', host).replaceAll('localhost', host);
}
