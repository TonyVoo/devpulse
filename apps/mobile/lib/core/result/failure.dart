import 'package:dio/dio.dart';

/// What went wrong, in terms the UI can act on. Built from the API's problem+json `code`,
/// never from human-readable text.
sealed class Failure implements Exception {
  const Failure(this.message, {this.code, this.requestId});

  final String message;
  final String? code;
  final String? requestId;

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
        return const UnknownFailure('The response took too long to process.');
      case DioExceptionType.cancel:
        return const UnknownFailure('Request cancelled');
      case DioExceptionType.badCertificate:
        return const NetworkFailure("Can't establish a secure connection.");
      case DioExceptionType.badResponse:
      case DioExceptionType.unknown:
        break;
    }
    final response = e.response;
    if (response == null) return const NetworkFailure();
    final body = response.data;
    final problem = body is Map<String, dynamic> ? body : const <String, dynamic>{};
    final code = problem['code'] as String?;
    final detail = (problem['detail'] as String?) ?? 'Something went wrong. Try again.';
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
      return RateLimitedFailure(
        'Too many attempts. Wait a few minutes and try again.',
        code: code,
        requestId: requestId,
      );
    }
    return ServerFailure(
      status >= 500 ? 'DevPulse is having trouble right now. Try again shortly.' : detail,
      status: status,
      code: code,
      requestId: requestId,
    );
  }

  @override
  String toString() => '$runtimeType($code): $message';
}

final class NetworkFailure extends Failure {
  const NetworkFailure([super.message = "Can't reach DevPulse. Check your connection."]);
}

final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message, {super.code, super.requestId});
}

final class ForbiddenFailure extends Failure {
  const ForbiddenFailure(super.message, {super.code, super.requestId});
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message, {super.code, super.requestId});
}

final class ConflictFailure extends Failure {
  const ConflictFailure(super.message, {super.code, super.requestId});
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.fields = const {}, super.code, super.requestId});

  /// Field name → server message, e.g. `{'password': 'String should have at least 12 characters'}`.
  final Map<String, String> fields;
}

final class RateLimitedFailure extends Failure {
  const RateLimitedFailure(super.message, {super.code, super.requestId});
}

final class ServerFailure extends Failure {
  const ServerFailure(super.message, {required this.status, super.code, super.requestId});

  final int status;
}

final class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}
