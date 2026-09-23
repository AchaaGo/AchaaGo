import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A decorative stand-in for the live map. AGENTS.md only calls for a
/// real map once `MAPS_PROVIDER=google` is configured with an API key
/// (services/api/app/providers.py `DemoMaps` is the default); until then
/// this keeps the same visual language as apps/web's illustrated
/// `MapBackdrop` without pulling in a Maps SDK or API key.
class RouteIllustration extends StatelessWidget {
  const RouteIllustration({super.key, this.showRoute = false, this.pulse = false, this.showTruck = false});

  final bool showRoute;
  final bool pulse;
  final bool showTruck;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFECE7DC), // map-bg
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showRoute) CustomPaint(size: Size.infinite, painter: _RoutePainter()),
          if (pulse)
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.55), shape: BoxShape.circle),
            ),
          if (showTruck)
            const CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.ink,
              child: Icon(Icons.local_shipping, color: AppColors.accent, size: 20),
            ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * 0.28, size.height * 0.32);
    final end = Offset(size.width * 0.68, size.height * 0.7);

    final outline = Paint()
      ..color = Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = AppColors.ink
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, outline);
    canvas.drawLine(start, end, line);

    canvas.drawCircle(start, 7, Paint()..color = AppColors.ink);
    final dropoffPaint = Paint()..color = AppColors.accent;
    final dropoffBorder = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromCenter(center: end, width: 14, height: 14), dropoffPaint);
    canvas.drawRect(Rect.fromCenter(center: end, width: 14, height: 14), dropoffBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
