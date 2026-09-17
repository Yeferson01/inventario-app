import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest =
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
  final activityMatch = RegExp(
    r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>(.*?)</activity>',
    dotAll: true,
  ).firstMatch(manifest);

  test('DL-01 product manifest delegates deep links to app_links', () {
    expect(activityMatch, isNotNull);
    final activity = activityMatch!.group(1)!;
    final metadataTags = RegExp(r'<meta-data\b[^>]*/>').allMatches(activity);

    expect(
      metadataTags.any((match) {
        final tag = match.group(0)!;
        return tag.contains('android:name="flutter_deeplinking_enabled"') &&
            tag.contains('android:value="false"');
      }),
      isTrue,
    );
  });

  test('DL-02 productive auth callback intent filter remains present', () {
    expect(activityMatch, isNotNull);
    final activity = activityMatch!.group(1)!;
    final dataTags = RegExp(r'<data\b[^>]*/>').allMatches(activity);

    expect(
      dataTags.any((match) {
        final tag = match.group(0)!;
        return tag.contains('android:scheme="cronosmanagement"') &&
            tag.contains('android:host="auth-callback"');
      }),
      isTrue,
    );
  });
}
