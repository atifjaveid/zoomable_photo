import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zoomable_photo/zoomable_photo.dart';

void main() {
  // A 400 × 300 view with a photo fitted to 400 × 200 (wider than the view's
  // shape, so it has bands above and below).
  const geometry = PhotoGeometry(
    viewport: Size(400, 300),
    content: Size(400, 200),
  );

  group('PhotoGeometry', () {
    test('a fitted photo cannot move', () {
      expect(geometry.maxOffset(1), Offset.zero);
      expect(
        geometry.clamp(const PhotoTransform(offset: Offset(50, -20))),
        PhotoTransform.identity,
      );
    });

    test('a zoomed photo moves only as far as its edges', () {
      // At 2×: 800 × 400 in a 400 × 300 view.
      expect(geometry.maxOffset(2), const Offset(200, 50));
      expect(
        geometry
            .clamp(const PhotoTransform(scale: 2, offset: Offset(500, -80)))
            .offset,
        const Offset(200, -50),
      );
      // At 1.2× the height (240) still fits, so it stays centred vertically.
      expect(geometry.maxOffset(1.2).dy, 0);
    });

    test('zooming keeps the point under the focal point in place', () {
      const from = PhotoTransform(scale: 1.5, offset: Offset(30, 10));
      const focal = Offset(260, 120);
      final before = geometry.photoPointAt(focal, from);
      final to = geometry.zoomAround(from, 3, focal);
      expect(to.scale, 3);
      final after = geometry.photoPointAt(focal, to);
      expect(after.dx, closeTo(before.dx, 1e-9));
      expect(after.dy, closeTo(before.dy, 1e-9));
    });

    test('the photo is drawn centred, moved by the offset', () {
      expect(geometry.topLeft(PhotoTransform.identity), const Offset(0, 50));
      expect(
        geometry
            .topLeft(const PhotoTransform(scale: 2, offset: Offset(-200, 0))),
        const Offset(-400, -50),
      );
    });

    test('canPan is false at an edge, so a gallery can turn the page', () {
      // Fitted: nothing to move.
      expect(geometry.canPan(PhotoTransform.identity, const Offset(-20, 0)),
          isFalse);
      // Zoomed and centred: can move both ways.
      const centred = PhotoTransform(scale: 2);
      expect(geometry.canPan(centred, const Offset(-20, 0)), isTrue);
      expect(geometry.canPan(centred, const Offset(20, 0)), isTrue);
      // Showing the right edge: dragging left (to see more on the right)
      // can't move it, dragging right can.
      const rightEdge = PhotoTransform(scale: 2, offset: Offset(-200, 0));
      expect(geometry.canPan(rightEdge, const Offset(-20, 2)), isFalse);
      expect(geometry.canPan(rightEdge, const Offset(20, 2)), isTrue);
      // A mostly vertical drag is judged on the vertical axis.
      expect(geometry.canPan(rightEdge, const Offset(-5, 30)), isTrue);
    });
  });

  test('PhotoTransform.lerp', () {
    final mid = PhotoTransform.lerp(
      PhotoTransform.identity,
      const PhotoTransform(scale: 3, offset: Offset(100, -40)),
      0.5,
    );
    expect(mid, const PhotoTransform(scale: 2, offset: Offset(50, -20)));
  });
}
