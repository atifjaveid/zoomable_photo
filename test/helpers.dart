import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// An image provider that serves [image] straight away, for tests.
class TestImageProvider extends ImageProvider<TestImageProvider> {
  TestImageProvider(this.image);

  final ui.Image image;

  @override
  Future<TestImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          TestImageProvider key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

/// An image provider whose image never arrives, or fails with [error].
class PendingImageProvider extends ImageProvider<PendingImageProvider> {
  PendingImageProvider({this.error});

  final Object? error;

  @override
  Future<PendingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
      PendingImageProvider key, ImageDecoderCallback decode) {
    final failure = error;
    return OneFrameImageStreamCompleter(failure == null
        ? Completer<ImageInfo>().future
        : Future<ImageInfo>.error(failure));
  }
}

/// A decoded image of the given size.
Future<ui.Image> makeImage(WidgetTester tester, int width, int height) async =>
    (await tester
        .runAsync(() => createTestImage(width: width, height: height)))!;

/// Puts [child] in a [width] × [height] box, as the only thing on screen.
Widget host(Widget child, {double width = 400, double height = 300}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, height: height, child: child),
      ),
    );
