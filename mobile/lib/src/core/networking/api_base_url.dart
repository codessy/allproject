import 'api_base_url_io.dart' if (dart.library.html) 'api_base_url_web.dart' as impl;

/// REST base URL. Override with `--dart-define=API_BASE_URL=http://192.168.x.x:8080`.
String resolveApiBaseUrl() => impl.resolveApiBaseUrl();

/// For WS / LiveKit / ICE strings from the API when using Android emulator.
String rewriteDevLocalEndpoints(String value) => impl.rewriteDevLocalEndpoints(value);
