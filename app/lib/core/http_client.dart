// Shared HTTP helpers: 10-second timeout, exactly one retry, never throw
// to callers — a failed request returns the raw response (or null for GET)
// and the repository turns that into a Result.
//
// WEB PROXY (browsers only): Animeify's API and the file-host pages send
// no CORS headers, so a browser cannot read them directly — every fetch
// would fail. On web, requests are routed through a tiny proxy that
// forwards the method + body and adds `Access-Control-Allow-Origin: *`.
// Contract: `{proxy}?url=<url-encoded target>`.
//   - Empty (default): direct requests. Works on Android; on web the
//     app shows its honest "could not load" error with Retry.
//   - Set to a Cloudflare Worker (free) or Firebase Function URL to make
//     the web build work. Android ignores this and always goes direct.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

const _timeout = Duration(seconds: 10);

const String kWebProxyBase = '';

Uri _route(Uri uri) {
  if (!kIsWeb || kWebProxyBase.isEmpty) return uri;
  return Uri.parse(
      '$kWebProxyBase?url=${Uri.encodeComponent(uri.toString())}');
}

Future<http.Response?> httpGet(Uri uri, {Map<String, String>? headers}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final res =
          await http.get(_route(uri), headers: headers).timeout(_timeout);
      return res;
    } catch (_) {
      if (attempt == 1) return null;
    }
  }
  return null;
}

Future<http.Response?> httpPost(Uri uri, Map<String, String> body,
    {Map<String, String>? headers}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final res = await http
          .post(_route(uri), body: body, headers: headers)
          .timeout(_timeout);
      return res;
    } catch (_) {
      if (attempt == 1) return null;
    }
  }
  return null;
}

/// Lenient JSON decode: Animeify answers sometimes start with blank lines.
dynamic decodeJsonLoose(String body) {
  try {
    return jsonDecode(body.trim());
  } catch (_) {
    return null;
  }
}
