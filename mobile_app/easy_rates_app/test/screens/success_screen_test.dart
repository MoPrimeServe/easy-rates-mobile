import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/screens/success/success_screen.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins the Success screen's key structural invariants:
//   - ALWAYS renders on the dark ink-900 surface regardless of host brightness
//   - lime glow check circle, "Payment sent", lime R amount, receipt line, "Done"
//   - amount in R (no £) — DoD 7 currency check
//   - "Done" navigates to /home

Widget successApp({double amount = 1250.00}) => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/success',
        routes: [
          GoRoute(
            path: '/success',
            builder: (_, state) =>
                SuccessScreen(amount: (state.extra as double?) ?? amount),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('SuccessScreen — structure', () {
    testWidgets('renders "Payment sent" headline', (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      expect(find.text('Payment sent'), findsOneWidget);
    });

    testWidgets('renders the paid amount in R', (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      expect(find.textContaining('R '), findsWidgets);
      // DoD 7 — no £ anywhere.
      expect(find.textContaining('£'), findsNothing);
    });

    testWidgets('renders receipt reference line', (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      expect(find.textContaining('Ref '), findsOneWidget);
    });

    testWidgets('renders "Done" button', (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('renders correct amount when passed as parameter', (tester) async {
      await tester.pumpWidget(successApp(amount: 842.50));
      await tester.pump();

      expect(find.textContaining('842'), findsWidgets);
    });
  });

  group('SuccessScreen — brightness', () {
    testWidgets('scaffold background is always the dark ink-900 token',
        (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EasyRatesTokens.dark.ink900);
    });

    testWidgets('inner Theme is always the dark token set', (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      final themeWidget = tester.widget<Theme>(
        find.descendant(
          of: find.byType(SuccessScreen),
          matching: find.byType(Theme),
        ),
      );
      expect(themeWidget.data.brightness, Brightness.dark);
    });
  });

  group('SuccessScreen — navigation', () {
    testWidgets('"Done" button navigates to /home', (tester) async {
      await tester.pumpWidget(successApp());
      await tester.pump();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });
  });
}
