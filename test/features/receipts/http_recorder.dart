import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// An [http.Client] that records the request instead of sending it.
///
/// Hand-written rather than `package:http/testing.dart`'s `MockClient` so the
/// **finalized bytes** are available: the assertions that matter here are about
/// what actually goes on the wire — which multipart fields exist, what the
/// headers are, and that the image bytes are unmodified — and a handler that
/// only sees a re-wrapped `Request` cannot answer the last one confidently.
class RecordingHttpClient extends http.BaseClient {
  RecordingHttpClient({
    this.statusCode = 200,
    String? body,
    this.throws,
    this.delay,
  }) : body =
           body ??
           '{"status":"submitted","submission_id":'
               '"99999999-8888-7777-6666-555555555555"}';

  final int statusCode;
  final String body;

  /// Thrown from [send], to model a dropped connection.
  final Object? throws;

  /// Delays the response, to model a timeout.
  final Duration? delay;

  int requestCount = 0;
  late String lastMethod;
  late Uri lastUrl;
  late Map<String, String> lastHeaders;
  late Uint8List lastBodyBytes;

  /// The body as text, with non-UTF-8 image bytes replaced rather than throwing.
  late String lastBodyText;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    lastMethod = request.method;
    lastUrl = request.url;
    lastBodyBytes = await request.finalize().toBytes();
    // Read after finalize: MultipartRequest adds its boundary content-type
    // there, and the assertion that the header set is exactly three entries is
    // only meaningful once every header the client will actually send is
    // present.
    lastHeaders = Map<String, String>.from(request.headers);
    lastBodyText = latin1.decode(lastBodyBytes, allowInvalid: true);

    if (throws != null) {
      throw throws!;
    }
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }

    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      statusCode,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }

  /// The `name=` of every non-file multipart part, in order.
  List<String> fieldNames() => _partNames(withFilename: false);

  /// The `name=` of every part that carries a `filename=`.
  List<String> fileFieldNames() => _partNames(withFilename: true);

  /// The value of a simple field part.
  String? fieldValue(String name) {
    final RegExp pattern = RegExp(
      'name="$name"\r\n\r\n(.*?)\r\n',
      dotAll: true,
    );
    return pattern.firstMatch(lastBodyText)?.group(1);
  }

  /// The `filename=` of the first file part.
  String? lastFileName() =>
      RegExp('filename="(.*?)"').firstMatch(lastBodyText)?.group(1);

  List<String> _partNames({required bool withFilename}) {
    final RegExp header = RegExp(
      r'content-disposition: form-data; name="([^"]+)"([^\r\n]*)',
      caseSensitive: false,
    );
    return header
        .allMatches(lastBodyText)
        .where(
          (RegExpMatch m) =>
              (m.group(2) ?? '').contains('filename=') == withFilename,
        )
        .map((RegExpMatch m) => m.group(1)!)
        .toList();
  }
}
