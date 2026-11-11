import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payload the API sends with every push (see `app/modules/notifications/push.py`).
class PushPayload {
  const PushPayload({required this.route, required this.orgId});

  final String route;
  final String orgId;

  static final _allowed = RegExp(r'^/incidents/[A-Za-z0-9-]{1,64}$');

  /// Only well-formed in-app routes are accepted; anything else is ignored (a push must
  /// never be able to navigate to an arbitrary location).
  static PushPayload? parse(Map<String, dynamic> data) {
    final route = data['route'];
    final org = data['org_id'];
    if (route is! String || org is! String || !_allowed.hasMatch(route)) return null;
    return PushPayload(route: route, orgId: org);
  }
}

/// Source of push messages. The Firebase implementation needs a Firebase project
/// (GoogleService-Info.plist / google-services.json + APNs key), which is not configured
/// yet; until then [NoPushMessages] keeps the app fully functional without push.
abstract interface class PushMessages {
  /// The message that launched the app from a terminated state (cold start), if any.
  Future<Map<String, dynamic>?> initialMessage();

  /// Messages tapped while the app was in the background.
  Stream<Map<String, dynamic>> get opened;

  /// Device token to register with `POST /me/devices`, or null when push is unavailable.
  Future<String?> token();
}

class NoPushMessages implements PushMessages {
  const NoPushMessages();

  @override
  Future<Map<String, dynamic>?> initialMessage() async => null;

  @override
  Stream<Map<String, dynamic>> get opened => const Stream.empty();

  @override
  Future<String?> token() async => null;
}

final pushMessagesProvider = Provider<PushMessages>((ref) => const NoPushMessages());
