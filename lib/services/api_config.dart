import 'package:flutter_dotenv/flutter_dotenv.dart';

const String _dartDefineApiBaseUrl = String.fromEnvironment('API_BASE_URL');

String _safeEnv(String key) {
  try {
    return (dotenv.env[key] ?? '').trim();
  } catch (_) {
    return '';
  }
}

String getApiBaseUrl() {
  final raw = _dartDefineApiBaseUrl.trim().isNotEmpty
      ? _dartDefineApiBaseUrl.trim()
      : _safeEnv('API_BASE_URL');
  if (raw.isEmpty) {
    return 'http://127.0.0.1:8011';
  }
  return raw.replaceAll(RegExp(r'/+$'), '');
}
