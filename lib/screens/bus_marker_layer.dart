import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../palette.dart';
import '../vehicles.dart';

class BusMarkerLayer extends StatefulWidget {
  final LatLng point, estimatedPoint;
  final DateTime? fetchedAt;
  final bool stale, stopped, selected;
  final String label;
  final VoidCallback onTap;
  final Key buttonKey;

  const BusMarkerLayer({
    super.key,
    required this.point,
    required this.estimatedPoint,
    required this.fetchedAt,
    required this.stale,
    required this.stopped,
    required this.selected,
    required this.label,
    required this.onTap,
    required this.buttonKey,
  });

  @override
  State<BusMarkerLayer> createState() => _BusMarkerLayerState();
}

class _BusMarkerLayerState extends State<BusMarkerLayer>
    with SingleTickerProviderStateMixin {
  late final motion = AnimationController(vsync: this);
  late LatLng start = widget.point, end = widget.point;
  bool? reduceMotion;

  LatLng get position => interpolateBusPoint(start, end, motion.value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.disableAnimationsOf(context);
    if (disabled != reduceMotion) {
      reduceMotion = disabled;
      updateMotion();
    }
  }

  @override
  void didUpdateWidget(BusMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.point != oldWidget.point ||
        widget.estimatedPoint != oldWidget.estimatedPoint ||
        widget.stale != oldWidget.stale ||
        widget.stopped != oldWidget.stopped ||
        widget.fetchedAt != oldWidget.fetchedAt) {
      updateMotion();
    }
  }

  void updateMotion() {
    final fetched = widget.fetchedAt;
    final age = fetched == null
        ? busMotionWindow
        : DateTime.now().difference(fetched);
    final remaining = busMotionWindow - (age.isNegative ? Duration.zero : age);
    if (widget.stale ||
        widget.stopped ||
        reduceMotion == true ||
        remaining <= Duration.zero) {
      motion.stop();
      start = end = widget.point;
      return;
    }
    final fraction = remaining.inMilliseconds / busMotionWindow.inMilliseconds;
    final destination = interpolateBusPoint(
      widget.point,
      widget.estimatedPoint,
      fraction,
    );
    if (end == destination) return;
    final current = position;
    // A large GPS correction should start at the new fix immediately.
    start =
        const Distance(calculator: Haversine())
                .distance(current, widget.point) >
            1000
        ? widget.point
        : current;
    end = destination;
    motion.duration = remaining;
    motion.forward(from: 0);
  }

  @override
  void dispose() {
    motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = widget.stale ? Colors.grey.shade700 : green;
    final button = Semantics(
      label: '公交车，${widget.label}',
      selected: selected,
      child: IconButton(
        key: widget.buttonKey,
        onPressed: widget.onTap,
        style: IconButton.styleFrom(
          backgroundColor: selected ? color : Colors.white,
          foregroundColor: selected ? Colors.white : color,
          side: BorderSide(color: selected ? Colors.white : color, width: 2),
          elevation: 2,
          shadowColor: Colors.black45,
        ),
        icon: const Icon(Icons.directions_bus_rounded, size: 22),
      ),
    );
    final width = selected ? 156.0 : 48.0;
    final height = selected ? 78.0 : 48.0;
    return AnimatedBuilder(
      animation: motion,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          if (selected)
            Positioned(
              bottom: 46,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ink,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          SizedBox.square(
            dimension: 48,
            child: Center(
              child: selected
                  ? button
                  : Tooltip(
                      message: widget.label,
                      excludeFromSemantics: true,
                      child: button,
                    ),
            ),
          ),
        ],
      ),
      builder: (_, child) => MarkerLayer(
        markers: [
          Marker(
            point: position,
            width: width,
            height: height,
            alignment: Marker.computePixelAlignment(
              width: width,
              height: height,
              left: width / 2,
              top: height - 24,
            ),
            child: child!,
          ),
        ],
      ),
    );
  }
}
