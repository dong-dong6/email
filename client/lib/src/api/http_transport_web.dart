import 'dart:html';

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

HttpTransport createTransport() => WebTransport();

class WebTransport implements HttpTransport {
  @override
  Future<TransportResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final response = await HttpRequest.request(
      uri.toString(),
      method: method,
      requestHeaders: headers,
      sendData: body,
    );
    return TransportResponse(response.status ?? 0, response.responseText ?? '');
  }
}
