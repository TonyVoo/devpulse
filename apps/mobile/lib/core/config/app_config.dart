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
    return AppConfig(apiBaseUrl: url.endsWith('/') ? url.substring(0, url.length - 1) : url);
  }

  final String apiBaseUrl;

  String get apiV1 => '$apiBaseUrl/api/v1';
}
