import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/catalog_provider.dart';

class CategoryChips extends StatelessWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final categories = catalog.categories;
    final selectedId = catalog.selectedCategoryId;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1, // +1 for 'All'
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final isSelected = isAll ? selectedId == null : categories[index - 1].id == selectedId;
          final label = isAll ? 'All' : categories[index - 1].name;

          return ChoiceChip(
            label: Text(label),
            selected: isSelected,
            onSelected: (selected) {
              catalog.selectCategory(isAll ? null : categories[index - 1].id);
            },
            selectedColor: AppColors.primary,
            labelStyle: TextStyle(
              color: isSelected ? AppColors.textInverse : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
            ),
          );
        },
      ),
    );
  }
}
