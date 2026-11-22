import 'package:flutter/material.dart';

import 'app_theme.dart';

class SsuSeal extends StatelessWidget {
  const SsuSeal({super.key, required this.size, this.decorative = false});

  final double size;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    // The seal sits in the top 810 pixels of the 882 × 920 source artwork.
    const sealWidth = 810 / 882;
    const sealHeight = 810 / 920;

    return ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        widthFactor: sealWidth,
        heightFactor: sealHeight,
        child: Image.asset(
          'assets/ssu-logo.png',
          width: size / sealWidth,
          height: size / sealHeight,
          fit: BoxFit.fill,
          semanticLabel: 'Samar State University seal',
          excludeFromSemantics: decorative,
        ),
      ),
    );
  }
}

class SsuRibbonPainter extends CustomPainter {
  const SsuRibbonPainter({this.bottomRight = false, this.base = AppTheme.navy});

  final bool bottomRight;
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (bottomRight) canvas.translate(size.width, size.height);
    canvas.scale(
      bottomRight ? -size.width : size.width,
      bottomRight ? -size.height : size.height,
    );
    final navy = Paint()..color = base;
    final gold = Paint()..color = AppTheme.gold;

    canvas.drawPath(
      Path()
        ..lineTo(.65, 0)
        ..cubicTo(.36, .2, .13, .57, 0, .92)
        ..close(),
      navy,
    );
    canvas.drawPath(
      Path()
        ..moveTo(0, .79)
        ..cubicTo(.12, .49, .33, .17, .58, 0)
        ..lineTo(.8, 0)
        ..cubicTo(.48, .2, .19, .59, 0, 1)
        ..close(),
      gold,
    );
    canvas.drawPath(
      Path()
        ..moveTo(.8, 0)
        ..lineTo(1, 0)
        ..cubicTo(.73, .13, .49, .37, .29, .61)
        ..cubicTo(.42, .4, .63, .14, .8, 0)
        ..close(),
      navy,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(SsuRibbonPainter oldDelegate) =>
      bottomRight != oldDelegate.bottomRight || base != oldDelegate.base;
}
