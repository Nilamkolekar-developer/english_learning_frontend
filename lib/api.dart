import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Real phone over USB: run `adb reverse tcp:8080 tcp:8080` and keep the default.
/// Emulator: use --dart-define=API_BASE=http://10.0.2.2:8080
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8080');
const _store = FlutterSecureStorage();

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
}

class Api {
  /// Called when the server says the subscription is no longer active (HTTP 402).
  static void Function()? onSubscriptionRequired;

  static Future<void> saveTokens(Map t) async {
    await _store.write(key: 'access', value: t['access_token'] as String);
    await _store.write(key: 'refresh', value: t['refresh_token'] as String);
  }

  static Future<void> clear() => _store.deleteAll();
  static Future<bool> hasSession() async => await _store.read(key: 'refresh') != null;

  static Future<bool> _refresh() async {
    final rt = await _store.read(key: 'refresh');
    if (rt == null) return false;
    final r = await http.post(Uri.parse('$apiBase/auth/refresh'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh_token': rt}));
    if (r.statusCode != 200) return false;
    await saveTokens(jsonDecode(r.body));
    return true;
  }

  static Future<dynamic> request(String method, String path, {Map<String, dynamic>? body, bool retry = true}) async {
    final token = await _store.read(key: 'access');
    final headers = {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
    final uri = Uri.parse('$apiBase$path');
    final payload = body == null ? null : jsonEncode(body);
    final r = switch (method) {
      'GET' => await http.get(uri, headers: headers),
      'PATCH' => await http.patch(uri, headers: headers, body: payload),
      'DELETE' => await http.delete(uri, headers: headers, body: payload),
      _ => await http.post(uri, headers: headers, body: payload),
    };
    if (r.statusCode == 401 && retry && await _refresh()) {
      return request(method, path, body: body, retry: false);
    }
    if (r.statusCode == 402) onSubscriptionRequired?.call();
    if (r.statusCode >= 400) {
      String msg = 'Error ${r.statusCode}';
      try { msg = jsonDecode(r.body)['detail'].toString(); } catch (_) {}
      throw ApiException(r.statusCode, msg);
    }
    return r.body.isEmpty ? null : jsonDecode(r.body);
  }

  /// Downloads raw bytes (e.g. a profile photo). Returns null if there is none.
  static Future<Uint8List?> bytes(String path, {bool retry = true}) async {
    final token = await _store.read(key: 'access');
    try {
      final r = await http.get(Uri.parse('$apiBase$path'),
          headers: {if (token != null) 'Authorization': 'Bearer $token'});
      if (r.statusCode == 401 && retry && await _refresh()) return bytes(path, retry: false);
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }
}