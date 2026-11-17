import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Moves a [PhotoGallery] between photos from outside, and tells you which
/// photo is showing.
///
/// It notifies its listeners when [index] changes. Use one controller per
/// gallery. Dispose it when you no longer need it.
class PhotoGalleryController extends ChangeNotifier {
  /// Creates a controller that starts at photo [initialIndex].
  PhotoGalleryController({int initialIndex = 0})
      : assert(initialIndex >= 0),
        _index = initialIndex;

  _PhotoGalleryState? _gallery;
  int _index;

  /// The photo showing (or most of the way into view), from 0.
  int get index => _index;

  /// Whether a gallery is using this controller.
  bool get isAttached => _gallery != null;

  /// Goes to the next photo. In a looping gallery, the last photo is
  /// followed by the first.
  Future<void> next({
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutCubic,
  }) async =>
      _gallery?._step(1, duration, curve);

  /// Goes to the previous photo. In a looping gallery, the first photo is
  /// preceded by the last.
  Future<void> previous({
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutCubic,
  }) async =>
      _gallery?._step(-1, duration, curve);

  /// Animates to photo [index].
  Future<void> animateTo(
    int index, {
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutCubic,
  }) async =>
      _gallery?._animateTo(index, duration, curve);

  /// Shows photo [index] straight away.
  void jumpTo(int index) => _gallery?._jumpTo(index);

  // The most recent PhotoGallery to attach wins. When a gallery is rebuilt with a
  // new key, the new one attaches before the old one is disposed.
  void _attach(_PhotoGalleryState gallery) => _gallery = gallery;

  void _detach(_PhotoGalleryState gallery) {
    if (identical(_gallery, gallery)) _gallery = null;
  }

  void _setIndex(int value) {
    if (value == _index) return;
    _index = value;
    notifyListeners();
  }
}

/// Swipe between photos, each of which can be zoomed.
///
/// Build each page with a [ZoomablePhoto]: while a photo is zoomed, dragging
/// moves it, and once its edge is in view the next drag turns the page.
///
/// ```dart
/// PhotoGallery(
///   itemCount: urls.length,
///   itemBuilder: (context, index) =>
///       ZoomablePhoto(image: NetworkImage(urls[index])),
/// )
/// ```
///
/// On desktop and the web, the left and right arrow keys (or up and down,
/// for a vertical gallery) turn the page while the gallery has focus.
class PhotoGallery extends StatefulWidget {
  /// Creates a gallery of [itemCount] pages built by [itemBuilder].
  const PhotoGallery({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.initialIndex,
    this.onPageChanged,
    this.loop = false,
    this.scrollDirection = Axis.horizontal,
    this.pageSpacing = 16,
    this.keyboardNavigation = true,
    this.autofocus = true,
  })  : assert(itemCount >= 0),
        assert(pageSpacing >= 0);

  /// How many photos there are.
  final int itemCount;

  /// Builds the page for photo `index`, usually a [ZoomablePhoto].
  final IndexedWidgetBuilder itemBuilder;

  /// Moves between photos from outside.
  final PhotoGalleryController? controller;

  /// The photo to start at. Defaults to the [controller]'s index, or 0.
  final int? initialIndex;

  /// Called with the index of the photo that's showing when it changes.
  final ValueChanged<int>? onPageChanged;

  /// Whether swiping past the last photo goes back to the first (and the
  /// other way round).
  final bool loop;

  /// Whether pages are side by side ([Axis.horizontal]) or stacked
  /// ([Axis.vertical]).
  final Axis scrollDirection;

  /// The gap between photos while swiping, in pixels.
  final double pageSpacing;

  /// Whether the arrow keys turn the page.
  final bool keyboardNavigation;

  /// Whether the gallery takes keyboard focus when it appears, so the arrow
  /// keys work straight away.
  final bool autofocus;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late PageController _pages;
  late int _index;

  // Changes whenever [_pages] is replaced. The page view is keyed on it, so
  // it starts afresh at the new controller's initial page (a reused scroll
  // position would keep the old page instead).
  int _generation = 0;

  // A looping gallery starts far from page 0, so it can scroll both ways.
  static const _loopBase = 10000;

  int get _count => widget.itemCount;
  bool get _looping => widget.loop && _count > 1;

