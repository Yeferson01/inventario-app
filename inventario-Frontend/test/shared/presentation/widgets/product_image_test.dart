import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/shared/presentation/widgets/product_image.dart';

void main() {
  testWidgets('missing barcode keeps placeholder and creates no image provider',
      (tester) async {
    var providerCalls = 0;

    await tester.pumpWidget(
      _host(
        ProductImage(
          barcode: null,
          imageProviderFactory: (_) {
            providerCalls += 1;
            return _ControlledImageProvider();
          },
        ),
      ),
    );

    expect(providerCalls, 0);
    expect(find.byKey(const Key('product-image-placeholder')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows placeholder until the image frame completes',
      (tester) async {
    final provider = _ControlledImageProvider();

    await tester.pumpWidget(
      _host(
        ProductImage(
          barcode: '7622201764999',
          imageProviderFactory: (_) => provider,
        ),
      ),
    );

    expect(find.byKey(const Key('product-image-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('product-image-loaded')), findsNothing);

    final image = await _createImage();
    provider.complete(ImageInfo(image: image));
    await tester.pump();

    expect(find.byKey(const Key('product-image-loaded')), findsOneWidget);
    expect(find.byKey(const Key('product-image-placeholder')), findsNothing);
  });

  testWidgets('image failure silently keeps the fallback', (tester) async {
    final provider = _ControlledImageProvider();

    await tester.pumpWidget(
      _host(
        ProductImage(
          barcode: '7622201764999',
          imageProviderFactory: (_) => provider,
        ),
      ),
    );
    provider.fail(StateError('simulated image failure'));
    await tester.pump();

    expect(find.byKey(const Key('product-image-placeholder')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<ui.Image> _createImage() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1, 1),
    Paint()..color = Colors.blue,
  );
  return recorder.endRecording().toImage(1, 1);
}

class _ControlledImageProvider extends ImageProvider<_ControlledImageProvider> {
  final Completer<ImageInfo> _completer = Completer<ImageInfo>();

  void complete(ImageInfo image) => _completer.complete(image);

  void fail(Object error) => _completer.completeError(error);

  @override
  Future<_ControlledImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_ControlledImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ControlledImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_completer.future);
  }
}
