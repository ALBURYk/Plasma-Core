import 'package:flutter_test/flutter_test.dart';
import 'package:plasma_core/src/plasma_core_app.dart';

void main() {
  testWidgets('renders Plasma Core researcher workspace', (tester) async {
    await tester.pumpWidget(const PlasmaCoreApp());

    expect(find.text('Plasma Core'), findsOneWidget);
    expect(find.text('Параметры'), findsOneWidget);
    expect(find.text('Запустить расчет'), findsOneWidget);
    expect(find.text('FASTA результат'), findsOneWidget);
  });
}
