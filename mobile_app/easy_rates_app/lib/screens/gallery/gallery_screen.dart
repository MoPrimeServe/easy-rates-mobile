import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

// Component gallery — a living catalogue of the Mohapi V1 design system.
// A sun/moon toggle in the AppBar switches the entire subtree between the
// light and dark token sets so every component can be inspected in both modes.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  Brightness _brightness = Brightness.light;

  void _toggle() => setState(() {
        _brightness =
            _brightness == Brightness.light ? Brightness.dark : Brightness.light;
      });

  @override
  Widget build(BuildContext context) {
    final themeData = _brightness == Brightness.light
        ? buildEasyRatesTheme()
        : buildEasyRatesDarkTheme();

    // Theme wrapper overrides the entire gallery subtree — AppBar included.
    return Theme(
      data: themeData,
      child: Builder(builder: (ctx) {
        final theme = Theme.of(ctx);
        final t = theme.extension<EasyRatesTokens>()!;
        final tt = theme.textTheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Component gallery'),
            actions: [
              IconButton(
                onPressed: _toggle,
                tooltip: _brightness == Brightness.light
                    ? 'Switch to dark'
                    : 'Switch to light',
                icon: Icon(
                  _brightness == Brightness.light
                      ? LucideIcons.moon
                      : LucideIcons.sun,
                ),
              ),
            ],
          ),
          body: ListView(
            padding: t.screenPadding,
            children: [
              SizedBox(height: t.s3),

              // ── AppBalanceCard ──────────────────────────────────────────────
              const _SectionHeader('AppBalanceCard'),
              SizedBox(height: t.s1),
              Text(
                'Lime-surface hero: total owed (Space Grotesk tabular), '
                'masked account, holder name & due date.',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s2),
              const _SectionSpec([
                'fill: primary (#E1FB8E)  ·  fg: onPrimary (#0A0B0A)',
                'radius: rLg (22)  ·  type: displayLarge (58) / bodyMedium (15)',
                'account mask: •••• NNNN — last 4 digits shown',
              ]),
              SizedBox(height: t.s3),
              AppBalanceCard(
                totalOwed: 12480.75,
                accountHolder: 'T. Mokoena',
                accountNumber: '1002004821',
                dueDate: DateTime(2026, 7, 15),
              ),

              const Divider(height: AppSpacing.xl),

              // ── AppButton ───────────────────────────────────────────────────
              const _SectionHeader('AppButton'),
              SizedBox(height: t.s1),
              Text(
                'Three variants driven by AppButtonVariant.spec(). '
                'Each block: resting → with leading icon → disabled.',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s2),
              const _SectionSpec([
                'primary   fill: primary  ·  fg: onPrimary  ·  pressed: limePress',
                'secondary  fill: inverseSurface  ·  fg: onInverseSurface',
                'outline   border: outline 1px  ·  fg: onSurface',
                'disabled  fg: onSurface@38%  ·  fill: onSurface@12%',
                'shape: pill  ·  pad: s4×s3 (16×12)  ·  min-h: 44',
              ]),
              SizedBox(height: t.s3),
              const _VariantBlock(
                title: 'Primary — lime pill',
                variant: AppButtonVariant.primary,
              ),
              const _VariantBlock(
                title: 'Secondary — ink pill',
                variant: AppButtonVariant.secondary,
              ),
              const _VariantBlock(
                title: 'Outline — ring',
                variant: AppButtonVariant.outline,
              ),

              const Divider(height: AppSpacing.xl),

              // ── AppBadge ────────────────────────────────────────────────────
              const _SectionHeader('AppBadge'),
              SizedBox(height: t.s1),
              Text(
                'Five status pills — semantic colour + Lucide glyph per .spec().',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s2),
              const _SectionSpec([
                'paid     positive (#1F9D57)  check',
                'due      warning  (#F59E0B)  clock',
                'pastDue  error    (#E2473D)  circleAlert',
                'autoPay  info     (#3E7BD8)  repeat',
                'newBill  fgMuted  (#757B72)  fileText',
                'shape: pill  ·  fill: color@10%  ·  border: color@30%  ·  pad: h12/v4',
              ]),
              SizedBox(height: t.s3),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: const [
                  AppBadge(AppBadgeVariant.paid),
                  AppBadge(AppBadgeVariant.due),
                  AppBadge(AppBadgeVariant.pastDue),
                  AppBadge(AppBadgeVariant.autoPay),
                  AppBadge(AppBadgeVariant.newBill),
                ],
              ),

              const Divider(height: AppSpacing.xl),

              // ── AppBillRow ──────────────────────────────────────────────────
              const _SectionHeader('AppBillRow'),
              SizedBox(height: t.s1),
              Text(
                'List row: icon tile + title/subtitle + signed R amount + '
                'trailing badge. Negative amounts in error red, '
                'positive in positive green.',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s2),
              const _SectionSpec([
                'icon tile: rMd (16) radius  ·  tile fill: primary@10%',
                'amount: negative → error  ·  positive → positive',
                'badge: AppBadge (trailing)',
              ]),
              SizedBox(height: t.s3),
              const AppBillRow(
                icon: LucideIcons.droplet,
                title: 'Water & sanitation',
                subtitle: 'January 2026 statement',
                amount: -842.50,
                status: AppBadgeVariant.newBill,
              ),
              const AppBillRow(
                icon: LucideIcons.zap,
                title: 'Electricity',
                subtitle: 'Account 1002004821',
                amount: -1250,
                status: AppBadgeVariant.pastDue,
              ),
              const AppBillRow(
                icon: LucideIcons.trash2,
                title: 'Refuse removal',
                subtitle: 'Due 15 Jul 2026',
                amount: -180,
                status: AppBadgeVariant.due,
              ),
              const AppBillRow(
                icon: LucideIcons.house,
                title: 'Property rates',
                subtitle: 'Enrolled in AutoPay',
                amount: -1430.75,
                status: AppBadgeVariant.autoPay,
              ),
              const AppBillRow(
                icon: LucideIcons.banknote,
                title: 'Payment received',
                subtitle: 'EFT · 28 Jun 2026',
                amount: 2000,
                status: AppBadgeVariant.paid,
              ),

              const Divider(height: AppSpacing.xl),

              // ── AppFormField ────────────────────────────────────────────────
              const _SectionHeader('AppFormField'),
              SizedBox(height: t.s1),
              Text(
                'Leading-glyph slot (Lucide icon or text prefix) + four ring '
                'states. Tap any enabled field to see the sky-500 focus ring.',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s2),
              const _SectionSpec([
                'resting   border: hairline 1px  ·  fill: surface',
                'focused   border: secondary (sky-500) 2px',
                'error     border: negative (#E2473D) 2px  ·  helper text below',
                'disabled  border: hairline 1px  ·  fill: sunken  ·  fg: fgMuted',
                'radius: rMd (16)  ·  glyph: iconSm (18)',
              ]),
              SizedBox(height: t.s3),
              const AppFormField(
                label: 'Account number',
                hint: 'e.g. 1234567890',
                icon: LucideIcons.hash,
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: t.s3),
              const AppFormField(
                label: 'Amount',
                hint: '0.00',
                prefixText: 'R',
                keyboardType: TextInputType.number,
              ),
              SizedBox(height: t.s3),
              const AppFormField(
                label: 'Account number',
                hint: 'e.g. 1234567890',
                icon: LucideIcons.hash,
                errorText: 'No account found for that number.',
              ),
              SizedBox(height: t.s3),
              const AppFormField(
                label: 'Account number',
                prefixText: '#',
                hint: 'Locked',
                enabled: false,
              ),

              const Divider(height: AppSpacing.xl),

              // ── AppTabBar ───────────────────────────────────────────────────
              const _SectionHeader('AppTabBar'),
              SizedBox(height: t.s1),
              Text(
                'Floating ink-900 pill bar — dark in both modes. '
                'Lime active pill expands to show label; tap to switch.',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s2),
              const _SectionSpec([
                'surface: ink900 (#0A0B0A) — brightness-independent',
                'inactive: onInkMuted (#AFB4AC) glyph only',
                'active: primary (lime) pill  ·  fg: onPrimary  ·  icon + label',
                'pad: s2 (8) slab inner  ·  active pill: s4×s2 (16×8)  ·  radius: pill',
              ]),
              SizedBox(height: t.s3),
              const _TabBarDemo(),

              const Divider(height: AppSpacing.xl),

              // ── Fidelity notes ──────────────────────────────────────────────
              const _SectionHeader('Fidelity notes'),
              SizedBox(height: t.s1),
              Text(
                'Gaps observed between the current kit and the Mohapi V1 spec '
                'sheet. Each note names the component, the divergence, and '
                'the smallest fix.',
                style: tt.bodyMedium,
              ),
              SizedBox(height: t.s3),
              const _GapNote(
                component: 'AppButton.secondary',
                gap: 'Uses inverseSurface — renders a light pill in light mode. '
                    'Mohapi V1 calls for an ink pill dark in both modes.',
                fix: 'Replace inverseSurface/onInverseSurface with t.inkSurface/t.onInkMuted.',
              ),
              const _GapNote(
                component: 'AppButton — no expand flag',
                gap: 'Content-sized only. Login and payment screens need fill-width CTAs.',
                fix: 'Add expand: bool = false; wraps in SizedBox.expand when true.',
              ),
              const _GapNote(
                component: 'AppBadge.newBill',
                gap: 'Uses fgMuted (grey). A new-unread item may need more visual weight.',
                fix: 'Swap fgMuted → t.info (sky-500) if the intent is "needs attention".',
              ),
              const _GapNote(
                component: 'AppFormField — no trailing slot',
                gap: 'No trailing action widget (visibility toggle, clear, scan icon).',
                fix: 'Add trailing: Widget? rendered after the text input inside the ring.',
              ),
              const _GapNote(
                component: 'AppFormField — no helper text',
                gap: 'No below-field helper or character counter row.',
                fix: 'Add helperText: String?, render bodySmall/fgMuted below the ring.',
              ),
              const _GapNote(
                component: 'AppTabBar — no notification dot',
                gap: 'Tab items carry no badge indicator. Alerts tab needs an unread dot.',
                fix: 'Add badge: int? to AppTabItem; render a 6×6 positive dot when > 0.',
              ),
              const _GapNote(
                component: 'AppBillRow — token audit pending',
                gap: 'Externally added; amount colours not traced to design tokens.',
                fix: 'Audit app_bill_row.dart for raw Material palette references '
                    '→ replace with scheme.error / t.positive.',
              ),
              const _GapNote(
                component: 'AppButton — no semanticLabel',
                gap: 'Icon-only or context-sparse labels may under-describe for screen readers.',
                fix: 'Thread semanticLabel: String? through the Semantics wrapper.',
              ),
              SizedBox(height: t.s8),
            ],
          ),
        );
      }),
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) =>
      Text(title, style: Theme.of(context).textTheme.headlineSmall);
}

