import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

    expect(tags, isNotEmpty, reason: 'the page loads cropperjs');
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

  // The policy is what stops an injected script reading the administrator's
  // session. Report-only logs and blocks nothing.
  test(
    'the content-security policy is enforced and allows no inline script',
    () {
      final headers = File('web/_headers').readAsLinesSync();
      expect(
        headers.where(
          (line) => line.contains('Content-Security-Policy-Report-Only'),
        ),
        isEmpty,
      );
      final policy = headers.singleWhere(
        (line) => line.trimLeft().startsWith('Content-Security-Policy:'),
      );
      final scripts = RegExp(
        r"script-src ([^;]+)",
      ).firstMatch(policy)!.group(1)!;
      expect(scripts, isNot(contains("'unsafe-inline'")));
      expect(scripts, isNot(contains("'unsafe-eval'")));
      expect(policy, contains("object-src 'none'"));
      expect(policy, contains("frame-ancestors 'none'"));
    },
  );

  // The map library is served from this site. The list was written when the
  // files were taken from the npm release (checked against the registry's own
  // checksum), so an edited or swapped file fails here.
  test('the self-hosted map library is the published release', () {
    const folder = 'web/vendor/maplibre-gl-6.4.1';
    final sums = File('$folder/SHA384SUMS').readAsLinesSync();
    expect(sums, hasLength(4));
    for (final line in sums) {
      final [hash, name] = line.split('  ');
      final digest = sha384.convert(File('$folder/$name').readAsBytesSync());
      expect('sha384-${base64.encode(digest.bytes)}', hash, reason: name);
    }
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains("scriptUrl: '/vendor/maplibre-gl-6.4.1/maplibre-gl.mjs'"),
    );
    expect(
      File('web/index.html').readAsStringSync(),
      isNot(contains('unpkg.com/maplibre-gl')),
      reason: 'a tag here would override the copy the plugin loads',
    );
  });
}
