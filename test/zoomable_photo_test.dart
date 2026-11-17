import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_photo/zoomable_photo.dart';

import 'helpers.dart';

/// An 800 × 600 box, fitted to 400 × 300 in [host].
Widget photo({
  ZoomablePhotoController? controller,
  VoidCallback? onTap,
  ValueChanged<double>? onScaleChanged,
  double maxScale = 4,
  double? doubleTapScale = 2.5,
}) =>
    host(ZoomablePhoto.child(
      childSize: const Size(800, 600),
      controller: controller,
      onTap: onTap,
      onScaleChanged: onScaleChanged,
      maxScale: maxScale,
      doubleTapScale: doubleTapScale,
      child: const ColoredBox(color: Color(0xFF3366CC)),
    ));

Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

void main() {
  late ZoomablePhotoController controller;
  setUp(() => controller = ZoomablePhotoController());
  tearDown(() => controller.dispose());

  testWidgets('starts fitted and centred', (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    await tester.pump();
    expect(controller.value, PhotoTransform.identity);
    expect(controller.isAttached, isTrue);
    expect(controller.isZoomed, isFalse);
  });

  testWidgets('double-tap zooms in where you tap, and back out',
      (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    const tap = Offset(240, 180);
    await doubleTapAt(tester, tap);
    expect(controller.scale, closeTo(2.5, 1e-9));
    // The tapped point stays under the finger: it was 40, 30 from the
    // centre, so the photo moved by -1.5 × that.
    expect(controller.value.offset.dx, closeTo(-60, 1e-6));
    expect(controller.value.offset.dy, closeTo(-45, 1e-6));

    await doubleTapAt(tester, tap);
    expect(controller.value, PhotoTransform.identity);
  });

  testWidgets('zooming never leaves a gap the photo could cover',
      (tester) async {
    // 800 × 400 fits a 400 × 300 view as 400 × 200, with bands above and
    // below. Double-tap in the top band.
    await tester.pumpWidget(host(ZoomablePhoto.child(
      childSize: const Size(800, 400),
      controller: controller,
      child: const ColoredBox(color: Color(0xFF3366CC)),
    )));
    await doubleTapAt(tester, const Offset(200, 10));
    // Zooming around that point would pull the photo's top edge down to
    // y = 10 + 140 × 2.5; instead it stops with the top edge at the top of
    // the view (at 2.5× the photo is 500 high, so it can move 100).
    expect(controller.scale, closeTo(2.5, 1e-9));
    expect(controller.value.offset, const Offset(0, 100));
  });

  testWidgets('double-tap zoom can be turned off', (tester) async {
    await tester
        .pumpWidget(photo(controller: controller, doubleTapScale: null));
    await doubleTapAt(tester, const Offset(200, 150));
    expect(controller.scale, 1);
  });

  testWidgets('pinching zooms', (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    final a = await tester.startGesture(const Offset(150, 150));
    final b = await tester.startGesture(const Offset(250, 150));
    for (var step = 1; step <= 10; step++) {
      await a.moveTo(Offset(150 - 5.0 * step, 150));
      await b.moveTo(Offset(250 + 5.0 * step, 150));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    // The fingers went from 100 to 200 apart.
    expect(controller.scale, closeTo(2, 0.01));
  });

  testWidgets('pinching past the limit springs back to it', (tester) async {
    await tester.pumpWidget(photo(controller: controller, maxScale: 2));
    final a = await tester.startGesture(const Offset(180, 150));
    final b = await tester.startGesture(const Offset(220, 150));
    for (var step = 1; step <= 10; step++) {
      await a.moveTo(Offset(180 - 10.0 * step, 150));
      await b.moveTo(Offset(220 + 10.0 * step, 150));
      await tester.pump();
    }
    expect(controller.scale, greaterThan(2)); // Stretched past the limit.
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(controller.scale, closeTo(2, 1e-9));
  });

  testWidgets('the mouse wheel zooms where the pointer is', (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    const at = Offset(300, 100);
    await tester.sendEventToBinding(mouse.hover(at));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -300)));
    await tester.pump();
    final scale = controller.scale;
    expect(scale, greaterThan(2.5));
    // The point under the pointer stayed put.
    expect(controller.value.offset.dx, closeTo(-100 * (scale - 1), 1e-6));
    expect(controller.value.offset.dy, closeTo(50 * (scale - 1), 1e-6));

    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 3000)));
    await tester.pump();
    expect(controller.value, PhotoTransform.identity);
  });

  testWidgets('dragging moves a zoomed photo, but not a fitted one',
      (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    await tester.drag(find.byType(ZoomablePhoto), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(controller.value, PhotoTransform.identity);

    controller.zoomTo(2, animate: false);
    await tester.pump();
    await tester.timedDrag(find.byType(ZoomablePhoto), const Offset(-80, -40),
        const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(controller.value.offset.dx, lessThan(-60));
    expect(controller.value.offset.dy, lessThan(-25));
  });

  testWidgets('a flick keeps the photo gliding', (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    controller.zoomTo(3, animate: false);
    await tester.pump();
    await tester.fling(find.byType(ZoomablePhoto), const Offset(-60, 0), 1500);
    await tester.pumpAndSettle();
    // Further than the finger moved, but still inside the photo's edges.
    expect(controller.value.offset.dx, lessThan(-80));
    expect(controller.value.offset.dx, greaterThanOrEqualTo(-400));
  });

  testWidgets('the controller zooms within the limits and resets',
      (tester) async {
    final scales = <double>[];
    await tester
        .pumpWidget(photo(controller: controller, onScaleChanged: scales.add));
    controller.zoomTo(10);
    await tester.pumpAndSettle();
    expect(controller.scale, 4);
    expect(controller.isZoomed, isTrue);
    expect(scales.last, 4);

    controller.zoomOut(factor: 2);
    await tester.pumpAndSettle();
    expect(controller.scale, 2);

    controller.reset();
    await tester.pumpAndSettle();
    expect(controller.value, PhotoTransform.identity);
    expect(scales.last, 1);
  });

  testWidgets('a single tap calls onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(photo(onTap: () => taps++));
    await tester.tapAt(const Offset(200, 150));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
    expect(taps, 1);
  });

  testWidgets('a controller moves to a new photo and detaches', (tester) async {
    await tester.pumpWidget(photo(controller: controller));
    expect(controller.isAttached, isTrue);
    await tester.pumpWidget(host(const SizedBox()));
    expect(controller.isAttached, isFalse);
    controller.zoomTo(2); // Does nothing without a photo.
    expect(controller.scale, 1);
  });

  group('images', () {
    testWidgets('are fitted using their size', (tester) async {
      final image = await makeImage(tester, 200, 100);
      await tester.pumpWidget(host(ZoomablePhoto(
        image: TestImageProvider(image),
        controller: controller,
      )));
      await tester.pump();
      // 200 × 100 fits a 400 × 300 view as 400 × 200.
      expect(tester.getSize(find.byType(Image)), const Size(400, 200));
      expect(tester.getTopLeft(find.byType(Image)), const Offset(0, 50));

      controller.zoomTo(2, animate: false);
      await tester.pump();
      expect(tester.getSize(find.byType(Image)), const Size(800, 400));
    });

    testWidgets('show the loading and error builders', (tester) async {
      await tester.pumpWidget(host(ZoomablePhoto(
        image: PendingImageProvider(),
        loadingBuilder: (context, progress) => const Text('Loading'),
      )));
      expect(find.text('Loading'), findsOneWidget);

      await tester.pumpWidget(host(ZoomablePhoto(
        image: PendingImageProvider(error: Exception('no')),
        errorBuilder: (context, error, stack) => const Text('Failed'),
      )));
      await tester.pump();
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('a new image starts fitted again', (tester) async {
      final first = await makeImage(tester, 200, 100);
      final second = await makeImage(tester, 100, 200);
      await tester.pumpWidget(host(ZoomablePhoto(
          image: TestImageProvider(first), controller: controller)));
      controller.zoomTo(3, animate: false);
      await tester.pump();
      await tester.pumpWidget(host(ZoomablePhoto(
          image: TestImageProvider(second), controller: controller)));
      await tester.pump();
      expect(controller.value, PhotoTransform.identity);
      // 100 × 200 fits a 400 × 300 view as 150 × 300.
      expect(tester.getSize(find.byType(Image)), const Size(150, 300));
    });
  });
}