// A compact sunken box listing the tokens driving the component directly below.
class _SectionSpec extends StatelessWidget {
  const _SectionSpec(this.lines);
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<EasyRatesTokens>()!;
    final style =
        Theme.of(context).textTheme.labelSmall!.copyWith(color: t.fgMuted);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(t.s2),
      decoration: BoxDecoration(
        color: t.sunken,
        borderRadius: t.radiusSm,
        border: Border.all(color: t.hairline, width: t.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            Text(lines[i], style: style),
          ],
        ],
      ),
    );
  }
}

// One gap-note card: component name (in warning amber), the observed
// divergence, and the smallest suggested fix.
class _GapNote extends StatelessWidget {
  const _GapNote({
    required this.component,
    required this.gap,
    required this.fix,
  });

  final String component;
  final String gap;
  final String fix;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<EasyRatesTokens>()!;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: t.s3),
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(t.s3, t.s2, t.s2, t.s2),
        decoration: BoxDecoration(
          color: t.sunken,
          borderRadius: t.radiusSm,
          border: Border(
            left: BorderSide(color: t.warning, width: t.borderWidthFocus),
            top: BorderSide(color: t.hairline, width: t.borderWidth),
            right: BorderSide(color: t.hairline, width: t.borderWidth),
            bottom: BorderSide(color: t.hairline, width: t.borderWidth),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(component,
                style: tt.labelMedium!.copyWith(color: t.warning)),
            SizedBox(height: t.s1),
            Text(gap, style: tt.bodySmall),
            SizedBox(height: t.s1),
            Text('Fix: $fix',
                style: tt.bodySmall!.copyWith(color: t.fgMuted)),
          ],
        ),
      ),
    );
  }
}

/// Holds the selected-tab state for the interactive AppTabBar demo.
class _TabBarDemo extends StatefulWidget {
  const _TabBarDemo();

  @override
  State<_TabBarDemo> createState() => _TabBarDemoState();
}

class _TabBarDemoState extends State<_TabBarDemo> {
  int _index = 0;

  @override
  Widget build(BuildContext context) => AppTabBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      );
}

/// One labelled group for AppButton: resting, with leading icon, disabled.
class _VariantBlock extends StatelessWidget {
  const _VariantBlock({required this.title, required this.variant});

  final String title;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.labelMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppButton(
                label: 'Pay account',
                variant: variant,
                onPressed: () {},
              ),
              AppButton(
                label: 'Pay account',
                variant: variant,
                icon: LucideIcons.arrowRight,
                onPressed: () {},
              ),
              AppButton(
                label: 'Disabled',
                variant: variant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
