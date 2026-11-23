import 'package:flutter/material.dart';

/// Clips overflow only along the scrollable [axis] while letting focus halos
/// and scale animations bleed freely along the cross axis.
class TvAxisClipRect extends StatelessWidget {
  const TvAxisClipRect({
    super.key,
    required this.axis,
    required this.child,
    this.crossAxisBleed = 36.0,
  });

  final Axis axis;
  final Widget child;
  final double crossAxisBleed;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      clipper: _AxisOnlyClipper(axis, crossAxisBleed),
      child: child,
    );
  }
}

class _AxisOnlyClipper extends CustomClipper<Rect> {
  const _AxisOnlyClipper(this.axis, this.crossAxisBleed);

  final Axis axis;
  final double crossAxisBleed;

  @override
  Rect getClip(Size size) {
    return switch (axis) {
      Axis.horizontal => Rect.fromLTRB(
          0,
          -crossAxisBleed,
          size.width,
          size.height + crossAxisBleed,
        ),
      Axis.vertical => Rect.fromLTRB(
          -crossAxisBleed,
          0,
          size.width + crossAxisBleed,
          size.height,
        ),
    };
  }

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) {
    if (oldClipper is! _AxisOnlyClipper) return true;
    return oldClipper.axis != axis ||
        oldClipper.crossAxisBleed != crossAxisBleed;
  }
}
