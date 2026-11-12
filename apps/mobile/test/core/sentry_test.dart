import 'package:devpulse_mobile/core/observability/sentry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test('error reports carry no user or request data', () async {
    final event = SentryEvent(
      user: SentryUser(id: 'u1', email: 'ada@example.com'),
      request: SentryRequest(url: 'https://api.example.com/x', headers: {'Authorization': 'Bearer t'}),
    );
    final out = await scrubSentryEvent(event, Hint());
    expect(out!.user, isNull);
    expect(out.request, isNull);
  });

  test('sentry is off by default (no DSN compiled in)', () {
    expect(sentryDsn, isEmpty);
    final o = SentryFlutterOptions();
    configureSentry(o);
    expect(o.sendDefaultPii, isFalse);
    expect(o.attachScreenshot, isFalse);
  });
}
