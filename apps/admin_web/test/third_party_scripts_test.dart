import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Scripts on this page run with the signed-in administrator's session. A
  // version range ("@^5.24.0") lets the CDN serve whatever was published last,
  // and without an integrity hash the browser runs it unchecked.
  test('third-party scripts and stylesheets are exact versions with SRI', () {
    final html = File('web/index.html').readAsStringSync();
    // Scripts and stylesheets only: <link rel="canonical"> loads nothing.
    final tags =
        RegExp(r'<(?:script|link)\b[^>]*\b(?:src|href)="https?://[^"]+"[^>]*>')
            .allMatches(html)
            .map((match) => match.group(0)!)
            .where(
              (tag) => tag.startsWith('<script') || tag.contains('stylesheet'),
            )
            .toList();

    expect(tags, isNotEmpty, reason: 'the page loads MapLibre and cropperjs');
    for (final tag in tags) {
      final url = RegExp(r'(?:src|href)="([^"]+)"').firstMatch(tag)!.group(1)!;
      expect(
        url,
        isNot(matches(RegExp(r'@[\^~*]|@latest|@\d+(?:\.\d+)?/'))),
        reason: '$url must name one exact version',
      );
      expect(tag, contains('integrity="sha384-'), reason: '$url needs SRI');
      expect(tag, contains('crossorigin="anonymous"'), reason: url);
    }
  });
}
