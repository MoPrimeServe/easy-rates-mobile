// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:easy_rates_app/main.dart';

void main() {
  testWidgets('EasyRatesApp renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const EasyRatesApp());
    expect(find.byType(EasyRatesApp), findsOneWidget);

    // SplashScreen schedules a 2s timer that routes to /onboarding. Advance past
    // it and settle the navigation so no timer is left pending at teardown.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(EasyRatesApp), findsOneWidget);
  });
}
