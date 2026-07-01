import 'package:flutter/material.dart';
import 'app_card.dart';
import '../../core/theme/app_colors.dart';

class AppMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final String? trend;
  final bool isPositiveTrend;

  const AppMetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.trend,
    this.isPositiveTrend = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyMedium),
              Icon(icon, size: 20, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          if (trend != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isPositiveTrend ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: isPositiveTrend ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 4),
                Text(
                  trend!,
                  style: TextStyle(
                    color: isPositiveTrend ? AppColors.success : AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          ]
        ],
      ),
    );
  }
}
