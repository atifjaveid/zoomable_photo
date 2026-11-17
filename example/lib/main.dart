// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:zoomable_photo/zoomable_photo.dart';

void main() => runApp(const ExampleApp());

/// A photo from Lorem Picsum (https://picsum.photos), which serves free
/// photos from Unsplash.
class Photo {
  const Photo(this.id, this.author, {this.portrait = false});

  final int id;
  final String author;
  final bool portrait;

  String get url => portrait
      ? 'https://picsum.photos/id/$id/1067/1600'
      : 'https://picsum.photos/id/$id/1600/1067';
}

const photos = [
  Photo(1015, 'Alexey Topolyanskiy'),
  Photo(1018, 'Andrew Ridley'),
  Photo(1036, 'Wolfgang Lutz', portrait: true),
  Photo(1039, 'Oleg Chursin'),
  Photo(1043, 'Christian Joudrey', portrait: true),
  Photo(10, 'Paul Jarvis'),
  Photo(15, 'Paul Jarvis'),
  Photo(16, 'Paul Jarvis', portrait: true),
  Photo(17, 'Paul Jarvis'),
  Photo(28, 'Dan Gold'),
  Photo(29, 'Go Wild', portrait: true),
  Photo(54, 'Nithya Ramanujam'),
];

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.imageFor = _networkImage});

  /// The image for a photo. Tests pass their own.
  final ImageProvider Function(Photo photo) imageFor;

  static ImageProvider _networkImage(Photo photo) => NetworkImage(photo.url);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zoomable_photo example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: PhotoGrid(imageFor: imageFor),
    );
  }
}

/// Thumbnails. Tap one to open the gallery.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({super.key, required this.imageFor});

  final ImageProvider Function(Photo photo) imageFor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('zoomable_photo')),
      body: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () => Navigator.of(context).push(PageRouteBuilder<void>(
            opaque: false,
            transitionDuration: const Duration(milliseconds: 300),
            pageBuilder: (context, animation, _) => FadeTransition(
              opacity: animation,
              child: GalleryPage(initialIndex: index, imageFor: imageFor),
            ),
          )),
          child: Hero(
            tag: photos[index].id,
            child: Image(
              image: imageFor(photos[index]),
              fit: BoxFit.cover,
              semanticLabel: 'Photo by ${photos[index].author}',
              errorBuilder: (context, error, stack) => const ColoredBox(
                color: Colors.black26,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photos full screen: swipe between them, and zoom each one.
class GalleryPage extends StatefulWidget {
  const GalleryPage({
    super.key,
    required this.initialIndex,
    required this.imageFor,
  });

  final int initialIndex;
  final ImageProvider Function(Photo photo) imageFor;

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final _gallery =
      PhotoGalleryController(initialIndex: widget.initialIndex);
  final _zoom = <int, ZoomablePhotoController>{};
  var _showControls = true;
  var _loop = false;

  ZoomablePhotoController _zoomFor(int index) =>
      _zoom.putIfAbsent(index, ZoomablePhotoController.new);

  @override
  void dispose() {
    _gallery.dispose();
    for (final controller in _zoom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoGallery(
              controller: _gallery,
              itemCount: photos.length,
              loop: _loop,
              itemBuilder: (context, index) => ZoomablePhoto(
                image: widget.imageFor(photos[index]),
                controller: _zoomFor(index),
                heroTag: photos[index].id,
                semanticLabel: 'Photo by ${photos[index].author}',
                onTap: () => setState(() => _showControls = !_showControls),
                loadingBuilder: (context, progress) => Center(
                  child: CircularProgressIndicator(
                    value: progress?.expectedTotalBytes == null
                        ? null
                        : progress!.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                  ),
                ),
                errorBuilder: (context, error, stack) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_off, color: Colors.white54, size: 40),
                      SizedBox(height: 8),
                      Text("Couldn't load this photo",
                          style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: _Controls(
                gallery: _gallery,
                zoomFor: _zoomFor,
                loop: _loop,
                wide: wide,
                onLoopChanged: (value) => setState(() => _loop = value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.gallery,
    required this.zoomFor,
    required this.loop,
    required this.wide,
    required this.onLoopChanged,
  });

  final PhotoGalleryController gallery;
  final ZoomablePhotoController Function(int index) zoomFor;
  final bool loop;
  final bool wide;
  final ValueChanged<bool> onLoopChanged;

  @override
  Widget build(BuildContext context) {
    const shade = [Color(0xAA000000), Color(0x00000000)];
    return ListenableBuilder(
      listenable: gallery,
      builder: (context, _) {
        final index = gallery.index;
        final zoom = zoomFor(index);
        return Column(
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: shade,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    const BackButton(color: Colors.white),
                    Expanded(
                      child: Text(
                        '${index + 1} / ${photos.length}   ·   '
                        '${photos[index].author}',
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: loop ? 'Stop looping' : 'Loop',
                      color: loop ? Colors.tealAccent : Colors.white,
                      icon: const Icon(Icons.all_inclusive),
                      onPressed: () => onLoopChanged(!loop),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: shade,
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ListenableBuilder(
                    listenable: zoom,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              tooltip: 'Previous',
                              color: Colors.white,
                              icon: const Icon(Icons.chevron_left),
                              onPressed:
                                  loop || index > 0 ? gallery.previous : null,
                            ),
                            IconButton(
                              tooltip: 'Zoom out',
                              color: Colors.white,
                              icon: const Icon(Icons.zoom_out),
                              onPressed: zoom.isZoomed ? zoom.zoomOut : null,
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${(zoom.scale * 100).round()}%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Zoom in',
                              color: Colors.white,
                              icon: const Icon(Icons.zoom_in),
                              onPressed: zoom.scale < 4 ? zoom.zoomIn : null,
                            ),
                            IconButton(
                              tooltip: 'Next',
                              color: Colors.white,
                              icon: const Icon(Icons.chevron_right),
                              onPressed: loop || index < photos.length - 1
                                  ? gallery.next
                                  : null,
                            ),
                          ],
                        ),
                        if (wide)
                          const Text(
                            'Double-tap or scroll to zoom   ·   drag to move   ·   '
                            'arrow keys to browse',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
