import 'package:flutter/foundation.dart';

/// Build-time configuration via `--dart-define`. No secrets ever live in the app binary.
///
/// ```sh
/// flutter run --dart-define=API_BASE_URL=http://localhost:8000
/// ```
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    const url = String.fromEnvironment(
      'API_BASE_URL',
      // The iOS simulator reaches the host's localhost directly.
      // Android emulators need http://10.0.2.2:8000.
      defaultValue: 'http://localhost:8000',
    );
    return AppConfig(apiBaseUrl: validated(url, release: kReleaseMode));
  }

  /// Release builds talk to DevPulse over HTTPS only (tokens, incident data). Plain HTTP is
  /// accepted for local development hosts so simulators and emulators keep working.
  static String validated(String url, {required bool release}) {
    final trimmed = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(url, 'API_BASE_URL', 'is not an absolute URL');
    }
    const local = {'localhost', '127.0.0.1', '10.0.2.2'};
    if (release && uri.scheme != 'https' && !local.contains(uri.host)) {
      throw ArgumentError.value(url, 'API_BASE_URL', 'must use https in release builds');
    }
    return trimmed;
  }

  final String apiBaseUrl;

  String get apiV1 => '$apiBaseUrl/api/v1';
}
