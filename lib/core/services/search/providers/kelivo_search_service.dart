import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../search_service.dart';

class KelivoSearchService extends SearchService<KelivoOptions> {
  KelivoSearchService({super.client});

  static String get _token {
    return const String.fromEnvironment('BUILD_X_SEARCH_TOKEN');
  }

  @override
  String get name => 'Build X';

  @override
  Widget description(BuildContext context) => const SizedBox.shrink();

  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required KelivoOptions serviceOptions,
  }) async {
    final ownsClient = client == null;
    // Keep this off DioHttpClient so the built-in token is not written to request logs.
    final httpClient = client ?? http.Client();
    try {
      final language = _languageQueryValue(PlatformDispatcher.instance.locale);
      final uri = Uri.https('search.psycheas.top', '/v1/search', {
        'q': query,
        'count': '${commonOptions.resultSize}',
        if (language != null) 'language': language,
      });
      final response = await httpClient
          .get(uri, headers: {'Authorization': 'Bearer $_token'})
          .timeout(Duration(milliseconds: commonOptions.timeout));
      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      final results = (data['results'] as List? ?? const []).map((item) {
        return SearchResultItem(
          title: item['title'] ?? '',
          url: item['url'] ?? '',
          text: item['content'] ?? '',
        );
      }).toList();

      return SearchResult(items: results);
    } catch (e) {
      throw Exception('Build X search failed: $e');
    } finally {
      if (ownsClient) httpClient.close();
    }
  }

  static String? _languageQueryValue(Locale locale) {
    final language = locale.languageCode.trim();
    if (language.isEmpty) return null;
    final country = locale.countryCode?.trim();
    if (country != null && country.isNotEmpty) {
      return '$language-$country';
    }
    if (language == 'zh') return 'zh-CN';
    if (language == 'en') return 'en-US';
    return language;
  }
}
