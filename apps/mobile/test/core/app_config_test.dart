import 'package:devpulse_mobile/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release builds require https (except local dev hosts)', () {
    expect(AppConfig.validated('https://api.example.com/', release: true), 'https://api.example.com');
    expect(() => AppConfig.validated('http://api.example.com', release: true), throwsArgumentError);
    expect(AppConfig.validated('http://localhost:8000', release: true), 'http://localhost:8000');
    expect(AppConfig.validated('http://api.example.com', release: false), 'http://api.example.com');
    expect(() => AppConfig.validated('not a url', release: false), throwsArgumentError);
  });
}
