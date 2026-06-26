import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_rates_app/components/app_button.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/app_colors.dart';

// Pins AppButtonVariant.spec() to the design tokens: the visual contract every
// AppButton paints. Pure mapping assertions — pump a Builder only to get a
// themed BuildContext, then call spec() directly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  // Runs `body(context, colorScheme)` inside the real app theme.
  Future<void> withThemedContext(
    WidgetTester tester,
    void Function(BuildContext, ColorScheme) body,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildEasyRatesTheme(),
        home: Builder(
          builder: (context) {
            body(context, Theme.of(context).colorScheme);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  group('AppButtonVariant.spec — resting fills map to brand tokens', () {
    testWidgets('primary is the lime pill (primary / onPrimary)', (tester) async {
      await withThemedContext(tester, (context, scheme) {
        final s = AppButtonVariant.primary.spec(context);
        expect(s.fill, scheme.primary);       // lime-500
        expect(s.foreground, scheme.onPrimary); // ink
        expect(s.side, isNull);
      });
    });

    testWidgets('secondary is the ink pill (inverseSurface / onInverseSurface)',
        (tester) async {
      await withThemedContext(tester, (context, scheme) {
        final s = AppButtonVariant.secondary.spec(context);
        expect(s.fill, scheme.inverseSurface);
        expect(s.foreground, scheme.onInverseSurface);
        expect(s.side, isNull);
      });
    });

    testWidgets('outline has no fill and an outline ring', (tester) async {
      await withThemedContext(tester, (context, scheme) {
        final s = AppButtonVariant.outline.spec(context);
        expect(s.fill, isNull);
        expect(s.foreground, scheme.onSurface);
        expect(s.side!.color, scheme.outline);
      });
    });
  });

  group('AppButtonVariant.spec — state layers come from tokens', () {
    testWidgets('pressed primary uses the limePress token', (tester) async {
      await withThemedContext(tester, (context, scheme) {
        final resting = AppButtonVariant.primary.spec(context);
        final pressed = AppButtonVariant.primary.spec(context, pressed: true);
        expect(pressed.fill, isNot(resting.fill));
        expect(pressed.fill, const Color(0xFFB6DE2E)); // limePress
      });
    });

    testWidgets('pressed outline gains a faint onSurface fill', (tester) async {
      await withThemedContext(tester, (context, scheme) {
        final pressed = AppButtonVariant.outline.spec(context, pressed: true);
        expect(pressed.fill,
            scheme.onSurface.withAlpha(AppColors.pressOverlayAlpha));
      });
    });

    testWidgets('disabled fades content + container via disabled alphas',
        (tester) async {
      await withThemedContext(tester, (context, scheme) {
        final primary = AppButtonVariant.primary.spec(context, disabled: true);
        expect(primary.foreground,
            scheme.onSurface.withAlpha(AppColors.disabledContentAlpha));
        expect(primary.fill,
            scheme.onSurface.withAlpha(AppColors.disabledContainerAlpha));

        // Outline stays fill-less but its ring fades too.
        final outline = AppButtonVariant.outline.spec(context, disabled: true);
        expect(outline.fill, isNull);
        expect(outline.side!.color,
            scheme.onSurface.withAlpha(AppColors.disabledContainerAlpha));
      });
    });
  });

  group('AppButton widget', () {
    testWidgets('renders label + optional leading icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEasyRatesTheme(),
          home: Scaffold(
            body: AppButton(
              label: 'Pay account',
              icon: Icons.arrow_forward, // any IconData; Lucide is one
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(find.text('Pay account'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });
  });
}
