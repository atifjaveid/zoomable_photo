import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_photo/zoomable_photo.dart';
import 'package:zoomable_photo_example/main.dart';

/// Serves a ready-made image, so the test needs no network.
class _TestImage extends ImageProvider<_TestImage> {
  _TestImage(this.image);

  final ui.Image image;

  @override
  Future<_TestImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TestImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
          SynchronousFuture(ImageInfo(image: image.clone())));
}

void main() {
  testWidgets('open a photo, zoom it and move between photos', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final landscape = (await tester
        .runAsync(() => createTestImage(width: 160, height: 107)))!;
    final portrait = (await tester
        .runAsync(() => createTestImage(width: 107, height: 160)))!;
    await tester.pumpWidget(ExampleApp(
      imageFor: (photo) => _TestImage(photo.portrait ? portrait : landscape),
    ));
    await tester.pumpAndSettle();

    // Open the first photo.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.byType(PhotoGallery), findsOneWidget);
    expect(find.textContaining('1 / ${photos.length}'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    // Double-tap to zoom.
    final centre = tester.getCenter(find.byType(PhotoGallery));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centre);
    await tester.pumpAndSettle();
    expect(find.text('250%'), findsOneWidget);

    // The zoom buttons.
    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pumpAndSettle();
    expect(find.text('167%'), findsOneWidget);

    // Next photo, then back.
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 / ${photos.length}'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 / ${photos.length}'), findsOneWidget);

    // Looping: back from the first photo goes to the last.
    await tester.tap(find.byTooltip('Loop'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(find.textContaining('${photos.length} / ${photos.length}'),
        findsOneWidget);

    // Close the gallery.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoGallery), findsNothing);
  });
}
