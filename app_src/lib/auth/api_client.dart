import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException;

import 'package:http/http.dart' as http;

import 'api_errors.dart';

/// Shared by the HTTP client and the sign-in controller: the current access
/// token, and what to do when the server says it has expired.
class ApiSession {
  String? accessToken;

  /// Gets a fresh access token. Returns true when the request should be retried.
  Future<bool> Function()? onUnauthorized;
}

/// Sends JSON to the Vyro server. Adds the access token, retries once after a
/// token refresh, and turns failures into [ApiException]s.
class ApiClient {
  ApiClient({required this.baseUrl, required this.session, http.Client? client, this.timeout = const Duration(seconds: 20)})
      : _client = client ?? http.Client();

  final Uri baseUrl;
  final ApiSession session;
  final Duration timeout;
  final http.Client _client;

  Future<Object?> send(String method, String path, {Object? body, Map<String, String>? query, bool auth = true}) async {
    http.Response response = await _once(method, path, body, query, auth);
    if (response.statusCode == 401 && auth) {
      final refresh = session.onUnauthorized;
      if (refresh != null && await refresh()) {
        response = await _once(method, path, body, query, auth);
      }
    }
    return _decode(response);
  }

  Future<http.Response> _once(String method, String path, Object? body, Map<String, String>? query, bool auth) async {
    final uri = baseUrl.replace(path: path, queryParameters: (query == null || query.isEmpty) ? null : query);
    final request = http.Request(method, uri)
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = 'application/json';
    final token = session.accessToken;
    if (auth && token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'network');
    } on IOException {
      throw const ApiException(0, 'network');
    } on http.ClientException {
      throw const ApiException(0, 'network');
    }
  }

  Object? _decode(http.Response r) {
    final text = utf8.decode(r.bodyBytes);
    Object? json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return json;
    final code = json is Map && json['error'] is String ? json['error'] as String : 'http_${r.statusCode}';
    throw ApiException(r.statusCode, code);
  }

  void close() => _client.close();
}
