import 'dart:async';
import 'dart:io';

/// Structured exception for Build X API communication errors (NVIDIA NIM).
///
/// Converts HTTP errors, authentication failures, timeouts, and rate limits
/// into user-friendly messages while maintaining technical debug context.
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

  /// Translates HTTP status codes or exceptions into informative error messages.
  factory BuildXApiException.fromHttp({
    required int statusCode,
    String? responseBody,
  }) {
    if (statusCode == 401) {
      return BuildXApiException(
        userMessage:
            'فشل التحقق من مفتاح NVIDIA API (Authentication failed). يرجى التحقق من المفتاح في الإعدادات.',
        statusCode: 401,
        technicalDetail: responseBody,
      );
    }
    if (statusCode == 403) {
      return BuildXApiException(
        userMessage:
            'تم رفض الوصول إلى نموذج NVIDIA (Access denied). تحقق من صلاحيات الحساب.',
        statusCode: 403,
        technicalDetail: responseBody,
      );
    }
    if (statusCode == 429) {
      return BuildXApiException(
        userMessage:
            'تم تجاوز حد الاستخدام المسموح مؤقتًا (Rate limit / Quota exceeded). يرجى المحاولة بعد قليل.',
        statusCode: 429,
        technicalDetail: responseBody,
      );
    }
    if (statusCode >= 500 && statusCode < 600) {
      return BuildXApiException(
        userMessage:
            'خدمة NVIDIA تواجه خطأ في الخادم (NVIDIA service error $statusCode). يرجى المحاولة لاحقًا.',
        statusCode: statusCode,
        technicalDetail: responseBody,
      );
    }
    return BuildXApiException(
      userMessage: 'حدث خطأ أثناء التواصل مع NVIDIA (كود $statusCode).',
      statusCode: statusCode,
      technicalDetail: responseBody,
    );
  }

  factory BuildXApiException.network(Object error) {
    if (error is TimeoutException ||
        error.toString().toLowerCase().contains('timeout')) {
      return BuildXApiException(
        userMessage:
            'انتهت مهلة انتظار الاستجابة من NVIDIA (Request timed out). تحقق من استقرار اتصالك.',
        originalError: error,
      );
    }
    if (error is SocketException ||
        error.toString().toLowerCase().contains('socketexception') ||
        error.toString().toLowerCase().contains('network')) {
      return BuildXApiException(
        userMessage:
            'تعذر الاتصال بالشبكة (Network unavailable). تأكد من اتصال الإنترنت.',
        originalError: error,
      );
    }
    return BuildXApiException(
      userMessage: 'تعذر الاتصال بخدمة NVIDIA: ${error.toString()}',
      originalError: error,
    );
  }

  factory BuildXApiException.streamParsing(Object error) {
    return BuildXApiException(
      userMessage:
          'خطأ في معالجة تدفق الاستجابة من NVIDIA (Response stream parsing error).',
      originalError: error,
    );
  }

  @override
  String toString() => userMessage;
}
