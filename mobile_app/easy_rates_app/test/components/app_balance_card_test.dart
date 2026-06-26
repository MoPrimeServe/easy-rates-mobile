import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/components/app_balance_card.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins AppBalanceCard's R/SA money formatting, account masking, and due-date
// rendering, and asserts the card paints on the lime (primary) surface with
// ink (onPrimary) content in both brightnesses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> pumpCard(
    WidgetTester tester,
    ThemeData theme, {
    double totalOwed = 12480.75,
    String accountNumber = '1002004821',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AppBalanceCard(
            totalOwed: totalOwed,
            accountHolder: 'T. Mokoena',
            accountNumber: accountNumber,
            dueDate: DateTime(2026, 7, 15),
          ),
        ),
      ),
    );
  }

  group('AppBalanceCard — content rendering', () {
    testWidgets('renders eyebrow, holder, masked account and due date',
        (tester) async {
      await pumpCard(tester, buildEasyRatesTheme());
      expect(find.text('TOTAL OWED'), findsOneWidget);
      expect(find.text('ACCOUNT HOLDER'), findsOneWidget);
      expect(find.text('DUE'), findsOneWidget);
      expect(find.text('T. Mokoena'), findsOneWidget);
      // Last four digits only, masked.
      expect(find.text('•••• 4821'), findsOneWidget);
      expect(find.text('15 Jul 2026'), findsOneWidget);
    });

    testWidgets('formats the figure R/SA style — grouped thousands',
        (tester) async {
      await pumpCard(tester, buildEasyRatesTheme());
      // 12480.75 → "R 12 480.75" with non-breaking spaces.
      expect(find.text('R 12 480.75'), findsOneWidget);
    });

    testWidgets('groups millions and keeps small amounts ungrouped',
        (tester) async {
      await pumpCard(tester, buildEasyRatesTheme(), totalOwed: 1234567.89);
      expect(find.text('R 1 234 567.89'), findsOneWidget);

      await pumpCard(tester, buildEasyRatesTheme(), totalOwed: 9.50);
      expect(find.text('R 9.50'), findsOneWidget);
    });

    testWidgets('short account numbers are shown whole, not over-masked',
        (tester) async {
      await pumpCard(tester, buildEasyRatesTheme(), accountNumber: '88');
      expect(find.text('•••• 88'), findsOneWidget);
    });
  });

  group('AppBalanceCard — token-driven surface', () {
    void expectLimeCardWithInkContent(WidgetTester tester, ThemeData theme) {
      final scheme = theme.colorScheme;

      // Fill is the lime primary, radius is the rXl token.
      final t = theme.extension<EasyRatesTokens>()!;
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppBalanceCard),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, scheme.primary);
      expect(decoration.borderRadius, t.radiusXl);

      // Every text fragment is painted in onPrimary (ink that reads on lime).
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(AppBalanceCard),
          matching: find.byType(Text),
        ),
      );
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(text.style?.color, scheme.onPrimary,
            reason: 'all card content uses onPrimary');
      }
    }

    testWidgets('light: lime fill, ink content', (tester) async {
      final theme = buildEasyRatesTheme();
      await pumpCard(tester, theme);
      expectLimeCardWithInkContent(tester, theme);
    });

    testWidgets('dark: lime fill, ink content', (tester) async {
      final theme = buildEasyRatesDarkTheme();
      await pumpCard(tester, theme);
      expectLimeCardWithInkContent(tester, theme);
    });
  });
}
