import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';

Tone stockTone(StockStatus s) => switch (s) {
  StockStatus.inStock => Tone.success,
  StockStatus.lowStock => Tone.warning,
  StockStatus.outOfStock => Tone.error,
  StockStatus.untracked => Tone.neutral,
};

/// Colour-keyed initials tile used until product photos are supported.
class ProductAvatar extends StatelessWidget {
  const ProductAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  static const _palette = [
    (BizColors.secondaryContainer, BizColors.onSecondaryContainer),
    (BizColors.primaryContainer, BizColors.onPrimaryContainer),
    (Color(0xFFE8EAF4), BizColors.navy),
  ];

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette[name.hashCode.abs() % _palette.length];
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final initials = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.md)),
        child: Text(
          initials,
          style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: size * 0.34),
        ),
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, required this.currency, this.onTap, this.trailing});

  final Product product;
  final String currency;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = product;
    final subtitle = [if (p.variantLine.isNotEmpty) p.variantLine, if (p.sku != null) 'SKU ${p.sku}'].join('  ·  ');
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(Space.sm),
      child: Row(
        children: [
          ProductAvatar(name: p.name),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: Space.xxs),
                Row(
                  children: [
                    Flexible(
                      child: StatusChip(
                        p.trackStock ? '${p.quantityOnHand} ${p.unit}' : p.stockStatus.label,
                        tone: stockTone(p.stockStatus),
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: MoneyText(p.sellingPrice.format(currency), style: t.titleSmall),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: Space.sm), trailing!],
        ],
      ),
    );
  }
}
