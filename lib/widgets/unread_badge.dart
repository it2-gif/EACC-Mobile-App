import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class UnreadBadge extends StatelessWidget {
  final int count;
  final Color color;
  final String? label;
  final bool compact;

  const UnreadBadge({
    super.key,
    required this.count,
    this.color = AppColors.danger,
    this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final text = label ?? (count > 99 ? '99+' : '$count');

    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0.82, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 22 : 26),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 5,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
