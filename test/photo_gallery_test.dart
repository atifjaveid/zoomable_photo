import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_photo/zoomable_photo.dart';

import 'helpers.dart';

void main() {
  late List<ZoomablePhotoController> photos;
  late PhotoGalleryController gallery;

  setUp(() {
    photos = List.generate(3, (_) => ZoomablePhotoController());
    gallery = PhotoGalleryController();
  });
  tearDown(() {
    for (final p in photos) {
      p.dispose();
    }
    gallery.dispose();
  });

  Widget build({
    bool loop = false,
    ValueChanged<int>? onPageChanged,
    double pageSpacing = 16,
    int? initialIndex,
  }) =>
      host(PhotoGallery(
        itemCount: 3,
        controller: gallery,
        loop: loop,
        initialIndex: initialIndex,
        pageSpacing: pageSpacing,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) => ZoomablePhoto.child(
          childSize: const Size(800, 600),
          controller: photos[index],
          child: Text('Photo $index'),
        ),
      ));

  testWidgets('swiping turns the page', (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(build(onPageChanged: pages.add));
    await tester.fling(find.byType(PhotoGallery), const Offset(-250, 0), 1000);
    await tester.pumpAndSettle();
    expect(gallery.index, 1);
    expect(pages, [1]);
    expect(find.text('Photo 1'), findsOneWidget);
  });

  testWidgets('each photo fills the gallery, with a gap while swiping',
      (tester) async {
    await tester.pumpWidget(build(pageSpacing: 20));
    expect(tester.getRect(find.byType(ZoomablePhoto)),
        const Rect.fromLTWH(0, 0, 400, 300));
    final drag = await tester.startGesture(const Offset(300, 150));
    await drag.moveBy(const Offset(-50, 0));
    await drag.moveBy(const Offset(-50, 0));
    await tester.pump();
    final first = tester.getRect(find.byType(ZoomablePhoto).first);
    final second = tester.getRect(find.byType(ZoomablePhoto).last);
    expect(second.left - first.right, closeTo(20, 0.01));
    await drag.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dragging a zoomed photo moves it instead of the page',
      (tester) async {
    await tester.pumpWidget(build());
    photos[0].zoomTo(2, animate: false);
    await tester.pump();
    await tester.timedDrag(find.byType(PhotoGallery), const Offset(-120, 0),
        const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(gallery.index, 0);
    expect(photos[0].value.offset.dx, lessThan(-90));
  });

  testWidgets('at the edge of a zoomed photo, dragging turns the page',
      (tester) async {
    await tester.pumpWidget(build());
    // Zoom so the photo's right edge is at the right of the view.
    photos[0].zoomTo(2, focalPoint: const Offset(400, 150), animate: false);
    await tester.pump();
    expect(photos[0].value.offset.dx, -200);
    await tester.fling(find.byType(PhotoGallery), const Offset(-250, 0), 1000);
    await tester.pumpAndSettle();
    expect(gallery.index, 1);
  });

  testWidgets('the controller moves between photos', (tester) async {
    await tester.pumpWidget(build());
    unawaited(gallery.next());
    await tester.pumpAndSettle();
    expect(gallery.index, 1);
    gallery.jumpTo(2);
    await tester.pump();
    expect(gallery.index, 2);
    expect(find.text('Photo 2'), findsOneWidget);
    // Without looping, there's nothing after the last photo.
    unawaited(gallery.next());
    await tester.pumpAndSettle();
    expect(gallery.index, 2);
    unawaited(gallery.animateTo(0));
    await tester.pumpAndSettle();
    expect(gallery.index, 0);
  });

  testWidgets('a looping gallery goes round', (tester) async {
    await tester.pumpWidget(build(loop: true));
    unawaited(gallery.previous());
    await tester.pumpAndSettle();
    expect(gallery.index, 2);
    expect(find.text('Photo 2'), findsOneWidget);
    unawaited(gallery.next());
    await tester.pumpAndSettle();
    expect(gallery.index, 0);
    // animateTo takes the shorter way round: 0 to 2 is one step back.
    unawaited(gallery.animateTo(2));
    await tester.pumpAndSettle();
    expect(gallery.index, 2);
  });

  testWidgets('looping can be switched on and off on any photo',
      (tester) async {
    await tester.pumpWidget(build());
    gallery.jumpTo(1);
    await tester.pump();
    await tester.pumpWidget(build(loop: true));
    await tester.pump();
    expect(find.text('Photo 1'), findsOneWidget);
    expect(gallery.index, 1);
    unawaited(gallery.previous());
    await tester.pumpAndSettle();
    unawaited(gallery.previous());
    await tester.pumpAndSettle();
    expect(gallery.index, 2); // Went round from 0 to the last photo.

    await tester.pumpWidget(build());
    await tester.pump();
    expect(find.text('Photo 2'), findsOneWidget);
    expect(gallery.index, 2);
  });

  testWidgets('starts at initialIndex', (tester) async {
    await tester.pumpWidget(build(initialIndex: 2));
    await tester.pump();
    expect(find.text('Photo 2'), findsOneWidget);
    expect(gallery.index, 2);
  });

  testWidgets('the arrow keys turn the page', (tester) async {
    await tester.pumpWidget(build());
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(gallery.index, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(gallery.index, 0);
  });

  testWidgets('a photo that scrolls away starts fitted again', (tester) async {
    await tester.pumpWidget(build());
    photos[0].zoomTo(2, animate: false);
    await tester.pump();
    unawaited(gallery.next());
    await tester.pumpAndSettle();
    unawaited(gallery.previous());
    await tester.pumpAndSettle();
    expect(photos[0].scale, 1);
  });
}
