import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/components/app_badge.dart';
import 'package:easy_rates_app/components/app_bill_row.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins AppBillRow's signed-money rendering: the +/− glyph and SA space-grouped
// R formatting (formatSignedAmount), the direction → token colour mapping
// (amountColor), and the composed row — title/subtitle/amount + trailing badge.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<void> withThemedContext(
    WidgetTester tester,
    void Function(BuildContext, ColorScheme, EasyRatesTokens) body,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEasyRatesTheme(),
        home: Builder(
          builder: (context) {
            body(
              context,
              Theme.of(context).colorScheme,
              Theme.of(context).extension<EasyRatesTokens>()!,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  group('formatSignedAmount — sign + SA R formatting', () {
    test('positive gets a + and green-direction sign; negative gets a − (U+2212)',
        () {
      expect(AppBillRow.formatSignedAmount(1250), '+R 1 250.00');
      expect(AppBillRow.formatSignedAmount(-842.5), '−R 842.50');
      expect(AppBillRow.formatSignedAmount(0), 'R 0.00');
    });

    test('thousands are space-grouped, two decimals always shown', () {
      expect(AppBillRow.formatSignedAmount(-1250000), '−R 1 250 000.00');
      expect(AppBillRow.formatSignedAmount(180), '+R 180.00');
      expect(AppBillRow.formatSignedAmount(-1430.75), '−R 1 430.75');
    });

    test('the minus is a true minus, not an ASCII hyphen', () {
      expect(AppBillRow.formatSignedAmount(-5).contains('−'), isTrue);
      expect(AppBillRow.formatSignedAmount(-5).contains('-'), isFalse);
    });
  });

  group('amountColor — money direction maps to semantic tokens', () {
    testWidgets('positive → positive, negative → negative, zero → onSurface',
        (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        expect(AppBillRow.amountColor(context, 10), t.positive);
        expect(AppBillRow.amountColor(context, -10), t.negative);
        expect(AppBillRow.amountColor(context, 0), scheme.onSurface);
      });
    });
  });

  group('AppBillRow widget', () {
    Widget host(Widget child) =>
        MaterialApp(theme: buildEasyRatesTheme(), home: Scaffold(body: child));

    testWidgets('renders icon, title, subtitle, signed amount, trailing badge',
        (tester) async {
      await tester.pumpWidget(host(
        const AppBillRow(
          icon: LucideIcons.droplet,
          title: 'Water & sanitation',
          subtitle: 'January 2026 statement',
          amount: -842.50,
          status: AppBadgeVariant.newBill,
        ),
      ));

      expect(find.text('Water & sanitation'), findsOneWidget);
      expect(find.text('January 2026 statement'), findsOneWidget);
      expect(find.text('−R 842.50'), findsOneWidget);
      // The trailing slot is the 02-status-badges widget.
      expect(find.byType(AppBadge), findsOneWidget);
      expect(find.text('New bill'), findsOneWidget);
    });

    testWidgets('the amount Text is coloured by money direction', (tester) async {
      late EasyRatesTokens tokens;
      await tester.pumpWidget(host(
        Builder(builder: (context) {
          tokens = Theme.of(context).extension<EasyRatesTokens>()!;
          return const AppBillRow(
            icon: LucideIcons.banknote,
            title: 'Payment received',
            subtitle: 'EFT',
            amount: 2000,
            status: AppBadgeVariant.paid,
          );
        }),
      ));

      final amount = tester.widget<Text>(find.text('+R 2 000.00'));
      expect(amount.style?.color, tokens.positive);
    });

    testWidgets('onTap fires when the row is tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(
        AppBillRow(
          icon: LucideIcons.zap,
          title: 'Electricity',
          subtitle: 'Account 1002004821',
          amount: -1250,
          status: AppBadgeVariant.pastDue,
          onTap: () => taps++,
        ),
      ));

      await tester.tap(find.byType(AppBillRow));
      expect(taps, 1);
    });
  });
}
