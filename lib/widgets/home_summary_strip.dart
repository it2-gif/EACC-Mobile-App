import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class HomeSummaryStrip extends StatelessWidget {
  final List<HomeSummaryItem> items;

  const HomeSummaryStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: compact
              ? Column(
                  children: [
                    for (var index = 0; index < items.length; index += 1) ...[
                      _SummaryTile(item: items[index], compact: true),
                      if (index != items.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                )
              : Row(
                  children: [
                    for (var index = 0; index < items.length; index += 1) ...[
                      Expanded(child: _SummaryTile(item: items[index])),
                      if (index != items.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class HomeSummaryItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const HomeSummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
  });
}

class _SummaryTile extends StatelessWidget {
  final HomeSummaryItem item;
  final bool compact;

  const _SummaryTile({required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 10,
        vertical: compact ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: item.color.withValues(alpha: 0.13)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: item.color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
