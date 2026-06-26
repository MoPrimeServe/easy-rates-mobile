import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/screens/home/home_screen.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins the Home screen's key structural invariants:
//   - always renders on the light surface (t.appBg from the light token set)
//   - greeting row, balance card, 5 quick actions, tip banner, bill list, tab bar
//   - all money rendered in R (no £) — DoD 7 currency check
//   - Pay quick action navigates to /pay; Usage tile and tab 2 navigate to /usage

Widget homeApp() => MaterialApp.router(
      theme: buildEasyRatesTheme(),
      routerConfig: GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/pay',   builder: (_, _) => const Scaffold(body: Text('pay'))),
          GoRoute(path: '/usage', builder: (_, _) => const Scaffold(body: Text('usage'))),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('HomeScreen — structure', () {
    testWidgets('renders greeting with bell icon', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      expect(find.textContaining('Hi '), findsOneWidget);
      // Bell appears in the greeting row AND in the Alerts tab of the tab bar.
      expect(find.byIcon(LucideIcons.bell), findsWidgets);
    });

    testWidgets('renders balance card with R amount', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      // Balance card renders a large R-formatted figure.
      expect(find.textContaining('R '), findsWidgets);
      // DoD 7 — no £ anywhere on the screen.
      expect(find.textContaining('£'), findsNothing);
    });

    testWidgets('renders all 5 quick-action labels', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      for (final label in ['Pay', 'Bills', 'Usage', 'Auto-pay', 'More']) {
        expect(find.text(label), findsOneWidget, reason: '$label tile missing');
      }
    });

    testWidgets('renders bill list rows', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      expect(find.text('Your bills'), findsOneWidget);
      // At least one bill row title is present.
      expect(find.textContaining('Water'), findsWidgets);
    });

    testWidgets('renders the floating tab bar', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      // Home is the first tab — its label is visible in the active lime pill.
      expect(find.text('Home'), findsOneWidget);
    });
  });

  group('HomeScreen — brightness', () {
    testWidgets('scaffold background is the light appBg token', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EasyRatesTokens.light.appBg);
    });
  });

  group('HomeScreen — navigation', () {
    testWidgets('"Pay" quick action navigates to /pay', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();

      expect(find.text('pay'), findsOneWidget);
    });

    testWidgets('"Usage" quick action navigates to /usage', (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      await tester.tap(find.text('Usage'));
      await tester.pumpAndSettle();

      expect(find.text('usage'), findsOneWidget);
    });

    testWidgets('tab bar Water tab (index 2) navigates to /usage',
        (tester) async {
      await tester.pumpWidget(homeApp());
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Water'));
      await tester.pumpAndSettle();

      expect(find.text('usage'), findsOneWidget);
    });
  });
}
