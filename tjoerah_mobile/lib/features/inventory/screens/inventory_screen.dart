import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/inventory_provider.dart';
import '../models/inventory_models.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => InventoryProvider(),
      child: Consumer<InventoryProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              title: const Text('Stock & Inventory', style: TextStyle(fontWeight: FontWeight.bold)),
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: const [
                  Tab(text: 'Stock Balances'),
                  Tab(text: 'Movement Logs'),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => provider.loadInventory(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: ElevatedButton.icon(
                    onPressed: () => _showActionDialog(context, provider),
                    icon: const Icon(Icons.add),
                    label: const Text('Log Stock Incident'),
                  ),
                ),
              ],
            ),
            body: provider.isLoading && provider.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildStockTab(context, provider),
                      _buildMovementsTab(context, provider),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _buildStockTab(BuildContext context, InventoryProvider provider) {
    final filteredItems = provider.items.where((item) {
      return item.name.toLowerCase().contains(_searchQuery) || item.sku.toLowerCase().contains(_searchQuery);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search items by name or SKU...',
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),
        Expanded(
          child: filteredItems.isEmpty
              ? const Center(child: Text('No stock items match your search.'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: filteredItems.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = filteredItems[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: item.isLowStock ? Colors.red[50] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          item.isLowStock ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                          color: item.isLowStock ? Colors.red : Colors.grey[600],
                        ),
                      ),
                      title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('SKU: ${item.sku} | Cost: Rp ${item.weightedAverageCost.toStringAsFixed(0)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${item.currentStock.toStringAsFixed(0)} ${item.unit}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: item.isLowStock ? Colors.red : AppColors.textPrimary,
                            ),
                          ),
                          if (item.isLowStock)
                            const Text(
                              'Low Stock Alert',
                              style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMovementsTab(BuildContext context, InventoryProvider provider) {
    final movements = provider.movements;

    if (movements.isEmpty) {
      return const Center(child: Text('No stock movements recorded yet.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: movements.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, index) {
        final movement = movements[index];
        final isNegative = movement.quantity < 0;
        final color = isNegative ? Colors.red : Colors.green;

        return ListTile(
          leading: Icon(
            isNegative ? Icons.arrow_downward : Icons.arrow_upward,
            color: color,
          ),
          title: Text(movement.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${movement.type.toUpperCase()} | Reason: ${movement.reason ?? 'N/A'}'),
          trailing: Text(
            '${isNegative ? "" : "+"}${movement.quantity.toStringAsFixed(0)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
          ),
        );
      },
    );
  }

  void _showActionDialog(BuildContext context, InventoryProvider provider) {
    if (provider.items.isEmpty) return;

    InventoryItemModel selectedItem = provider.items.first;
    String selectedAction = 'spoilage'; // 'spoilage' or 'adjustment'
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Log Stock Incident', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Item Selection
                    DropdownButtonFormField<InventoryItemModel>(
                      initialValue: selectedItem,
                      decoration: const InputDecoration(labelText: 'Inventory Item'),
                      items: provider.items.map((item) {
                        return DropdownMenuItem(
                          value: item,
                          child: Text(item.name),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => selectedItem = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Action Selection
                    DropdownButtonFormField<String>(
                      initialValue: selectedAction,
                      decoration: const InputDecoration(labelText: 'Incident Type'),
                      items: const [
                        DropdownMenuItem(value: 'spoilage', child: Text('Waste / Spoilage (Negative)')),
                        DropdownMenuItem(value: 'adjustment', child: Text('Manual Adjustment (Delta)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => selectedAction = val);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Quantity Input
                    TextField(
                      controller: qtyController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Quantity',
                        suffixText: selectedItem.unit,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Reason
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(labelText: 'Reason / Description'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final qty = double.tryParse(qtyController.text) ?? 0.0;
                    if (qty <= 0) return;

                    bool success = false;
                    if (selectedAction == 'spoilage') {
                      success = await provider.logWastage(
                        itemId: selectedItem.id,
                        warehouseId: 1, // Default warehouse ID
                        outletId: 1, // Default outlet ID
                        qty: qty,
                        reason: reasonController.text,
                      );
                    } else {
                      success = await provider.adjustStock(
                        itemId: selectedItem.id,
                        warehouseId: 1, // Default warehouse ID
                        qty: qty,
                        reason: reasonController.text,
                      );
                    }

                    if (success && context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stock incident successfully recorded.')),
                      );
                    }
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
