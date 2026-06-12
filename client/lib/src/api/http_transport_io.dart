import 'dart:convert';
import 'dart:io';

class TransportResponse {
  const TransportResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

abstract class HttpTransport {
  Future<TransportResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  });
}

HttpTransport createTransport() => IoTransport();

class IoTransport implements HttpTransport {
  final HttpClient _client = HttpClient();

  @override
  Future<TransportResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      final bytes = utf8.encode(body);
      request.headers.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return TransportResponse(response.statusCode, text);
  }
}
