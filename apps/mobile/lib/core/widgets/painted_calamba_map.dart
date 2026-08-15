import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

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
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _pulseController;
  late final Animation<double> _driverProgress;
  late final Animation<double> _pulseProgress;

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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulseProgress = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
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
    _pulseController.dispose();
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
          animation: Listenable.merge([_driverProgress, _pulseProgress]),
          builder: (context, _) => CustomPaint(
            painter: _CalambaMapPainter(
              driverProgress: widget.animateDriver
                  ? _driverProgress.value
                  : 0.65,
              pulseProgress: _pulseProgress.value,
            ),
          ),
        ),
      ),
    );
  }
}

class _CalambaMapPainter extends CustomPainter {
  const _CalambaMapPainter({
    required this.driverProgress,
    required this.pulseProgress,
  });

  final double driverProgress;
  final double pulseProgress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEDE8DC),
    );

    final zone = Path()
      ..moveTo(size.width * 0.08, size.height * 0.25)
      ..lineTo(size.width * 0.42, size.height * 0.12)
      ..lineTo(size.width * 0.79, size.height * 0.26)
      ..lineTo(size.width * 0.86, size.height * 0.66)
      ..lineTo(size.width * 0.52, size.height * 0.82)
      ..lineTo(size.width * 0.16, size.height * 0.68)
      ..close();
    canvas.drawPath(
      zone,
      Paint()
        ..color = const Color(0x6BE9A35E)
        ..style = PaintingStyle.fill,
    );
    _drawDashedPath(
      canvas,
      zone,
      Paint()
        ..color = const Color(0xFFC06E2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final roadPaint = Paint()
      ..color = const Color(0xFFFBFAF6)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadEdgePaint = Paint()
      ..color = const Color(0xFFE3DFD5)
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
        ..color = AppColors.primary
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    final pickup = Offset(size.width * 0.18, size.height * 0.65);
    final destination = Offset(size.width * 0.79, size.height * 0.36);
    _drawCurrentLocation(canvas, pickup);
    _drawPin(canvas, destination);

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
    _drawVehicleTag(canvas, driver, 'TRI 024');

    _drawPillLabel(
      canvas,
      Offset(size.width * 0.09, size.height * 0.08),
      'Calamba Poblacion TODA',
      background: AppColors.amberFill,
      foreground: AppColors.amberText,
      style: const TextStyle(fontSize: 12, color: AppColors.amberText),
      horizontalPadding: 10,
      verticalPadding: 2,
      radius: 10,
    );

    const attributionText = 'Demo map · illustrative, not to scale';
    final attribution = TextPainter(
      text: const TextSpan(
        text: attributionText,
        style: TextStyle(color: AppColors.ink, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final attributionOrigin = Offset(
      size.width - attribution.width - AppSpacing.xs,
      size.height - attribution.height - AppSpacing.xs,
    );
    final attributionRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        attributionOrigin.dx - 5,
        attributionOrigin.dy - 3,
        attribution.width + 10,
        attribution.height + 6,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      attributionRect,
      Paint()..color = AppColors.surface.withValues(alpha: 0.90),
    );
    attribution.paint(canvas, attributionOrigin);
  }

  void _drawPin(Canvas canvas, Offset point) {
    canvas.drawCircle(point, 10, Paint()..color = AppColors.surface);
    canvas.drawCircle(point, 7, Paint()..color = AppColors.primary);
  }

  void _drawCurrentLocation(Canvas canvas, Offset point) {
    final ringRadius = 9 * (0.4 + pulseProgress);
    canvas.drawCircle(
      point,
      ringRadius,
      Paint()
        ..color = AppColors.coral.withValues(alpha: 1 - pulseProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(point, 11, Paint()..color = AppColors.surface);
    canvas.drawCircle(point, 9, Paint()..color = AppColors.primary);
  }

  void _drawVehicleTag(Canvas canvas, Offset marker, String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AppTypography.bodyTag),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = Offset(marker.dx, marker.dy - 26);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + 14,
        height: painter.height + 4,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(rect, Paint()..color = AppColors.ink);
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  void _drawPillLabel(
    Canvas canvas,
    Offset origin,
    String text, {
    required Color background,
    required Color foreground,
    required TextStyle style,
    required double horizontalPadding,
    required double verticalPadding,
    required double radius,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(color: foreground),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        origin.dx,
        origin.dy,
        painter.width + horizontalPadding * 2,
        painter.height + verticalPadding * 2,
      ),
      Radius.circular(radius),
    );
    canvas.drawRRect(rect, Paint()..color = background);
    painter.paint(canvas, origin + Offset(horizontalPadding, verticalPadding));
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 8, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CalambaMapPainter oldDelegate) =>
      oldDelegate.driverProgress != driverProgress ||
      oldDelegate.pulseProgress != pulseProgress;
}
