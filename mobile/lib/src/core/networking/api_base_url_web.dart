String resolveApiBaseUrl() {
  const defined = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (defined.isNotEmpty) {
    return defined;
  }
  return 'http://localhost:8080';
}

String rewriteDevLocalEndpoints(String value) => value;
