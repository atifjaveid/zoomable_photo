import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'photo_gesture.dart';
import 'photo_transform.dart';

/// Shows the image loading progress. [progress] is null until the first
/// bytes arrive (and for images that don't report progress).
typedef PhotoLoadingBuilder = Widget Function(
  BuildContext context,
  ImageChunkEvent? progress,
);

/// Shows that an image couldn't be loaded.
typedef PhotoErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
);

/// Controls a [ZoomablePhoto] from outside: read and change the zoom, or go
/// back to the whole photo.
///
/// It notifies its listeners whenever the zoom or position changes. Use one
/// controller per photo. Dispose it when you no longer need it.
class ZoomablePhotoController extends ChangeNotifier {
  /// Creates a controller. Pass it to a [ZoomablePhoto] to use it.
  ZoomablePhotoController();

  _ZoomablePhotoState? _photo;
  PhotoTransform _value = PhotoTransform.identity;

  /// Whether a photo is using this controller.
  bool get isAttached => _photo != null;

  /// The current zoom and position.
  PhotoTransform get value => _value;

  /// The current zoom: 1 shows the whole photo.
  double get scale => _value.scale;

  /// Whether the photo is zoomed in past its starting size.
  bool get isZoomed => _value.scale > (_photo?._minScale ?? 1) + 0.001;

  /// Zooms to [scale], keeping the point at [focalPoint] (in the photo
  /// widget's coordinates) in place. Without a [focalPoint], zooms around
  /// the centre.
  void zoomTo(double scale, {Offset? focalPoint, bool animate = true}) =>
      _photo?._zoomTo(scale, focalPoint: focalPoint, animate: animate);

  /// Zooms in by [factor] around the centre.
  void zoomIn({double factor = 1.5, bool animate = true}) =>
      zoomTo(scale * factor, animate: animate);

  /// Zooms out by [factor] around the centre.
  void zoomOut({double factor = 1.5, bool animate = true}) =>
      zoomTo(scale / factor, animate: animate);

  /// Goes back to the whole photo, centred.
  void reset({bool animate = true}) => _photo?._reset(animate: animate);

  // The most recent ZoomablePhoto to attach wins. When a photo is rebuilt with a
  // new key, the new one attaches before the old one is disposed.
  void _attach(_ZoomablePhotoState photo) => _photo = photo;

  void _detach(_ZoomablePhotoState photo) {
    if (identical(_photo, photo)) _photo = null;
  }

  void _set(PhotoTransform value) {
    if (value == _value) return;
    _value = value;
    notifyListeners();
  }
}

/// A photo the user can zoom and move.
///
/// * Pinch, or use a trackpad pinch, to zoom. Drag to move the zoomed photo.
/// * Double-tap to zoom in where you tap, and again to zoom back out.
/// * Scroll the mouse wheel to zoom where the pointer is.
/// * Flick a zoomed photo to send it gliding.
///
/// It works inside a [PhotoGallery] (or any `PageView`): while the photo is
/// zoomed, dragging moves it, and once its edge is in view the next drag
/// turns the page.
///
/// ```dart
/// ZoomablePhoto(image: NetworkImage('https://example.com/photo.jpg'))
/// ```
///
/// To zoom any widget rather than an image, use [ZoomablePhoto.child].
class ZoomablePhoto extends StatefulWidget {
  /// A zoomable [image]. Its size is read from the image once it loads.
  const ZoomablePhoto({
    super.key,
    required ImageProvider this.image,
    this.fit = BoxFit.contain,
    this.minScale = 1,
    this.maxScale = 4,
    this.doubleTapScale = 2.5,
    this.controller,
    this.onScaleChanged,
    this.onTap,
    this.heroTag,
    this.semanticLabel,
    this.filterQuality = FilterQuality.medium,
    this.loadingBuilder,
    this.errorBuilder,
  })  : child = null,
        childSize = null,
        assert(minScale > 0),
        assert(minScale <= maxScale),
        assert(doubleTapScale == null || doubleTapScale > 0);

