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

HttpTransport createTransport() => _UnsupportedTransport();

class _UnsupportedTransport implements HttpTransport {
  @override
  Future<TransportResponse> request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
  }) {
    throw UnsupportedError('HTTP transport is not available on this platform');
  }
}
