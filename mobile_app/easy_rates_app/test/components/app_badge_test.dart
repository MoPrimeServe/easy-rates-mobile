import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/components/app_badge.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';
import 'package:easy_rates_app/theme/app_colors.dart';

// Pins AppBadgeVariant.spec() to its semantic colour + Lucide glyph, and the
// pill geometry to tokens. Pump a Builder only to obtain a themed context.
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

  group('AppBadgeVariant.spec — semantic colour + glyph mapping', () {
    testWidgets('each variant maps to the right token colour and Lucide glyph',
        (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        final cases = <AppBadgeVariant, (Color, IconData, String)>{
          AppBadgeVariant.paid:    (t.positive,   LucideIcons.check,       'Paid'),
          AppBadgeVariant.due:     (t.warning,    LucideIcons.clock,       'Due'),
          AppBadgeVariant.pastDue: (scheme.error, LucideIcons.circleAlert, 'Past due'),
          AppBadgeVariant.autoPay: (t.info,       LucideIcons.repeat,      'AutoPay'),
          AppBadgeVariant.newBill: (t.fgMuted,    LucideIcons.fileText,    'New bill'),
        };
        cases.forEach((variant, expected) {
          final s = variant.spec(context);
          expect(s.color, expected.$1, reason: '$variant colour');
          expect(s.icon, expected.$2, reason: '$variant glyph');
          expect(s.label, expected.$3, reason: '$variant label');
        });
      });
    });

    testWidgets('geometry + tint alphas come from tokens', (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        final s = AppBadgeVariant.paid.spec(context);
        expect(s.radius, t.radiusPill);
        expect(s.padding, t.badgePadding);
        expect(s.iconSize, t.iconSm);
        expect(s.gap, t.s1);
        expect(s.fillAlpha, AppColors.tintFillAlpha);
        expect(s.borderAlpha, AppColors.tintBorderAlpha);
        expect(s.textStyle.fontSize, 13); // labelMedium — the chips slot
      });
    });
  });

  group('AppBadge widget', () {
    testWidgets('renders glyph + label for every variant', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEasyRatesTheme(),
          home: const Scaffold(
            body: Wrap(
              children: [
                AppBadge(AppBadgeVariant.paid),
                AppBadge(AppBadgeVariant.due),
                AppBadge(AppBadgeVariant.pastDue),
                AppBadge(AppBadgeVariant.autoPay),
                AppBadge(AppBadgeVariant.newBill),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(AppBadge), findsNWidgets(5));
      expect(find.byType(Icon), findsNWidgets(5));
      expect(find.text('Past due'), findsOneWidget);
      expect(find.text('AutoPay'), findsOneWidget);
    });
  });
}
