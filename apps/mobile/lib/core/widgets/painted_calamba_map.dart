import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';

class PaintedCalambaMap extends StatefulWidget {
  const PaintedCalambaMap({
    this.animateDriver = false,
    this.driverAnimationDuration = const Duration(seconds: 7),
    this.height = 300,
    this.showNearbyDrivers = false,
    this.showRoute = true,
    this.showDestination = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadii.lg)),
    super.key,
  });

  final bool animateDriver;
  final Duration driverAnimationDuration;
  final double height;
  final bool showNearbyDrivers;
  final bool showRoute;
  final bool showDestination;
  final BorderRadius borderRadius;

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
      duration: widget.driverAnimationDuration,
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
    if (oldWidget.driverAnimationDuration != widget.driverAnimationDuration) {
      _controller.duration = widget.driverAnimationDuration;
    }
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
      borderRadius: widget.borderRadius,
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
              showNearbyDrivers: widget.showNearbyDrivers,
              showRoute: widget.showRoute,
              showDestination: widget.showDestination,
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
    required this.showNearbyDrivers,
    required this.showRoute,
    required this.showDestination,
  });

  final double driverProgress;
  final double pulseProgress;
  final bool showNearbyDrivers;
  final bool showRoute;
  final bool showDestination;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE4EDF7),
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
        ..color = const Color(0x5B7FC4EE)
        ..style = PaintingStyle.fill,
    );
    _drawDashedPath(
      canvas,
      zone,
      Paint()
        ..color = const Color(0xFF1262D0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final roadPaint = Paint()
      ..color = const Color(0xFFFBFDFF)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final roadEdgePaint = Paint()
      ..color = const Color(0xFFDBE5F1)
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
    if (showRoute) {
      canvas.drawPath(
        route,
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    final pickup = Offset(size.width * 0.18, size.height * 0.65);
    final destination = Offset(size.width * 0.79, size.height * 0.36);
    _drawCurrentLocation(canvas, pickup);
    if (showDestination) _drawPin(canvas, destination);

    final eased = 0.12 + (driverProgress * 0.5);
    final driver = Offset(
      size.width * (0.18 + 0.61 * eased),
      size.height * (0.65 - 0.29 * eased + math.sin(eased * math.pi) * 0.08),
    );
    canvas.drawCircle(driver, 15, Paint()..color = AppColors.surface);
    canvas.drawCircle(driver, 13, Paint()..color = AppColors.primary);
    final icon = TextPainter(
      text: TextSpan(
        // MaterialIcons is bundled by uses-material-design, so this glyph
        // renders identically on every device. Emoji do not: OEM fonts
        // substituted a hut for the tricycle here.
        text: String.fromCharCode(Icons.local_taxi_rounded.codePoint),
        style: TextStyle(
          fontSize: 15,
          fontFamily: Icons.local_taxi_rounded.fontFamily,
          package: Icons.local_taxi_rounded.fontPackage,
          color: AppColors.surface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, driver - Offset(icon.width / 2, icon.height / 2));
    _drawVehicleTag(canvas, driver, 'TRI 024');

    if (showNearbyDrivers) {
      _drawDriverMarker(
        canvas,
        Offset(size.width * 0.23, size.height * 0.29),
        'TRI 013',
      );
      _drawDriverMarker(
        canvas,
        Offset(size.width * 0.69, size.height * 0.22),
        'TRI 017',
      );
      _drawDriverMarker(
        canvas,
        Offset(size.width * 0.75, size.height * 0.69),
        'TRI 041',
      );
      _drawDriverMarker(
        canvas,
        Offset(size.width * 0.39, size.height * 0.77),
        'TRI 052',
      );
    }

    _drawPillLabel(
      canvas,
      Offset(size.width * 0.09, size.height * 0.205),
      'Calamba Poblacion TODA (illustrative boundary)',
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
        ..color = AppColors.sky.withValues(alpha: 1 - pulseProgress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(point, 11, Paint()..color = AppColors.surface);
    canvas.drawCircle(point, 9, Paint()..color = AppColors.primary);
  }

  void _drawDriverMarker(Canvas canvas, Offset marker, String tag) {
    canvas.drawCircle(marker, 15, Paint()..color = AppColors.surface);
    canvas.drawCircle(marker, 13, Paint()..color = AppColors.primary);
    final icon = TextPainter(
      text: TextSpan(
        // MaterialIcons is bundled by uses-material-design, so this glyph
        // renders identically on every device. Emoji do not: OEM fonts
        // substituted a hut for the tricycle here.
        text: String.fromCharCode(Icons.local_taxi_rounded.codePoint),
        style: TextStyle(
          fontSize: 15,
          fontFamily: Icons.local_taxi_rounded.fontFamily,
          package: Icons.local_taxi_rounded.fontPackage,
          color: AppColors.surface,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(canvas, marker - Offset(icon.width / 2, icon.height / 2));
    _drawVehicleTag(canvas, marker, tag);
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
      oldDelegate.pulseProgress != pulseProgress ||
      oldDelegate.showNearbyDrivers != showNearbyDrivers ||
      oldDelegate.showRoute != showRoute ||
      oldDelegate.showDestination != showDestination;
}
