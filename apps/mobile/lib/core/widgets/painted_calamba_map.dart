import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

class PaintedCalambaMap extends StatefulWidget {
  const PaintedCalambaMap({
    this.animateDriver = false,
    this.height = 300,
    super.key,
  });

  final bool animateDriver;
  final double height;

  @override
  State<PaintedCalambaMap> createState() => _PaintedCalambaMapState();
}

class _PaintedCalambaMapState extends State<PaintedCalambaMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _driverProgress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );
    _driverProgress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    if (widget.animateDriver) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant PaintedCalambaMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.animateDriver && widget.animateDriver) {
      _controller.forward(from: 0);
    } else if (oldWidget.animateDriver && !widget.animateDriver) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.lg)),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _driverProgress,
          builder: (context, _) => CustomPaint(
            painter: _CalambaMapPainter(
              driverProgress: widget.animateDriver
                  ? _driverProgress.value
                  : 0.65,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalambaMapPainter extends CustomPainter {
  const _CalambaMapPainter({required this.driverProgress});

  final double driverProgress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9EFEA),
    );

    final zone = Path()
      ..moveTo(size.width * 0.08, size.height * 0.25)
      ..lineTo(size.width * 0.42, size.height * 0.12)
      ..lineTo(size.width * 0.79, size.height * 0.26)
      ..lineTo(size.width * 0.86, size.height * 0.66)
      ..lineTo(size.width * 0.52, size.height * 0.82)
      ..lineTo(size.width * 0.16, size.height * 0.68)
      ..close();
    canvas.drawPath(zone, Paint()..color = AppColors.primaryContainer);
    canvas.drawPath(
      zone,
      Paint()
        ..color = AppColors.primary.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final roadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadEdgePaint = Paint()
      ..color = AppColors.outline
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final route = Path()
      ..moveTo(size.width * 0.18, size.height * 0.65)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.48,
        size.width * 0.56,
        size.height * 0.7,
        size.width * 0.79,
        size.height * 0.36,
      );
    canvas.drawPath(route, roadEdgePaint);
    canvas.drawPath(route, roadPaint);
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.info
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final pickup = Offset(size.width * 0.18, size.height * 0.65);
    final destination = Offset(size.width * 0.79, size.height * 0.36);
    _drawPin(canvas, pickup, AppColors.primary);
    _drawPin(canvas, destination, AppColors.secondary);

    final eased = 0.12 + (driverProgress * 0.5);
    final driver = Offset(
      size.width * (0.18 + 0.61 * eased),
      size.height * (0.65 - 0.29 * eased + math.sin(eased * math.pi) * 0.08),
    );
    canvas.drawCircle(driver, 15, Paint()..color = AppColors.surface);
    canvas.drawCircle(driver, 13, Paint()..color = AppColors.primary);
    final icon = TextPainter(
      text: const TextSpan(text: '🛺', style: TextStyle(fontSize: 16)),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, driver - Offset(icon.width / 2, icon.height / 2));

    final label = TextPainter(
      text: const TextSpan(
        text: 'Calamba Poblacion TODA\n(illustrative boundary)',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.42);
    label.paint(canvas, Offset(size.width * 0.09, size.height * 0.08));

    final attribution = TextPainter(
      text: const TextSpan(
        text: 'Demo map - illustrative, not to scale',
        style: TextStyle(
          color: AppColors.textPrimary,
          backgroundColor: Color(0xE6FFFFFF),
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    attribution.paint(
      canvas,
      Offset(
        size.width - attribution.width - AppSpacing.xs,
        size.height - attribution.height - AppSpacing.xs,
      ),
    );
  }

  void _drawPin(Canvas canvas, Offset point, Color color) {
    canvas.drawCircle(point, 10, Paint()..color = AppColors.surface);
    canvas.drawCircle(point, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _CalambaMapPainter oldDelegate) =>
      oldDelegate.driverProgress != driverProgress;
}