  /// Any zoomable widget, such as an SVG or a map, drawn at [childSize]
  /// (scaled to fit the view as [fit] says).
  const ZoomablePhoto.child({
    super.key,
    required Widget this.child,
    required Size this.childSize,
    this.fit = BoxFit.contain,
    this.minScale = 1,
    this.maxScale = 4,
    this.doubleTapScale = 2.5,
    this.controller,
    this.onScaleChanged,
    this.onTap,
    this.heroTag,
    this.semanticLabel,
  })  : image = null,
        filterQuality = FilterQuality.medium,
        loadingBuilder = null,
        errorBuilder = null,
        assert(minScale > 0),
        assert(minScale <= maxScale),
        assert(doubleTapScale == null || doubleTapScale > 0);

  /// The image to show.
  final ImageProvider? image;

  /// The widget to show instead of an image (see [ZoomablePhoto.child]).
  final Widget? child;

  /// The size [child] is laid out at before it's fitted to the view.
  final Size? childSize;

  /// How the photo fits the view at scale 1: [BoxFit.contain] shows all of
  /// it, [BoxFit.cover] fills the view.
  final BoxFit fit;

  /// The smallest zoom, relative to the fitted photo. 1 means the user can't
  /// zoom out past the fitted photo.
  final double minScale;

  /// The largest zoom, relative to the fitted photo.
  final double maxScale;

  /// The zoom a double-tap goes to. A second double-tap goes back to
  /// [minScale]. Null turns double-tap zooming off.
  final double? doubleTapScale;

  /// Controls the zoom from outside, and tells you when it changes.
  final ZoomablePhotoController? controller;

  /// Called with the new zoom whenever it changes.
  final ValueChanged<double>? onScaleChanged;

  /// Called when the photo is tapped once, for example to show or hide
  /// controls.
  final VoidCallback? onTap;

  /// Wraps the photo in a [Hero] with this tag, to animate it from a
  /// thumbnail.
  final Object? heroTag;

  /// A description of the photo for screen readers.
  final String? semanticLabel;

  /// How smoothly the image is scaled. See [Image.filterQuality].
  final FilterQuality filterQuality;

  /// Shown while the image loads. By default nothing is shown.
  final PhotoLoadingBuilder? loadingBuilder;

  /// Shown when the image can't be loaded. By default nothing is shown.
  final PhotoErrorBuilder? errorBuilder;

  @override
  State<ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  PhotoTransform _transform = PhotoTransform.identity;
  PhotoGeometry? _geometry;

  // Image loading.
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _imageSize;
  ImageChunkEvent? _progress;
  Object? _error;
  StackTrace? _errorStack;

  // Gestures.
  PhotoTransform _gestureStart = PhotoTransform.identity;
  Offset _gestureFocal = Offset.zero;
  Offset _doubleTapPosition = Offset.zero;

  // Animations.
  late final AnimationController _animation = AnimationController(vsync: this)
    ..addListener(_onAnimate);
  PhotoTransform _animateFrom = PhotoTransform.identity;
  PhotoTransform _animateTo = PhotoTransform.identity;
  Curve _animateCurve = Curves.easeOutCubic;

  bool _notifyScheduled = false;
  double _reportedScale = 1;

  double get _minScale => widget.minScale;
  double get _maxScale => widget.maxScale;

  Size? get _contentSourceSize =>
      widget.image != null ? _imageSize : widget.childSize;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    _transform = PhotoTransform(scale: _minScale);
    _reportedScale = _minScale;
    _notifyAfterBuild();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(ZoomablePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (widget.image != oldWidget.image) {
      _imageSize = null;
      _error = null;
      _progress = null;
      _animation.stop();
      _transform = PhotoTransform(scale: _minScale);
      _resolveImage();
    }
    if (widget.minScale != oldWidget.minScale ||
        widget.maxScale != oldWidget.maxScale ||
        widget.fit != oldWidget.fit) {
      final scale = _transform.scale.clamp(_minScale, _maxScale).toDouble();
      _transform = _clamp(_transform.copyWith(scale: scale));
    }
    _notifyAfterBuild();
  }

