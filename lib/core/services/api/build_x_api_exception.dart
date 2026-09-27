import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Structured exception for Build X API communication errors (NVIDIA NIM).
///
/// Converts HTTP errors, authentication failures, timeouts, and model errors
/// into clean, user-friendly messages while keeping internal details in debug logs.
class BuildXApiException implements Exception {
  const BuildXApiException({
    required this.userMessage,
    this.statusCode,
    this.technicalDetail,
    this.originalError,
  });

  final String userMessage;
  final int? statusCode;
  final String? technicalDetail;
  final Object? originalError;

  /// Translates HTTP status codes into consumer-friendly error messages.
  factory BuildXApiException.fromHttp({
    required int statusCode,
    String? responseBody,
  }) {
    final detail = _extractDetail(responseBody);
    final specificMessage = detail == null || detail.isEmpty
        ? 'Request failed with HTTP $statusCode.'
        : 'Request failed with HTTP $statusCode: $detail';
    if (statusCode == 401 || statusCode == 403) {
      return BuildXApiException(
        userMessage: 'The AI service could not authenticate.',
        statusCode: statusCode,
        technicalDetail: responseBody,
      );
    }
    if (statusCode == 404) {
      return BuildXApiException(
        userMessage: specificMessage,
        statusCode: 404,
        technicalDetail: responseBody,
      );
    }
    if (statusCode == 429) {
      return BuildXApiException(
        userMessage: 'The AI service is busy (HTTP 429). Please retry shortly.',
        statusCode: 429,
        technicalDetail: responseBody,
      );
    }
    return BuildXApiException(
      userMessage: statusCode == 404
          ? 'The requested AI endpoint or model was not found (HTTP 404): ${detail ?? 'No further details'}'
          : statusCode >= 500
          ? 'The AI service returned HTTP $statusCode. Please retry later.'
          : specificMessage,
      statusCode: statusCode,
      technicalDetail: responseBody,
    );
  }

  static String? _extractDetail(String? responseBody) {
    if (responseBody == null || responseBody.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } catch (_) {
      decoded = responseBody;
    }
    String detail;
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map) {
        detail = (error['message'] ?? error['detail'] ?? error.toString())
            .toString();
      } else {
        detail =
            (error ??
                    decoded['message'] ??
                    decoded['detail'] ??
                    decoded.toString())
                .toString();
      }
    } else {
      detail = decoded.toString();
    }
    detail = detail.replaceAll(
      RegExp(r'bearer\s+\S+|nvapi-[\w-]+', caseSensitive: false),
      '[redacted]',
    );
    detail = detail.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (detail.isEmpty) return null;
    return detail.length > 500 ? '${detail.substring(0, 500)}…' : detail;
  }

  factory BuildXApiException.network(Object error) {
    if (error is TimeoutException ||
        error.toString().toLowerCase().contains('timeout')) {
      return BuildXApiException(
        userMessage: 'The AI response timed out. Please try again.',
        originalError: error,
      );
    }
    if (error is SocketException ||
        error.toString().toLowerCase().contains('socketexception') ||
        error.toString().toLowerCase().contains('network') ||
        error.toString().toLowerCase().contains('failed host lookup')) {
      return BuildXApiException(
        userMessage:
            'Could not connect to the AI service. Check your network and retry.',
        originalError: error,
      );
    }
    return BuildXApiException(
      userMessage:
          'Could not connect to the AI service. Check your network and retry.',
      originalError: error,
    );
  }

  factory BuildXApiException.emptyResponse() {
    return const BuildXApiException(
      userMessage: 'The AI service returned an empty reply. Please try again.',
    );
  }

  factory BuildXApiException.streamParsing(Object error) {
    return BuildXApiException(
      userMessage: 'Could not read the AI response. Please try again.',
      originalError: error,
    );
  }

  @override
  String toString() => userMessage;
}
