import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/components/app_form_field.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';
import 'package:easy_rates_app/theme/app_colors.dart';

// Pins AppFieldRing.resolve() — the ring/glyph/fill contract — to tokens across
// the four states, and smoke-checks the widget's leading-glyph slot.
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

  group('AppFieldRing.resolve — ring states map to tokens', () {
    testWidgets('resting → hairline ring, 1px, muted accent, surface fill',
        (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        final r = AppFieldRing.resolve(context,
            focused: false, hasError: false, disabled: false);
        expect(r.border, t.hairline);
        expect(r.borderWidth, t.borderWidth);
        expect(r.accent, t.fgMuted);
        expect(r.fill, scheme.surface);
      });
    });

    testWidgets('focused → sky-500 ring at 2px', (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        final r = AppFieldRing.resolve(context,
            focused: true, hasError: false, disabled: false);
        expect(r.border, scheme.secondary); // sky-500
        expect(r.accent, scheme.secondary);
        expect(r.borderWidth, t.borderWidthFocus);
      });
    });

    testWidgets('error → negative ring; focused-error stays red at 2px',
        (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        final rest = AppFieldRing.resolve(context,
            focused: false, hasError: true, disabled: false);
        expect(rest.border, scheme.error);
        expect(rest.accent, scheme.error);
        expect(rest.borderWidth, t.borderWidth);

        final focused = AppFieldRing.resolve(context,
            focused: true, hasError: true, disabled: false);
        expect(focused.border, scheme.error); // error wins over focus colour
        expect(focused.borderWidth, t.borderWidthFocus);
      });
    });

    testWidgets('disabled → muted ring on sunken fill, faded content',
        (tester) async {
      await withThemedContext(tester, (context, scheme, t) {
        final r = AppFieldRing.resolve(context,
            focused: false, hasError: false, disabled: true);
        expect(r.border, scheme.outlineVariant);
        expect(r.fill, t.sunken);
        expect(r.borderWidth, t.borderWidth);
        expect(r.textColor,
            scheme.onSurface.withAlpha(AppColors.disabledContentAlpha));
      });
    });
  });

  group('AppFormField widget — leading-glyph slot', () {
    testWidgets('renders a Lucide glyph, label and hint', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEasyRatesTheme(),
          home: const Scaffold(
            body: AppFormField(
              label: 'Account number',
              hint: 'e.g. 1234567890',
              icon: LucideIcons.hash,
            ),
          ),
        ),
      );
      expect(find.text('Account number'), findsOneWidget);
      expect(find.text('e.g. 1234567890'), findsOneWidget);
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('renders a textual prefix marker and error helper',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildEasyRatesTheme(),
          home: const Scaffold(
            body: AppFormField(
              label: 'Amount',
              prefixText: 'R',
              errorText: 'Required',
            ),
          ),
        ),
      );
      expect(find.text('R'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
    });
  });
}
