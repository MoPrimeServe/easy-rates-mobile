// app_tab_bar.dart — a floating ink-900 tab bar with a lime active pill.
//
// The bar is a dark ink slab (t.ink900) in BOTH brightnesses — the signature
// inverted surface. The selected tab sits inside a lime pill (primary) with an
// ink label (onPrimary) and expands to show its label; unselected tabs are a
// single muted-light glyph (onInkMuted). Selection is driven from outside via
// [currentIndex] + [onTap], so a screen owns the navigation state.
//
// Every value — surface, pill, glyph, label, padding, radius, icon size — comes
// from the token store. Nothing is hardcoded.
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/theme.dart';

// One tab's data — a Lucide glyph + its label.
@immutable
class AppTabItem {
  const AppTabItem({required this.icon, required this.label});
  final IconData icon;
  final String label;
}

// The EasyRates municipal nav: Home · Bills · Water · Alerts · Account.
const List<AppTabItem> kEmfuleniTabs = [
  AppTabItem(icon: LucideIcons.house, label: 'Home'),
  AppTabItem(icon: LucideIcons.receipt, label: 'Bills'),
  AppTabItem(icon: LucideIcons.droplet, label: 'Water'),
  AppTabItem(icon: LucideIcons.bell, label: 'Alerts'),
  AppTabItem(icon: LucideIcons.user, label: 'Account'),
];

class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    this.items = kEmfuleniTabs,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).extension<EasyRatesTokens>()!;

    return Container(
      padding: EdgeInsets.all(t.s2), // 8 — inset that makes the pills float in the slab
      decoration: BoxDecoration(
        color: t.ink900, // deepest ink — dark in both modes
        borderRadius: t.radiusPill, // floating pill bar
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < items.length; i++)
            _Tab(
              item: items[i],
              selected: i == currentIndex,
              onTap: () => onTap(i),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});

  final AppTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).extension<EasyRatesTokens>()!;
    final labelStyle = Theme.of(context).textTheme.labelMedium!;

    // Active content reads ink-on-lime; inactive reads muted-light-on-ink.
    final color = selected ? scheme.onPrimary : t.onInkMuted;

    final child = selected
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: t.iconMd, color: color),
              SizedBox(width: t.s2),
              Text(item.label, style: labelStyle.copyWith(color: color)),
            ],
          )
        : Icon(item.icon, size: t.iconMd, color: color);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: selected
              ? EdgeInsets.symmetric(horizontal: t.s4, vertical: t.s2) // 16/8 pill
              : EdgeInsets.all(t.s2), // 8 — equal height to the pill
          decoration: BoxDecoration(
            color: selected ? scheme.primary : null, // lime active pill
            borderRadius: t.radiusPill,
          ),
          child: child,
        ),
      ),
    );
  }
}
