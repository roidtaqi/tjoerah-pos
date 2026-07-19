import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tjoerah_mobile/core/theme/app_theme.dart';
import 'package:tjoerah_mobile/core/theme/theme_provider.dart';
import 'package:tjoerah_mobile/features/auth/providers/auth_provider.dart';
import 'package:tjoerah_mobile/features/customers/models/customer_model.dart';
import 'package:tjoerah_mobile/features/customers/providers/customer_provider.dart';
import 'package:tjoerah_mobile/features/customers/screens/customers_screen.dart';
import 'package:tjoerah_mobile/features/dashboard/screens/dashboard_screen.dart';
import 'package:tjoerah_mobile/features/inventory/models/inventory_models.dart';
import 'package:tjoerah_mobile/features/inventory/providers/inventory_provider.dart';
import 'package:tjoerah_mobile/features/inventory/screens/inventory_screen.dart';
import 'package:tjoerah_mobile/features/kds/models/kitchen_ticket_model.dart';
import 'package:tjoerah_mobile/features/kds/providers/kds_provider.dart';
import 'package:tjoerah_mobile/features/kds/screens/kds_screen.dart';
import 'package:tjoerah_mobile/features/operations/screens/operations_screen.dart';
import 'package:tjoerah_mobile/features/orders/models/order_history_model.dart';
import 'package:tjoerah_mobile/features/orders/providers/order_history_provider.dart';
import 'package:tjoerah_mobile/features/orders/screens/orders_screen.dart';
import 'package:tjoerah_mobile/features/outlets/models/outlet_summary_model.dart';
import 'package:tjoerah_mobile/features/outlets/providers/outlet_provider.dart';
import 'package:tjoerah_mobile/features/outlets/screens/outlets_screen.dart';
import 'package:tjoerah_mobile/features/pos/models/category_model.dart';
import 'package:tjoerah_mobile/features/pos/models/product_model.dart';
import 'package:tjoerah_mobile/features/pos/models/table_models.dart';
import 'package:tjoerah_mobile/features/pos/providers/cart_provider.dart';
import 'package:tjoerah_mobile/features/pos/providers/catalog_provider.dart';
import 'package:tjoerah_mobile/features/pos/providers/table_provider.dart';
import 'package:tjoerah_mobile/features/pos/screens/payment_screen.dart';
import 'package:tjoerah_mobile/features/pos/screens/pos_screen.dart';
import 'package:tjoerah_mobile/features/pos/screens/table_selection_screen.dart';
import 'package:tjoerah_mobile/features/pos/screens/table_management_screen.dart';
import 'package:tjoerah_mobile/features/recipe/models/recipe_models.dart';
import 'package:tjoerah_mobile/features/recipe/providers/recipe_provider.dart';
import 'package:tjoerah_mobile/features/recipe/screens/recipe_screen.dart';
import 'package:tjoerah_mobile/features/reports/models/report_models.dart';
import 'package:tjoerah_mobile/features/reports/providers/reports_provider.dart';
import 'package:tjoerah_mobile/features/reports/screens/reports_screen.dart';
import 'package:tjoerah_mobile/features/settings/providers/printer_provider.dart';
import 'package:tjoerah_mobile/features/settings/providers/sync_provider.dart';
import 'package:tjoerah_mobile/features/settings/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('POS renders without overflow on phone and tablet', (
    tester,
  ) async {
    await _render(
      tester,
      size: const Size(390, 844),
      screen: const PosScreen(),
      overrides: _posOverrides(),
    );
    expect(find.text('Pesanan baru'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 800),
      screen: const PosScreen(),
      overrides: _posOverrides(),
    );
    expect(find.text('Pesanan saat ini'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('KDS board adapts between phone and tablet', (tester) async {
    await _render(
      tester,
      size: const Size(390, 844),
      screen: const KdsScreen(),
      overrides: [kdsNotifierProvider.overrideWith(_PreviewKdsNotifier.new)],
    );
    expect(find.textContaining('Tunggu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 800),
      screen: const KdsScreen(),
      overrides: [kdsNotifierProvider.overrideWith(_PreviewKdsNotifier.new)],
    );
    expect(find.text('Menunggu'), findsOneWidget);
    expect(find.text('Dimasak'), findsOneWidget);
    expect(find.text('Siap diambil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inventory and reports render operational data', (tester) async {
    await _render(
      tester,
      size: const Size(390, 844),
      screen: const InventoryScreen(),
      overrides: [
        inventoryProvider.overrideWith(_PreviewInventoryNotifier.new),
      ],
    );
    expect(find.text('Stok menipis'), findsWidgets);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 900),
      screen: const ReportsScreen(),
      overrides: [reportsProvider.overrideWith(_PreviewReportsNotifier.new)],
    );
    expect(find.text('Kinerja outlet'), findsOneWidget);
    expect(find.text('Tren penjualan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('table, recipe, payment, and settings screens stay responsive', (
    tester,
  ) async {
    await _render(
      tester,
      size: const Size(390, 844),
      screen: const TableSelectionScreen(),
      overrides: [tableProvider.overrideWith(_PreviewTableNotifier.new)],
    );
    expect(find.text('Meja 01'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 800),
      screen: const TableManagementScreen(),
      overrides: [tableProvider.overrideWith(_PreviewTableNotifier.new)],
    );
    expect(find.text('Atur meja & area'), findsOneWidget);
    expect(find.text('Tambah meja'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 800),
      screen: const RecipeScreen(),
      overrides: [recipeProvider.overrideWith(_PreviewRecipeNotifier.new)],
    );
    expect(find.text('Kopi Susu Tjoerah'), findsWidgets);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(390, 844),
      screen: const PaymentScreen(),
      overrides: [cartProvider.overrideWith(_PreviewCartNotifier.new)],
    );
    expect(find.text('Metode pembayaran'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(390, 844),
      screen: const SettingsScreen(),
      overrides: [
        authProvider.overrideWith(_PreviewAuthNotifier.new),
        syncProvider.overrideWith(_PreviewSyncNotifier.new),
        printerProvider.overrideWith(_PreviewPrinterNotifier.new),
        themeModeProvider.overrideWith(_PreviewThemeNotifier.new),
      ],
    );
    expect(find.text('Operasional'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role-specific screens render useful data without overflow', (
    tester,
  ) async {
    await _render(
      tester,
      size: const Size(390, 844),
      screen: const OrdersScreen(),
      overrides: [
        orderHistoryProvider.overrideWith(_PreviewOrderHistoryNotifier.new),
        printerProvider.overrideWith(_PreviewPrinterNotifier.new),
      ],
    );
    expect(find.text('Pesanan hari ini'), findsOneWidget);
    expect(find.text('TJ-260715-090001'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('TJ-260715-090001'));
    await tester.pumpAndSettle();
    expect(find.text('Cetak ulang'), findsOneWidget);
    expect(find.text('Struk pelanggan'), findsOneWidget);
    expect(find.text('Tiket dapur'), findsOneWidget);
    expect(find.text('Cetak semua dokumen'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(390, 844),
      screen: const CustomersScreen(),
      overrides: [customerProvider.overrideWith(_PreviewCustomerNotifier.new)],
    );
    expect(find.text('Total pelanggan'), findsOneWidget);
    expect(find.text('Ayu Lestari'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 800),
      screen: const OutletsScreen(),
      overrides: [outletProvider.overrideWith(_PreviewOutletNotifier.new)],
    );
    expect(find.text('Outlet aktif'), findsOneWidget);
    expect(find.text('Tjoerah Coffee - Renon'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 800),
      screen: const OperationsScreen(),
      overrides: [
        kdsNotifierProvider.overrideWith(_PreviewKdsNotifier.new),
        inventoryProvider.overrideWith(_PreviewInventoryNotifier.new),
        tableProvider.overrideWith(_PreviewTableNotifier.new),
      ],
    );
    expect(find.text('Layanan outlet'), findsOneWidget);
    expect(find.text('Persediaan & menu'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _render(
      tester,
      size: const Size(1280, 900),
      screen: const DashboardScreen(),
      overrides: [
        authProvider.overrideWith(_PreviewOwnerAuthNotifier.new),
        reportsProvider.overrideWith(_PreviewReportsNotifier.new),
        inventoryProvider.overrideWith(_PreviewInventoryNotifier.new),
        outletProvider.overrideWith(_PreviewOutletNotifier.new),
      ],
    );
    expect(find.text('Perbandingan outlet'), findsOneWidget);
    expect(find.text('Produk teratas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _render(
  WidgetTester tester, {
  required Size size,
  required Widget screen,
  required dynamic overrides,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.lightTheme, home: screen),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

dynamic _posOverrides() => [
  catalogProvider.overrideWith(_PreviewCatalogNotifier.new),
  cartProvider.overrideWith(_PreviewCartNotifier.new),
];

class _PreviewCatalogNotifier extends CatalogNotifier {
  @override
  Future<CatalogState> build() async {
    final categories = [
      CategoryModel(id: '1', name: 'Kopi'),
      CategoryModel(id: '2', name: 'Non Kopi'),
      CategoryModel(id: '3', name: 'Makanan'),
      CategoryModel(id: '4', name: 'Pastry'),
    ];
    return CatalogState(
      categories: categories,
      products: List.generate(12, (index) {
        const names = [
          'Kopi Susu Tjoerah',
          'Cappuccino',
          'Americano',
          'Matcha Latte',
          'Chocolate',
          'Lemon Tea',
          'Nasi Goreng Kampung',
          'Chicken Katsu',
          'Croissant Butter',
          'Pain au Chocolat',
          'Espresso',
          'Caramel Latte',
        ];
        return ProductModel(
          id: '${index + 1}',
          name: names[index],
          price: 22000 + (index * 2500),
          categoryId: '${(index % 4) + 1}',
          sku: 'SKU-${index + 1}',
          station: index % 3 == 0 ? 'kitchen' : 'bar',
        );
      }),
    );
  }
}

class _PreviewCartNotifier extends CartNotifier {
  @override
  CartState build() => const CartState(
    orderType: 'dine_in',
    tableId: '7',
    tableName: 'Meja 07',
    customerName: 'Ayu',
    discountPercent: 10,
    items: [
      CartItem(
        productId: '1',
        name: 'Kopi Susu Tjoerah',
        price: 28000,
        quantity: 2,
      ),
      CartItem(productId: '4', name: 'Matcha Latte', price: 34000),
      CartItem(productId: '9', name: 'Croissant Butter', price: 26000),
    ],
  );
}

class _PreviewKdsNotifier extends KdsNotifier {
  @override
  Future<List<KitchenTicketModel>> build() async {
    final now = DateTime.now();
    return [
      _ticket(
        'AA1201',
        'pending',
        now.subtract(const Duration(minutes: 11)),
        'rush',
      ),
      _ticket(
        'BB2302',
        'pending',
        now.subtract(const Duration(minutes: 4)),
        'normal',
      ),
      _ticket(
        'CC3403',
        'preparing',
        now.subtract(const Duration(minutes: 8)),
        'normal',
      ),
      _ticket(
        'DD4504',
        'ready',
        now.subtract(const Duration(minutes: 6)),
        'normal',
      ),
      _ticket(
        'EE5605',
        'completed',
        now.subtract(const Duration(minutes: 12)),
        'normal',
      ),
    ];
  }

  KitchenTicketModel _ticket(
    String id,
    String status,
    DateTime createdAt,
    String priority,
  ) {
    return KitchenTicketModel(
      id: id,
      orderId: 'order-$id',
      station: 'kitchen',
      status: status,
      priority: priority,
      createdAt: createdAt,
      items: [
        KitchenTicketItemModel(
          id: 'item-$id-1',
          orderItemId: 'order-item-$id-1',
          name: 'Nasi Goreng Kampung',
          qty: 2,
          notes: id == 'AA1201' ? 'Tanpa pedas, telur terpisah' : null,
          status: status,
        ),
        KitchenTicketItemModel(
          id: 'item-$id-2',
          orderItemId: 'order-item-$id-2',
          name: 'Chicken Katsu',
          qty: 1,
          status: status,
        ),
      ],
    );
  }
}

class _PreviewInventoryNotifier extends InventoryNotifier {
  @override
  Future<InventoryState> build() async => InventoryState(
    items: List.generate(
      10,
      (index) => InventoryItemModel(
        id: index + 1,
        name: [
          'Biji Kopi House Blend',
          'Susu Segar',
          'Gula Aren',
          'Matcha Powder',
          'Sirup Caramel',
          'Tepung Terigu',
          'Butter',
          'Dada Ayam',
          'Beras Premium',
          'Minyak Goreng',
        ][index],
        sku: 'INV-${(index + 1).toString().padLeft(3, '0')}',
        itemType: 'raw_material',
        unit: index < 5 ? 'gr' : 'kg',
        weightedAverageCost: 18000 + (index * 3200),
        minimumStock: 10,
        currentStock: index < 3 ? 6 + index.toDouble() : 24 + index.toDouble(),
      ),
    ),
    movements: const [],
  );
}

class _PreviewReportsNotifier extends ReportsNotifier {
  @override
  ReportsState build() {
    final now = DateTime.now();
    return ReportsState(
      startDate: now.subtract(const Duration(days: 6)),
      endDate: now,
      isLoading: false,
      salesReport: List.generate(
        7,
        (index) => SalesReportModel(
          date: now.subtract(Duration(days: 6 - index)).toIso8601String(),
          orders: 34 + index * 4,
          totalSales: 3200000 + index * 480000,
          cogs: 1250000 + index * 170000,
          grossProfit: 1950000 + index * 310000,
        ),
      ),
      margins: List.generate(
        7,
        (index) => ProductMarginModel(
          productId: '${index + 1}',
          name: [
            'Kopi Susu Tjoerah',
            'Cappuccino',
            'Matcha Latte',
            'Americano',
            'Nasi Goreng Kampung',
            'Croissant Butter',
            'Chicken Katsu',
          ][index],
          qty: 82 - index * 7,
          revenue: 3200000 - index * 180000,
          cogs: 1100000 + index * 90000,
          marginPercent: 66 - index * 3,
        ),
      ),
      alerts: [
        SystemAlertModel(
          id: 1,
          title: 'Stok susu menipis',
          message: 'Sisa stok diperkirakan untuk 1 hari operasional.',
          severity: 'warning',
          createdAt: now,
        ),
      ],
    );
  }
}

class _PreviewTableNotifier extends TableNotifier {
  @override
  Future<TableState> build() async => TableState(
    selectedFloorId: '1',
    floors: [
      FloorModel(id: '1', name: 'Lantai 1', sortOrder: 1),
      FloorModel(id: '2', name: 'Teras', sortOrder: 2),
    ],
    tables: List.generate(
      12,
      (index) => DiningTableModel(
        id: '${index + 1}',
        floorId: '1',
        name: 'Meja ${(index + 1).toString().padLeft(2, '0')}',
        capacity: index % 3 == 0 ? 4 : 2,
        status: index == 2
            ? 'cleaning'
            : index % 4 == 0
            ? 'occupied'
            : 'available',
        positionX: 0,
        positionY: 0,
      ),
    ),
  );
}

class _PreviewRecipeNotifier extends RecipeNotifier {
  @override
  Future<List<RecipeModel>> build() async => [
    _recipe('1', 'Kopi Susu Tjoerah', 11200),
    _recipe('2', 'Cappuccino', 12800),
    _recipe('3', 'Matcha Latte', 14500),
    _recipe('4', 'Caramel Latte', 15100),
  ];

  RecipeModel _recipe(String id, String name, double cost) {
    return RecipeModel(
      id: id,
      name: name,
      currentCost: cost,
      yieldQuantity: 1,
      yieldUnit: 'porsi',
      items: [
        RecipeItemModel(
          id: '$id-1',
          recipeId: id,
          inventoryItemId: '1',
          inventoryItemName: 'Biji Kopi House Blend',
          quantity: 18,
          unit: 'gr',
          wastePercent: 2,
          unitCost: 320,
          totalCost: 5760,
        ),
        RecipeItemModel(
          id: '$id-2',
          recipeId: id,
          inventoryItemId: '2',
          inventoryItemName: 'Susu Segar',
          quantity: 150,
          unit: 'ml',
          wastePercent: 1,
          unitCost: 26,
          totalCost: 3900,
        ),
      ],
    );
  }
}

class _PreviewAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {
      'name': 'Raka Pratama',
      'role': 'Outlet Manager',
      'outlet_name': 'Tjoerah Coffee - Renon',
    },
  );
}

class _PreviewSyncNotifier extends SyncNotifier {
  @override
  SyncState build() => SyncState(pendingCount: 3);
}

class _PreviewPrinterNotifier extends PrinterNotifier {
  @override
  PrinterState build() => PrinterState();
}

class _PreviewThemeNotifier extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.light;
}

class _PreviewOrderHistoryNotifier extends OrderHistoryNotifier {
  @override
  Future<List<OrderHistoryItem>> build() async => [
    OrderHistoryItem(
      id: 'order-1',
      receiptNumber: 'TJ-260715-090001',
      orderType: 'dine_in',
      paymentMethod: 'cash',
      total: 98000,
      createdAt: DateTime.now(),
      syncStatus: 'synced',
      customerName: 'Ayu Lestari',
      tableId: '7',
      paymentBreakdown: const {'cash': 98000},
      items: const [
        OrderHistoryLine(
          name: 'Kopi Susu Tjoerah',
          quantity: 2,
          price: 28000,
          total: 56000,
        ),
        OrderHistoryLine(
          name: 'Croissant Butter',
          quantity: 1,
          price: 42000,
          total: 42000,
        ),
      ],
    ),
  ];
}

class _PreviewCustomerNotifier extends CustomerNotifier {
  @override
  Future<List<CustomerModel>> build() async => [
    CustomerModel(
      id: '1',
      name: 'Ayu Lestari',
      phone: '081234567890',
      email: 'ayu@example.com',
      totalSpent: 1250000,
      visitCount: 12,
      lastPurchaseAt: DateTime.now(),
      isSynced: true,
    ),
    const CustomerModel(
      id: '2',
      name: 'Bima Putra',
      phone: '081298765432',
      totalSpent: 280000,
      visitCount: 3,
      isSynced: false,
    ),
  ];
}

class _PreviewOutletNotifier extends OutletNotifier {
  @override
  Future<List<OutletSummaryModel>> build() async => const [
    OutletSummaryModel(
      id: '1',
      name: 'Tjoerah Coffee - Renon',
      address: 'Jl. Tukad Yeh Aya, Denpasar',
      isActive: true,
      orders: 184,
      revenue: 9800000,
      cogs: 3300000,
      grossProfit: 6500000,
    ),
    OutletSummaryModel(
      id: '2',
      name: 'Tjoerah Coffee - Sanur',
      address: 'Jl. Danau Tamblingan, Denpasar',
      isActive: true,
      orders: 142,
      revenue: 7400000,
      cogs: 3500000,
      grossProfit: 3900000,
    ),
  ];
}

class _PreviewOwnerAuthNotifier extends AuthNotifier {
  @override
  AuthState build() => AuthState(
    isAuthenticated: true,
    user: {
      'name': 'Owner Admin',
      'role': 'owner',
      'outlets': [
        {'name': 'Tjoerah Coffee - Renon'},
      ],
    },
  );
}
