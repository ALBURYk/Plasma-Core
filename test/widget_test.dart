import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:plasma_core/src/plasma_core_app.dart';

void main() {
  testWidgets('renders Plasma Core researcher workspace without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PlasmaCoreApp());

    expect(find.text('Plasma Core'), findsOneWidget);
    expect(find.text('Parameters'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
