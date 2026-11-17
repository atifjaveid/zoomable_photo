import 'package:flutter/gestures.dart';

/// A scale (pinch and pan) recognizer that works inside a page view.
///
/// With one finger it decides early, before a page view's drag would win:
/// it claims the drag when the photo can move that way, and steps aside
/// when the photo already shows its edge there, so the page view turns the
/// page instead. Two fingers always pinch.
class PhotoScaleGestureRecognizer extends ScaleGestureRecognizer {
  /// Creates a recognizer. [canPan] says whether the photo can move by a
  /// finger movement.
  PhotoScaleGestureRecognizer({super.debugOwner, required this.canPan});

  /// Whether the photo can move by the given finger movement.
  final bool Function(Offset delta) canPan;

  final Map<int, Offset> _downPositions = {};
  bool _decided = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (_downPositions.isEmpty) _decided = false;
    _downPositions[event.pointer] = event.position;
    // A second finger means a pinch: claim it.
    if (_downPositions.length > 1 && !_decided) {
      _decided = true;
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    final down = _downPositions[event.pointer];
    if (!_decided &&
        down != null &&
        _downPositions.length == 1 &&
        event is PointerMoveEvent) {
      final delta = event.position - down;
      // Decide at half the touch slop, before drag recognizers (which
      // accept at the full slop) can claim the gesture.
      if (delta.distance > computeHitSlop(event.kind, gestureSettings) / 2) {
        _decided = true;
        if (canPan(delta)) {
          resolve(GestureDisposition.accepted);
        } else {
          resolve(GestureDisposition.rejected);
          return;
        }
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downPositions.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downPositions.clear();
    _decided = false;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  String get debugDescription => 'photo scale';
}
