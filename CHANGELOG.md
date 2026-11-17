## 0.1.0

* First version.
* `ZoomablePhoto`: pinch, trackpad pinch and mouse-wheel zoom; double-tap to zoom in where you tap; drag to move a zoomed photo, with momentum when you flick it. The zoom stretches a little past its limits and springs back. Works with any `ImageProvider`, or any widget with `ZoomablePhoto.child`.
* `ZoomablePhotoController`: read the zoom, `zoomTo`, `zoomIn`, `zoomOut` and `reset`.
* `PhotoGallery`: swipe between photos. While a photo is zoomed, dragging moves it, and at its edge the next drag turns the page. Optional looping, a gap between photos while swiping, arrow-key navigation, and `PhotoGalleryController` (`next`, `previous`, `animateTo`, `jumpTo`).
* Loading and error builders, `heroTag` for Hero animations, and a `semanticLabel` for screen readers.
* No dependencies, and no `package:flutter/material.dart`: works in Material, Cupertino and plain-widget apps.