  /// Tells the controller and [ZoomablePhoto.onScaleChanged] about changes
  /// made during a build, once the frame is done (listeners may rebuild
  /// other widgets, which isn't allowed during a build).
  void _notifyAfterBuild() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!mounted) return;
      widget.controller?._set(_transform);
      if (_transform.scale != _reportedScale) {
        _reportedScale = _transform.scale;
        widget.onScaleChanged?.call(_transform.scale);
      }
    });
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _stopListeningToImage();
    _animation.dispose();
    super.dispose();
  }

  // ---- Image loading ----

  void _resolveImage() {
    final provider = widget.image;
    if (provider == null) {
      _stopListeningToImage();
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _imageStream?.key) return;
    _stopListeningToImage();
    _imageStream = stream;
    _imageListener = ImageStreamListener(
      (info, synchronousCall) {
        final size = Size(
          info.image.width / info.scale,
          info.image.height / info.scale,
        );
        info.dispose();
        if (!mounted) return;
        if (synchronousCall) {
          _imageSize = size;
          _error = null;
        } else {
          setState(() {
            _imageSize = size;
            _error = null;
          });
        }
      },
      onChunk: (event) {
        if (mounted) setState(() => _progress = event);
      },
      onError: (error, stack) {
        if (mounted) {
          setState(() {
            _error = error;
            _errorStack = stack;
          });
        }
      },
    );
    stream.addListener(_imageListener!);
  }

  void _stopListeningToImage() {
    final listener = _imageListener;
    if (listener != null) _imageStream?.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }

  // ---- Transform ----

  PhotoTransform _clamp(PhotoTransform transform) =>
      _geometry?.clamp(transform) ?? transform;

  void _setTransform(PhotoTransform value) {
    if (value == _transform) return;
    setState(() => _transform = value);
    widget.controller?._set(value);
    if (value.scale != _reportedScale) {
      _reportedScale = value.scale;
      widget.onScaleChanged?.call(value.scale);
    }
  }

  void _animateToTransform(
    PhotoTransform target, {
    Duration duration = const Duration(milliseconds: 260),
    Curve curve = Curves.easeOutCubic,
  }) {
    _animation.stop();
    if (target == _transform) return;
    _animateFrom = _transform;
    _animateTo = target;
    _animateCurve = curve;
    _animation
      ..duration = duration
      ..forward(from: 0);
  }

  void _onAnimate() {
    final t = _animateCurve.transform(_animation.value);
    _setTransform(PhotoTransform.lerp(_animateFrom, _animateTo, t));
  }

  void _zoomTo(double scale, {Offset? focalPoint, required bool animate}) {
    final geometry = _geometry;
    if (geometry == null) return;
    final target = scale.clamp(_minScale, _maxScale).toDouble();
    final focal = focalPoint ??
        Offset(geometry.viewport.width / 2, geometry.viewport.height / 2);
    final next = geometry.clamp(geometry.zoomAround(_transform, target, focal));
    if (animate) {
      _animateToTransform(next);
    } else {
      _animation.stop();
      _setTransform(next);
    }
  }

  void _reset({required bool animate}) {
    final next = PhotoTransform(scale: _minScale);
    if (animate) {
      _animateToTransform(_clamp(next));
    } else {
      _animation.stop();
      _setTransform(_clamp(next));
    }
  }

  // ---- Gestures ----

  bool _canPan(Offset delta) {
    final geometry = _geometry;
    if (geometry == null) return false;
    // Keep the gesture while an animation (such as a fling) is running, so
    // the user can catch the photo.
    if (_animation.isAnimating) return true;
    return geometry.canPan(_transform, delta);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _animation.stop();
    _gestureStart = _transform;
    _gestureFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final geometry = _geometry;
    if (geometry == null) return;
    // Past the limits the zoom slows down, then springs back on release.
    final scale = _rubberBand(_gestureStart.scale * details.scale);
    final point = geometry.photoPointAt(_gestureFocal, _gestureStart);
    final focal = details.localFocalPoint;
    final viewportCentre =
        Offset(geometry.viewport.width / 2, geometry.viewport.height / 2);
    final next = PhotoTransform(
      scale: scale,
      offset: focal - viewportCentre - point * scale,
    );
    _setTransform(geometry.clamp(next));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    final geometry = _geometry;
    if (geometry == null) return;
    final scale = _transform.scale;
    if (scale < _minScale || scale > _maxScale) {
      final target = scale.clamp(_minScale, _maxScale).toDouble();
      _animateToTransform(geometry
          .clamp(geometry.zoomAround(_transform, target, _gestureFocal)));
      return;
    }
    final velocity = details.velocity.pixelsPerSecond;
    if (details.pointerCount == 0 && velocity.distance > 200) {
      // Glide in the direction of the flick, slowing to a stop.
      const glide = 0.22; // Seconds' worth of the release speed.
      final target = geometry.clamp(
          _transform.copyWith(offset: _transform.offset + velocity * glide));
      final distance = (target.offset - _transform.offset).distance;
      if (distance > 1) {
        final ms = (distance / velocity.distance * 2000).clamp(200, 700);
        _animateToTransform(
          target,
          duration: Duration(milliseconds: ms.round()),
          curve: Curves.decelerate,
        );
      }
    }
  }

  double _rubberBand(double scale) {
    if (scale < _minScale) {
      return _minScale - (_minScale - scale) * 0.35;
    }
    if (scale > _maxScale) {
      return _maxScale + (scale - _maxScale) * 0.35;
    }
    return scale;
  }

  void _onDoubleTap() {
    final zoomed = _transform.scale > _minScale + 0.01;
    final target = widget.doubleTapScale;
    if (target == null) return;
    if (zoomed) {
      _reset(animate: true);
    } else {
      _zoomTo(math.max(target, _minScale),
          focalPoint: _doubleTapPosition, animate: true);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      final delta = scroll.scrollDelta.dy;
      if (delta == 0) return;
      final factor = math.exp(-delta / 300);
      _zoomTo(_transform.scale * factor,
          focalPoint: scroll.localPosition, animate: false);
    });
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final viewport = Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : 0,
        constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
      );
      final source = _contentSourceSize;

      if (source == null || source.isEmpty || viewport.isEmpty) {
        _geometry = null;
        return SizedBox.fromSize(
          size: viewport,
          child: _placeholder(context),
        );
      }

      final content = applyBoxFit(widget.fit, source, viewport).destination;
      final geometry = PhotoGeometry(viewport: viewport, content: content);
      if (geometry != _geometry) {
        _geometry = geometry;
        // Keep the photo in view after a resize.
        final clamped = geometry.clamp(_transform);
        if (clamped != _transform) {
          _transform = clamped;
          _notifyAfterBuild();
        }
      }

      final size = geometry.scaledContent(_transform.scale);
      final topLeft = geometry.topLeft(_transform);

      Widget photo = widget.image != null
          ? Image(
              image: widget.image!,
              fit: BoxFit.fill,
              filterQuality: widget.filterQuality,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            )
          : FittedBox(
              fit: BoxFit.fill,
              child: SizedBox.fromSize(
                size: widget.childSize,
                child: widget.child,
              ),
            );
      if (widget.heroTag != null) {
        photo = Hero(tag: widget.heroTag!, child: photo);
      }

      return Semantics(
        image: true,
        label: widget.semanticLabel,
        child: Listener(
          onPointerSignal: _onPointerSignal,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              PhotoScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  PhotoScaleGestureRecognizer>(
                () => PhotoScaleGestureRecognizer(
                    debugOwner: this, canPan: _canPan),
                (recognizer) => recognizer
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd,
              ),
              if (widget.doubleTapScale != null)
                DoubleTapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        DoubleTapGestureRecognizer>(
                  () => DoubleTapGestureRecognizer(debugOwner: this),
                  (recognizer) => recognizer
                    ..onDoubleTapDown = ((details) =>
                        _doubleTapPosition = details.localPosition)
                    ..onDoubleTap = _onDoubleTap,
                ),
              if (widget.onTap != null)
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(debugOwner: this),
                  (recognizer) => recognizer..onTap = widget.onTap,
                ),
            },
            child: ClipRect(
              child: SizedBox.fromSize(
                size: viewport,
                child: Stack(
                  children: [
                    Positioned(
                      left: topLeft.dx,
                      top: topLeft.dy,
                      width: size.width,
                      height: size.height,
                      child: photo,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _placeholder(BuildContext context) {
    final error = _error;
    if (error != null) {
      return widget.errorBuilder?.call(context, error, _errorStack) ??
          const SizedBox.shrink();
    }
    return widget.loadingBuilder?.call(context, _progress) ??
        const SizedBox.shrink();
  }
}
