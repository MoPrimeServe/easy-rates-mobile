// home_screen.dart — the Mohapi V1 Home screen, light brightness.
//
// Composes:
//   • greeting row     — "Hi {name}" + Lucide bell
//   • AppBalanceCard   — lime hero: total owed in R, masked account, due date
//   • quick-action row — 5 icon+label tiles: Pay / Bills / Usage / Auto-pay / More
//   • sky tip banner   — sky-100 fill, info glyph, short usage-tip copy
//   • "Your bills"     — AppBillRow list with Emfuleni service lines + AppBadge
//   • AppTabBar        — floating ink-900 bar; Home tab selected by default
//
// All money is rendered in R (South African Rand) via AppBalanceCard /
// AppBillRow's built-in R formatters. Nothing is hardcoded — every colour,
// spacing, and radius resolves through the EasyRatesTokens extension.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;
    final themeCtrl = context.watch<ThemeController>();

    const tabBarHeight = 72.0; // approximate floating bar height + margin

    return Scaffold(
      backgroundColor: t.appBg,
      body: Stack(
        children: [
          // ── Scrollable content ─────────────────────────────────────────────
          SafeArea(
            bottom: false, // tab bar handles bottom clearance
            child: ListView(
              padding: EdgeInsets.only(
                left: t.s5,
                right: t.s5,
                top: t.s4,
                bottom: tabBarHeight + t.s5,
              ),
              children: [
                // ── Greeting row ─────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Hi T. Mokoena',
                        style: tt.headlineSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: t.s2),
                    IconButton(
                      icon: Icon(
                        themeCtrl.isDark ? LucideIcons.sun : LucideIcons.moon,
                        size: t.iconLg,
                        color: scheme.onSurface,
                      ),
                      onPressed: () => themeCtrl.toggle(),
                      tooltip: themeCtrl.isDark ? 'Switch to light' : 'Switch to dark',
                    ),
                    IconButton(
                      icon: Icon(
                        LucideIcons.bell,
                        size: t.iconLg,
                        color: scheme.onSurface,
                      ),
                      onPressed: () {},
                      tooltip: 'Notifications',
                    ),
                  ],
                ),
                SizedBox(height: t.s3),

                // ── Balance card ──────────────────────────────────────────────
                AppBalanceCard(
                  totalOwed: 12480.75,
                  accountHolder: 'T. Mokoena',
                  accountNumber: '1002004821',
                  dueDate: DateTime(2026, 7, 15),
                ),
                SizedBox(height: t.s5),

                // ── Quick-action row ──────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _QuickAction(icon: LucideIcons.banknote, label: 'Pay',      onTap: () => context.go('/pay')),
                    _QuickAction(icon: LucideIcons.receipt,  label: 'Bills',    onTap: () {}),
                    _QuickAction(icon: LucideIcons.droplet,  label: 'Usage',    onTap: () => context.go('/usage')),
                    _QuickAction(icon: LucideIcons.repeat,   label: 'Auto-pay', onTap: () {}),
                    _QuickAction(icon: LucideIcons.ellipsis, label: 'More',     onTap: () {}),
                  ],
                ),
                SizedBox(height: t.s5),

                // ── Sky tip banner ────────────────────────────────────────────
                _TipBanner(
                  icon: LucideIcons.info,
                  text: 'Your water usage is 12% above the July average. '
                      'Check the Usage tab for a breakdown.',
                ),
                SizedBox(height: t.s5),

                // ── "Your bills" section ──────────────────────────────────────
                Text('Your bills', style: tt.titleMedium),
                SizedBox(height: t.s2),
                // Sunken card wrapping the bill rows — mirrors the spec's
                // list-on-surface treatment (borderRadius rLg).
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: t.radiusLg,
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: t.borderWidth,
                    ),
                  ),
                  child: Column(
                    children: [
                      AppBillRow(
                        icon: LucideIcons.droplet,
                        title: 'Water & sanitation',
                        subtitle: 'June 2026 statement',
                        amount: -842.50,
                        status: AppBadgeVariant.newBill,
                        onTap: () {},
                      ),
                      Divider(
                        height: 1,
                        indent: t.s12 + t.s3 + t.s4, // align with text column
                        color: scheme.outlineVariant,
                      ),
                      AppBillRow(
                        icon: LucideIcons.zap,
                        title: 'Electricity',
                        subtitle: 'Account 1002004821',
                        amount: -1250.00,
                        status: AppBadgeVariant.pastDue,
                        onTap: () {},
                      ),
                      Divider(
                        height: 1,
                        indent: t.s12 + t.s3 + t.s4,
                        color: scheme.outlineVariant,
                      ),
                      AppBillRow(
                        icon: LucideIcons.trash2,
                        title: 'Refuse removal',
                        subtitle: 'Due 15 Jul 2026',
                        amount: -180.00,
                        status: AppBadgeVariant.due,
                        onTap: () {},
                      ),
                      Divider(
                        height: 1,
                        indent: t.s12 + t.s3 + t.s4,
                        color: scheme.outlineVariant,
                      ),
                      AppBillRow(
                        icon: LucideIcons.house,
                        title: 'Property rates',
                        subtitle: 'Enrolled in AutoPay',
                        amount: -1430.75,
                        status: AppBadgeVariant.autoPay,
                        onTap: () {},
                      ),
                      Divider(
                        height: 1,
                        indent: t.s12 + t.s3 + t.s4,
                        color: scheme.outlineVariant,
                      ),
                      AppBillRow(
                        icon: LucideIcons.banknote,
                        title: 'Payment received',
                        subtitle: 'EFT · 28 Jun 2026',
                        amount: 2000.00,
                        status: AppBadgeVariant.paid,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Floating tab bar ──────────────────────────────────────────────
          Positioned(
            left: t.s4,
            right: t.s4,
            bottom: t.s4,
            child: SafeArea(
              top: false,
              child: AppTabBar(
                currentIndex: _tabIndex,
                onTap: (i) {
                  if (i == 2) { context.go('/usage'); return; }
                  if (i == 4) { context.go('/gallery'); return; }
                  setState(() => _tabIndex = i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick-action tile ─────────────────────────────────────────────────────────
// A rounded-square icon tile + label below, for the 5-action row.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = Theme.of(context).extension<EasyRatesTokens>()!;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: t.s12,  // 48 — same tile size as AppBillRow icon tile
              height: t.s12,
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: t.radiusMd,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: t.iconMd, color: scheme.onSurfaceVariant),
            ),
            SizedBox(height: t.s1),
            Text(
              label,
              style: tt.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sky tip banner ────────────────────────────────────────────────────────────
// A sky-100 tinted info strip with a leading glyph and one-liner copy.
class _TipBanner extends StatelessWidget {
  const _TipBanner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final t = Theme.of(context).extension<EasyRatesTokens>()!;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.s4, vertical: t.s3),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,   // sky-100
        borderRadius: t.radiusMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: t.iconSm, color: scheme.onSecondaryContainer),
          SizedBox(width: t.s2),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall!.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
