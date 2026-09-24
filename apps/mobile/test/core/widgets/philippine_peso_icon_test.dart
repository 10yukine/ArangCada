import 'package:arangcada/core/widgets/philippine_peso_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PhilippinePesoIcon renders cleanly with default properties', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: PhilippinePesoIcon()),
      ),
    );

    expect(find.byType(PhilippinePesoIcon), findsOneWidget);
    final size = tester.getSize(find.byType(PhilippinePesoIcon));
    expect(size.width, 20);
    expect(size.height, 20);
  });

  testWidgets('PhilippinePesoIcon respects custom size and color', (
    tester,
  ) async {
    const customSize = 32.0;
    const customColor = Colors.orange;

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: PhilippinePesoIcon(
            size: customSize,
            color: customColor,
          ),
        ),
      ),
    );

    final widget = tester.widget<PhilippinePesoIcon>(
      find.byType(PhilippinePesoIcon),
    );
    expect(widget.size, customSize);
    expect(widget.color, customColor);

    final renderSize = tester.getSize(find.byType(PhilippinePesoIcon));
    expect(renderSize.width, customSize);
    expect(renderSize.height, customSize);
  });
}