  int _pageFor(int index) => _looping ? _loopBase * _count + index : index;
  int _indexFor(int page) => _looping ? page % _count : page;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    final start = widget.initialIndex ?? widget.controller?.index ?? 0;
    _index = _count == 0 ? 0 : start.clamp(0, _count - 1);
    _pages = PageController(initialPage: _pageFor(_index));
    _notifyController();
  }

  @override
  void didUpdateWidget(PhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
      _notifyController();
    }
    final loopChanged = (oldWidget.loop && oldWidget.itemCount > 1) != _looping;
    if (loopChanged || oldWidget.itemCount != widget.itemCount) {
      _index = _count == 0 ? 0 : _index.clamp(0, _count - 1);
      if (loopChanged || _looping) {
        final old = _pages;
        _pages = PageController(initialPage: _pageFor(_index));
        _generation++;
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      _notifyController();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _pages.dispose();
    super.dispose();
  }

  void _notifyController() {
    final controller = widget.controller;
    if (controller == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller._setIndex(_index);
    });
  }

  void _onPageChanged(int page) {
    final index = _indexFor(page);
    if (index == _index) return;
    _index = index;
    widget.controller?._setIndex(index);
    widget.onPageChanged?.call(index);
  }

  int get _currentPage =>
      _pages.hasClients ? (_pages.page ?? 0).round() : _pageFor(_index);

  Future<void> _step(int by, Duration duration, Curve curve) async {
    if (!_pages.hasClients || _count == 0) return;
    final page = _currentPage + by;
    if (!_looping && (page < 0 || page >= _count)) return;
    await _pages.animateToPage(page, duration: duration, curve: curve);
  }

  Future<void> _animateTo(int index, Duration duration, Curve curve) async {
    if (!_pages.hasClients || _count == 0) return;
    final target = index.clamp(0, _count - 1);
    var page = _pageFor(target);
    if (_looping) {
      // Take the shorter way round.
      final current = _currentPage;
      page = current - _indexFor(current) + target;
      if (page - current > _count / 2) page -= _count;
      if (current - page > _count / 2) page += _count;
    }
    await _pages.animateToPage(page, duration: duration, curve: curve);
  }

  void _jumpTo(int index) {
    if (_count == 0) return;
    final target = index.clamp(0, _count - 1);
    if (!_pages.hasClients) {
      _index = target;
      return;
    }
    final current = _currentPage;
    _pages.jumpToPage(
        _looping ? current - _indexFor(current) + target : _pageFor(target));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.keyboardNavigation ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final horizontal = widget.scrollDirection == Axis.horizontal;
    final key = event.logicalKey;
    final back =
        horizontal ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp;
    final forward = horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    if (key == back) {
      _step(-1, const Duration(milliseconds: 300), Curves.easeOutCubic);
      return KeyEventResult.handled;
    }
    if (key == forward) {
      _step(1, const Duration(milliseconds: 300), Curves.easeOutCubic);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.scrollDirection == Axis.horizontal;
    final gap = widget.pageSpacing;

    return Focus(
      autofocus: widget.autofocus && widget.keyboardNavigation,
      onKeyEvent: _onKey,
      child: LayoutBuilder(builder: (context, constraints) {
        // The page view is wider than the gallery by one gap, and each page
        // has half a gap on each side, so photos sit edge to edge with the
        // gallery but have a gap between them while swiping.
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return ClipRect(
          child: OverflowBox(
            minWidth: horizontal ? width + gap : width,
            maxWidth: horizontal ? width + gap : width,
            minHeight: horizontal ? height : height + gap,
            maxHeight: horizontal ? height : height + gap,
            child: PageView.builder(
              key: ValueKey(_generation),
              controller: _pages,
              scrollDirection: widget.scrollDirection,
              itemCount: _looping ? null : _count,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, page) {
                final index = _indexFor(page);
                if (index < 0 || index >= _count) return null;
                return Padding(
                  padding: horizontal
                      ? EdgeInsets.symmetric(horizontal: gap / 2)
                      : EdgeInsets.symmetric(vertical: gap / 2),
                  child: KeyedSubtree(
                    key: ValueKey(index),
                    child: widget.itemBuilder(context, index),
                  ),
                );
              },
            ),
          ),
        );
      }),
    );
  }
}
