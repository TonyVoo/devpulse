import 'package:dio/dio.dart';

import '../../l10n/l10n.dart';

/// What went wrong, in terms the UI can act on. Built from the API's problem+json `code`,
/// never from human-readable text.
sealed class Failure implements Exception {
  const Failure(this.detail, {this.code, this.requestId});

  /// The server's own (English) text, kept for logs and as the fallback for unknown codes.
  final String detail;
  final String? code;
  final String? requestId;

  /// What to show the user, in the app's language: by failure type and API error code,
  /// falling back to the server's text.
  String get message {
    final known = switch (code) {
      'auth.invalid_credentials' => l10n.errInvalidCredentials,
      'auth.email_taken' => l10n.errEmailTaken,
      'auth.session_ended' || 'auth.session_revoked' || 'auth.token_expired' => l10n.sessionEnded,
      'conflict.version_mismatch' => l10n.errVersionMismatch,
      'incident.invalid_transition' => l10n.errInvalidTransition,
      'incident.max_escalation' => l10n.errMaxEscalation,
      'org.slug_taken' || 'service.slug_taken' => l10n.errSlugTaken,
      _ => null,
    };
    return known ?? (detail.isEmpty ? l10n.errGeneric : detail);
  }

  /// Maps any error thrown by the networking layer into a [Failure].
  static Failure from(Object error) {
    if (error is Failure) return error;
    if (error is DioException) {
      if (error.error is Failure) return error.error! as Failure;
      return _fromDio(error);
    }
    return UnknownFailure(error.toString());
  }

  static Failure _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.transformTimeout:
        return const UnknownFailure(UnknownFailure.slow);
      case DioExceptionType.cancel:
        return const UnknownFailure(UnknownFailure.cancelled);
      case DioExceptionType.badCertificate:
        return const NetworkFailure(NetworkFailure.insecure);
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
    final response = e.response;
    if (response == null) return const NetworkFailure();
    final body = response.data;
    final problem = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final code = problem['code'] as String?;
    final detail = (problem['detail'] as String?) ?? '';
    final requestId = problem['request_id'] as String?;
    final status = response.statusCode ?? 0;

    if (status == 401) return UnauthorizedFailure(detail, code: code, requestId: requestId);
    if (status == 403) return ForbiddenFailure(detail, code: code, requestId: requestId);
    if (status == 404) return NotFoundFailure(detail, code: code, requestId: requestId);
    if (status == 409) return ConflictFailure(detail, code: code, requestId: requestId);
    if (status == 422) {
      final fields = <String, String>{};
      for (final err in (problem['errors'] as List<dynamic>? ?? const [])) {
        if (err is Map<String, dynamic>) {
          final loc = (err['loc'] as List<dynamic>? ?? const []);
          if (loc.isNotEmpty) fields['${loc.last}'] = '${err['msg']}';
        }
      }
      return ValidationFailure(detail, fields: fields, code: code, requestId: requestId);
    }
    if (status == 429) {
      return RateLimitedFailure(detail, code: code, requestId: requestId);
    }
    return ServerFailure(detail, status: status, code: code, requestId: requestId);
  }

  @override
  String toString() => '$runtimeType($code): $detail';
}

final class NetworkFailure extends Failure {
  const NetworkFailure([super.detail = '']);

  static const insecure = 'tls';

  @override
  String get message => switch (detail) {
    '' => l10n.errNetwork,
    insecure => l10n.errInsecure,
    _ => detail,
  };
}

final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.detail, {super.code, super.requestId});
}

final class ForbiddenFailure extends Failure {
  const ForbiddenFailure(super.detail, {super.code, super.requestId});
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.detail, {super.code, super.requestId});
}

final class ConflictFailure extends Failure {
  const ConflictFailure(super.detail, {super.code, super.requestId});
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.detail, {this.fields = const {}, super.code, super.requestId});

  /// Field name → server message, e.g. `{'password': 'String should have at least 12 characters'}`.
  final Map<String, String> fields;
}

final class RateLimitedFailure extends Failure {
  const RateLimitedFailure(super.detail, {super.code, super.requestId});

  @override
  String get message => l10n.errTooMany;
}

final class ServerFailure extends Failure {
  const ServerFailure(super.detail, {required this.status, super.code, super.requestId});

  final int status;

  @override
  String get message => status >= 500 ? l10n.errServer : super.message;
}

final class UnknownFailure extends Failure {
  const UnknownFailure(super.detail);

  static const slow = 'transform_timeout';
  static const cancelled = 'cancelled';

  @override
  String get message => switch (detail) {
    slow => l10n.errSlow,
    cancelled => l10n.errCancelled,
    _ => super.message,
  };
}
