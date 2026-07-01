import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/reports_provider.dart';
import '../models/report_models.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ReportsProvider(),
      child: Consumer<ReportsProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text('Executive Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => provider.loadData(),
                  tooltip: 'Refresh Reports',
                ),
              ],
            ),
            body: provider.isLoading && provider.salesReport.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _buildDashboardContent(context, provider),
          );
        },
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context, ReportsProvider provider) {
    final alerts = provider.alerts.where((a) => a.severity == 'warning').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Spoilage/Waste Warnings Container
          if (alerts.isNotEmpty) ...[
            _buildAlertsSection(context, alerts),
            const SizedBox(height: 24),
          ],

          // 2. Premium Stat Cards Grid
          _buildStatGrid(provider),
          const SizedBox(height: 32),

          // 3. Profit Funnel & Margin Watchlist (Two Columns on large screens, stacked on small)
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 900) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildProfitFunnel(provider)),
                    const SizedBox(width: 24),
                    Expanded(flex: 4, child: _buildMarginWatchlist(provider)),
                  ],
                );
              } else {
                return Column(
                  children: [
                    _buildProfitFunnel(provider),
                    const SizedBox(height: 24),
                    _buildMarginWatchlist(provider),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection(BuildContext context, List<SystemAlertModel> alerts) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2), // Very soft Red
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red[300]!, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              const SizedBox(width: 8),
              Text(
                'Critical Operational Alerts (${alerts.length})',
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...alerts.map((alert) => Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '• ${alert.title}: ${alert.message}',
                  style: TextStyle(color: Colors.red[900], fontSize: 13, fontWeight: FontWeight.w500),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStatGrid(ReportsProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 600 ? 4 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.6,
          children: [
            _buildStatCard('Gross Sales', 'Rp ${provider.totalRevenue.toStringAsFixed(0)}', Icons.payments, Colors.blue),
            _buildStatCard('Total COGS', 'Rp ${provider.totalCOGS.toStringAsFixed(0)}', Icons.shopping_bag, Colors.orange),
            _buildStatCard('Net Gross Profit', 'Rp ${provider.totalGrossProfit.toStringAsFixed(0)}', Icons.trending_up, Colors.green),
            _buildStatCard('Gross Margin %', '${provider.grossMarginPercent.toStringAsFixed(1)}%', Icons.pie_chart, Colors.purple),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
              Icon(icon, color: color, size: 20),
            ],
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildProfitFunnel(ReportsProvider provider) {
    final revenue = provider.totalRevenue;
    final cogs = provider.totalCOGS;
    final profit = provider.totalGrossProfit;

    final cogsPercent = revenue > 0 ? (cogs / revenue) * 100 : 0.0;
    final profitPercent = revenue > 0 ? (profit / revenue) * 100 : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The Profit Funnel', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 24),
          
          // Funnel visualization
          _buildFunnelBar('Revenue', revenue, 100.0, Colors.blue),
          const SizedBox(height: 16),
          _buildFunnelBar('COGS', cogs, cogsPercent, Colors.orange),
          const SizedBox(height: 16),
          _buildFunnelBar('Net Operating Profit', profit, profitPercent, Colors.green),
        ],
      ),
    );
  }

  Widget _buildFunnelBar(String label, double value, double percent, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
            Text('Rp ${value.toStringAsFixed(0)} (${percent.toStringAsFixed(1)}%)', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 16,
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: (percent / 100.0).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarginWatchlist(ReportsProvider provider) {
    final list = provider.margins;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Margin Watchlist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          list.isEmpty
              ? Center(child: Text('No item margins logged yet', style: TextStyle(color: Colors.grey[400])))
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length.clamp(0, 10),
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final isLow = item.marginPercent < 60.0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('Qty Sold: ${item.qty} | COGS: Rp ${item.cogs.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isLow ? Colors.red[50] : Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isLow ? Colors.red[200]! : Colors.green[200]!),
                        ),
                        child: Text(
                          '${item.marginPercent.toStringAsFixed(1)}% margin',
                          style: TextStyle(
                            color: isLow ? Colors.red[700] : Colors.green[700],
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
