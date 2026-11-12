import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash/error reporting. Off unless the build passes `--dart-define=SENTRY_DSN=…`.
/// No user, request data or screenshots ever leave the device.
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

FutureOr<SentryEvent?> scrubSentryEvent(SentryEvent event, Hint hint) {
  event
    ..user = null
    ..request = null;
  return event;
}

void configureSentry(SentryFlutterOptions o) {
  o
    ..dsn = sentryDsn
    ..environment = const String.fromEnvironment('APP_ENV', defaultValue: 'local')
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..attachViewHierarchy = false
    ..tracesSampleRate = 0
    ..beforeSend = scrubSentryEvent;
}
