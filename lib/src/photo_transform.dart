import 'dart:math' as math;
import 'dart:ui' show Offset, Size, lerpDouble;

import 'package:flutter/foundation.dart';

/// How far a photo is zoomed and moved.
///
/// [scale] 1 shows the whole photo fitted to the view (or filling it, with
/// `BoxFit.cover`). [offset] is how far the photo's centre is from the view's
/// centre, in pixels.
@immutable
class PhotoTransform {
  /// Creates a transform.
  const PhotoTransform({this.scale = 1, this.offset = Offset.zero});

  /// The photo fitted to the view and centred.
  static const identity = PhotoTransform();

  /// How much the photo is enlarged: 1 is fitted to the view, 2 twice that.
  final double scale;

  /// How far the photo's centre is from the view's centre, in pixels.
  final Offset offset;

  /// A copy with the given fields replaced.
  PhotoTransform copyWith({double? scale, Offset? offset}) =>
      PhotoTransform(scale: scale ?? this.scale, offset: offset ?? this.offset);

  /// Linearly interpolates between two transforms, for animations.
  static PhotoTransform lerp(PhotoTransform a, PhotoTransform b, double t) =>
      PhotoTransform(
        scale: lerpDouble(a.scale, b.scale, t)!,
        offset: Offset.lerp(a.offset, b.offset, t)!,
      );

  @override
  bool operator ==(Object other) =>
      other is PhotoTransform && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);

  @override
  String toString() =>
      'PhotoTransform(scale: ${scale.toStringAsFixed(3)}, offset: $offset)';
}

/// The geometry of one photo in its view: works out where the photo goes,
/// and keeps it from being dragged out of view.
@immutable
class PhotoGeometry {
  /// Geometry for a photo that is [content] big at scale 1, in a view of
  /// [viewport].
  const PhotoGeometry({required this.viewport, required this.content});

  /// The size of the view.
  final Size viewport;

  /// The size of the photo at scale 1 (fitted to the view).
  final Size content;

  /// The photo's size at [scale].
  Size scaledContent(double scale) => content * scale;

  /// How far the photo's centre can move from the view's centre at [scale]:
  /// zero along an axis where the photo fits in the view (it stays centred).
  Offset maxOffset(double scale) {
    final size = scaledContent(scale);
    return Offset(
      math.max(0, (size.width - viewport.width) / 2),
      math.max(0, (size.height - viewport.height) / 2),
    );
  }

  /// [transform] with its offset limited, so the photo never leaves a gap
  /// at an edge it could cover.
  PhotoTransform clamp(PhotoTransform transform) {
    final limit = maxOffset(transform.scale);
    return transform.copyWith(
      offset: Offset(
        transform.offset.dx.clamp(-limit.dx, limit.dx).toDouble(),
        transform.offset.dy.clamp(-limit.dy, limit.dy).toDouble(),
      ),
    );
  }

  /// The point on the photo (in photo pixels at scale 1, from its centre)
  /// that is under [viewPoint].
  Offset photoPointAt(Offset viewPoint, PhotoTransform transform) =>
      (viewPoint - _centre - transform.offset) / transform.scale;

  /// The transform at [scale] that keeps the point under [focalPoint] where
  /// it is. Not clamped.
  PhotoTransform zoomAround(
    PhotoTransform from,
    double scale,
    Offset focalPoint,
  ) {
    final point = photoPointAt(focalPoint, from);
    return PhotoTransform(
      scale: scale,
      offset: focalPoint - _centre - point * scale,
    );
  }

  /// Where the photo is drawn: its top-left corner and size in the view.
  Offset topLeft(PhotoTransform transform) {
    final size = scaledContent(transform.scale);
    return _centre + transform.offset - Offset(size.width / 2, size.height / 2);
  }

  /// Whether a drag of [delta] (finger movement) can move the photo, along
  /// the axis the drag mostly follows. False when the photo already shows
  /// its edge on that side, so a gallery can turn the page instead.
  bool canPan(PhotoTransform transform, Offset delta) {
    const tolerance = 0.5;
    final limit = maxOffset(transform.scale);
    if (delta.dx.abs() >= delta.dy.abs()) {
      if (delta.dx == 0) return false;
      return delta.dx < 0
          ? transform.offset.dx > -limit.dx + tolerance
          : transform.offset.dx < limit.dx - tolerance;
    }
    return delta.dy < 0
        ? transform.offset.dy > -limit.dy + tolerance
        : transform.offset.dy < limit.dy - tolerance;
  }

  Offset get _centre => Offset(viewport.width / 2, viewport.height / 2);

  @override
  bool operator ==(Object other) =>
      other is PhotoGeometry &&
      other.viewport == viewport &&
      other.content == content;

  @override
  int get hashCode => Object.hash(viewport, content);
}
