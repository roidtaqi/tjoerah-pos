import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );
  static const Duration requestTimeout = Duration(seconds: 12);
  static final http.Client _client = http.Client();

  static Future<Map<String, String>> authHeaders({
    bool includeContentType = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    return {
      if (includeContentType) 'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> multipart(
    String endpoint, {
    required Map<String, String> fields,
    required String photoPath,
  }) async {
    final headers = await authHeaders();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'))
          ..headers.addAll({
            'Accept': headers['Accept']!,
            if (headers['Authorization'] != null)
              'Authorization': headers['Authorization']!,
          })
          ..fields.addAll(fields)
          ..files.add(await http.MultipartFile.fromPath('photo', photoPath));
    final streamed = await _client.send(request).timeout(requestTimeout);
    return http.Response.fromStream(streamed);
  }

  static Future<http.Response> uploadFile(
    String endpoint, {
    required Uint8List bytes,
    required String filename,
    String fieldName = 'file',
    Map<String, String> fields = const {},
  }) async {
    final headers = await authHeaders();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'))
          ..headers.addAll({
            'Accept': headers['Accept']!,
            if (headers['Authorization'] != null)
              'Authorization': headers['Authorization']!,
          })
          ..fields.addAll(fields)
          ..files.add(
            http.MultipartFile.fromBytes(fieldName, bytes, filename: filename),
          );
    final streamed = await _client.send(request).timeout(requestTimeout);
    return http.Response.fromStream(streamed);
  }

  static Future<http.Response> post(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final headers = await authHeaders();
    return _client
        .post(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(requestTimeout);
  }

  static Future<http.Response> get(
    String endpoint, {
    Map<String, String> additionalHeaders = const {},
  }) async {
    final headers = {...await authHeaders(), ...additionalHeaders};
    return _client
        .get(Uri.parse('$baseUrl$endpoint'), headers: headers)
        .timeout(requestTimeout);
  }

  static Future<http.Response> put(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final headers = await authHeaders();
    return _client
        .put(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(requestTimeout);
  }

  static Future<http.Response> patch(
    String endpoint,
    Map<String, dynamic> data,
  ) async {
    final headers = await authHeaders();
    return _client
        .patch(
          Uri.parse('$baseUrl$endpoint'),
          headers: headers,
          body: jsonEncode(data),
        )
        .timeout(requestTimeout);
  }

  static Future<http.Response> delete(String endpoint) async {
    final headers = await authHeaders();
    return _client
        .delete(Uri.parse('$baseUrl$endpoint'), headers: headers)
        .timeout(requestTimeout);
  }
}
