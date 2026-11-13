import 'dart:convert';
import 'dart:io';

import 'package:devpulse_mobile/core/config/app_config.dart';
import 'package:devpulse_mobile/core/design_system/widgets/status_widgets.dart';
import 'package:devpulse_mobile/core/network/org_api.dart';
import 'package:devpulse_mobile/core/result/failure.dart';
import 'package:devpulse_mobile/features/auth/domain/models.dart';
import 'package:devpulse_mobile/features/copilot/data/ai_repository.dart';
import 'package:devpulse_mobile/features/incidents/domain/incident.dart';
import 'package:devpulse_mobile/l10n/l10n.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'widgets_test.dart' show pumpApp;

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

/// Placeholder names used in a message (ignores ICU plural branch text).
Set<String> _placeholders(String s) =>
    RegExp(r'(?<![=\w])\{(\w+)(?:,|\})').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  tearDown(() => syncL10nLocale(const Locale('en')));

  group('translations', () {
    final en = _arb('en');
    final vi = _arb('vi');
    final keys = en.keys.where((k) => !k.startsWith('@'));

    test('Vietnamese has every message', () {
      expect(keys.where((k) => !vi.containsKey(k)), isEmpty);
      expect(keys.where((k) => (vi[k] as String).trim().isEmpty), isEmpty);
    });

    test('Vietnamese keeps every placeholder', () {
      final broken = keys.where((k) => !setEquals(_placeholders(en[k] as String), _placeholders(vi[k] as String)));
      expect(broken, isEmpty);
    });
  });

  group('text outside widgets follows the app language', () {
    test('failures, labels, relative time and numbers', () {
      syncL10nLocale(const Locale('vi'));
      expect(const NetworkFailure().message, 'Không kết nối được tới DevPulse. Hãy kiểm tra kết nối mạng.');
      expect(
        const UnauthorizedFailure('Email or password is incorrect', code: 'auth.invalid_credentials').message,
        'Email hoặc mật khẩu không đúng',
      );
      // Unknown codes keep the server's text rather than hiding it.
      expect(const ConflictFailure('Server says no', code: 'x.y').message, 'Server says no');
      expect(OrgRole.owner.label, 'Chủ sở hữu');
      expect(IncidentStatus.acknowledged.label, 'Đã xác nhận');
      expect(Health.degraded.label, 'Suy giảm');
      final now = DateTime(2026, 11, 12, 12);
      expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), '5 phút trước');
      expect(millis(1650), '1,65 s');
      expect(percent(0.053), '5,3%');

      syncL10nLocale(const Locale('fr')); // unsupported → English
      expect(Health.degraded.label, 'Degraded');
      expect(millis(1650), '1.65 s');
    });
  });

  test('AI requests carry the app language, so analyses and answers come back in it', () async {
    final adapter = FakeAdapter((o) => jsonBody({'messages': <dynamic>[], 'new_evidence': <dynamic>[]}));
    final dio = Dio(BaseOptions(baseUrl: '${const AppConfig(apiBaseUrl: 'http://api.test').apiV1}/'))
      ..httpClientAdapter = adapter;
    final repo = ApiAiRepository(OrgApi(dio, 'org-1'));

    syncL10nLocale(const Locale('vi'));
    await repo.ask('inv-1', 'Lỗi bắt đầu khi nào?', 'c-1');
    await repo.start('INC-1').then((_) {}, onError: (Object _) {}); // body is all we check
    expect([for (final r in adapter.requests) (r.data as Map<String, dynamic>)['language']], ['vi', 'vi']);

    syncL10nLocale(const Locale('en'));
    await repo.ask('inv-1', 'When did errors start?', 'c-2');
    expect((adapter.requests.last.data as Map<String, dynamic>)['language'], 'en');
  });

  testWidgets('the app opens in the saved language', (tester) async {
    await pumpApp(tester, FakeAuthRepository(), locale: 'vi');
    expect(find.text('Đăng nhập'), findsWidgets);
    expect(find.text('Email công việc'), findsOneWidget);
  });

  testWidgets('switching language in Settings updates the app', (tester) async {
    await pumpApp(tester, FakeAuthRepository(session: true, remote: me()));
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Settings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tiếng Việt'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Tiếng Việt'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Cài đặt')), findsOneWidget);
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('Sự cố')), findsOneWidget);
    expect(find.text('NGÔN NGỮ'), findsOneWidget); // section headers are upper-cased
  });
}
