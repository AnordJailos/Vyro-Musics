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

  /// Sends a file as the request body without loading it into memory, and reports progress.
  /// [open] is called again if the request has to be retried after a token refresh.
  Future<Object?> upload(
    String path, {
    required Stream<List<int>> Function() open,
    required int length,
    required String contentType,
    void Function(int sent, int total)? onProgress,
  }) async {
    http.Response response = await _uploadOnce(path, open, length, contentType, onProgress);
    if (response.statusCode == 401) {
      final refresh = session.onUnauthorized;
      if (refresh != null && await refresh()) response = await _uploadOnce(path, open, length, contentType, onProgress);
    }
    return _decode(response);
  }

  Future<http.Response> _uploadOnce(String path, Stream<List<int>> Function() open, int length, String contentType, void Function(int, int)? onProgress) async {
    final request = http.StreamedRequest('PUT', baseUrl.replace(path: path))
      ..headers['accept'] = 'application/json'
      ..headers['content-type'] = contentType
      ..contentLength = length;
    final token = session.accessToken;
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    var sent = 0;
    final body = open().map((chunk) {
      sent += chunk.length;
      onProgress?.call(sent, length);
      return chunk;
    });
    // addStream honours back-pressure, so a large file is read only as fast as it is sent.
    request.sink.addStream(body).then<void>((_) => request.sink.close()).catchError((Object _) => request.sink.close());
    try {
      final streamed = await _client.send(request).timeout(const Duration(minutes: 30));
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(0, 'network');
    } on IOException {
      throw const ApiException(0, 'network');
    } on http.ClientException {
      throw const ApiException(0, 'network');
    }
  }

  void close() => _client.close();
}
