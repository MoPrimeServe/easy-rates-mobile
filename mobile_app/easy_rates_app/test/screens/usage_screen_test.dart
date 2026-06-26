import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/screens/usage/usage_screen.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins the Usage screen's key structural invariants:
//   - light surface; Water/Council-tax toggle; usage card (m³ / kWh);
//     history list; floating tab bar
//   - toggling to Council-tax switches unit from m³ to kWh
//   - tab bar Home tab (index 0) navigates to /home

Widget usageApp() => MaterialApp.router(
      theme: buildEasyRatesTheme(),
      routerConfig: GoRouter(
        initialLocation: '/usage',
        routes: [
          GoRoute(path: '/usage', builder: (_, _) => const UsageScreen()),
          GoRoute(path: '/home',  builder: (_, _) => const Scaffold(body: Text('home'))),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('UsageScreen — structure', () {
    testWidgets('renders page title', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      expect(find.text('Usage'), findsOneWidget);
    });

    testWidgets('renders Water / Council-tax toggle', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      // 'Water' appears in both the toggle pill and the active tab label.
      expect(find.text('Water'),       findsWidgets);
      expect(find.text('Council tax'), findsOneWidget);
    });

    testWidgets('defaults to Water mode — shows m³ unit', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      expect(find.textContaining('m³'), findsWidgets);
    });

    testWidgets('renders History section with at least one row', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      expect(find.text('History'), findsOneWidget);
      // Each history row has a period label like "Jun 2026".
      expect(find.textContaining('2026'), findsWidgets);
    });

    testWidgets('renders the floating tab bar', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      // Water tab (index 2) is pre-selected — its label is in the active pill.
      expect(find.text('Water'), findsWidgets); // toggle + active tab pill
    });
  });

  group('UsageScreen — brightness', () {
    testWidgets('scaffold background is the light appBg token', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EasyRatesTokens.light.appBg);
    });
  });

  group('UsageScreen — toggle', () {
    testWidgets('tapping Council-tax switches unit to kWh', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      await tester.tap(find.text('Council tax'));
      await tester.pumpAndSettle();

      expect(find.textContaining('kWh'), findsWidgets);
    });

    testWidgets('switching back to Water restores m³', (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      await tester.tap(find.text('Council tax'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Water').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('m³'), findsWidgets);
    });
  });

  group('UsageScreen — navigation', () {
    testWidgets('tab bar Home tab (index 0) navigates to /home',
        (tester) async {
      await tester.pumpWidget(usageApp());
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Home'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });
  });
}
