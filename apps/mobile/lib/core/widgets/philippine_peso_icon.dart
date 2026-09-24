import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A rounded, vector Philippine Peso icon matching the ArangCada design language.
class PhilippinePesoIcon extends StatelessWidget {
  const PhilippinePesoIcon({
    super.key,
    this.size = 20,
    this.color = AppColors.primary,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PhilippinePesoPainter(color: color),
      ),
    );
  }
}

class _PhilippinePesoPainter extends CustomPainter {
  const _PhilippinePesoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.082;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final stemX = size.width * 0.2944;
    final stemTop = size.height * 0.1670;
    final stemBot = size.height * 0.8311;

    final straightRight = size.width * 0.4409;
    final loopCx = size.width * 0.4409;
    final loopCy = size.height * 0.3668;
    final loopRx = size.width * 0.2550;
    final loopRy = size.height * 0.1998;

    final barLeft = size.width * 0.2297;
    final barRight = size.width * 0.7702;
    final bar1Y = size.height * 0.2983;
    final bar2Y = size.height * 0.4334;

    // Draw the P shape: vertical stem and rounded loop.
    final path = Path()
      ..moveTo(stemX, stemBot)
      ..lineTo(stemX, stemTop)
      ..lineTo(straightRight, stemTop)
      ..arcTo(
        Rect.fromCenter(
          center: Offset(loopCx, loopCy),
          width: loopRx * 2,
          height: loopRy * 2,
        ),
        -math.pi / 2,
        math.pi,
        false,
      )
      ..lineTo(stemX, loopCy + loopRy);

    canvas.drawPath(path, paint);

    // Draw the two horizontal crossbars with rounded ends.
    canvas.drawLine(Offset(barLeft, bar1Y), Offset(barRight, bar1Y), paint);
    canvas.drawLine(Offset(barLeft, bar2Y), Offset(barRight, bar2Y), paint);
  }

  @override
  bool shouldRepaint(covariant _PhilippinePesoPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
