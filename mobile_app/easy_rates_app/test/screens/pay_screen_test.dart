import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/screens/pay/pay_screen.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins the Pay screen's key structural invariants:
//   - light surface; AMOUNT DUE hero in R; Due badge; Emfuleni breakdown;
//     payment-method card; sticky "Pay R…" CTA; secured footer
//   - all money in R (no £) — DoD 7 currency check
//   - breakdown arithmetic: line items sum to hero total (enforced by const in source)
//   - "Pay R…" button navigates to /success

Widget payApp() => MaterialApp.router(
      theme: buildEasyRatesTheme(),
      routerConfig: GoRouter(
        initialLocation: '/pay',
        routes: [
          GoRoute(path: '/pay',     builder: (_, _) => const PayScreen()),
          GoRoute(path: '/success', builder: (_, _) => const Scaffold(body: Text('success'))),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('PayScreen — structure', () {
    testWidgets('renders AMOUNT DUE hero and Due badge', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      expect(find.text('AMOUNT DUE'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
    });

    testWidgets('renders back button (chevronLeft)', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      expect(find.byIcon(LucideIcons.chevronLeft), findsOneWidget);
    });

    testWidgets('renders all Emfuleni breakdown line items', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      expect(find.text('Water supply tariff'), findsOneWidget);
      expect(find.text('Wastewater levy'),    findsOneWidget);
      expect(find.text('Network standing charge'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('renders payment-method card with masked digits', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      expect(find.textContaining('Absa Bank'), findsOneWidget);
      expect(find.textContaining('4821'), findsOneWidget);
    });

    testWidgets('renders sticky Pay CTA and secured footer', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      expect(find.textContaining('Pay R'), findsOneWidget);
      expect(find.text('Payments secured by Emfuleni billing'), findsOneWidget);
      expect(find.byIcon(LucideIcons.lockKeyhole), findsOneWidget);
    });

    testWidgets('all money is in R — no £ on screen', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      // _fmt uses U+00A0 (NBSP) between symbol and digits — check via the CTA label.
      expect(find.textContaining('Pay R'), findsWidgets);
      expect(find.textContaining('£'), findsNothing);
    });
  });

  group('PayScreen — brightness', () {
    testWidgets('scaffold background is the light appBg token', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EasyRatesTokens.light.appBg);
    });
  });

  group('PayScreen — navigation', () {
    testWidgets('"Pay R…" button navigates to /success', (tester) async {
      await tester.pumpWidget(payApp());
      await tester.pump();

      // Scroll to make the sticky CTA visible, then tap.
      await tester.tap(find.textContaining('Pay R'));
      await tester.pumpAndSettle();

      expect(find.text('success'), findsOneWidget);
    });
  });
}
