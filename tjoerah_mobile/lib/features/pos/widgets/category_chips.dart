import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/catalog_provider.dart';

class CategoryChips extends ConsumerWidget {
  const CategoryChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogState = ref.watch(catalogProvider);
    return catalogState.when(
      loading: () => const SizedBox(
        height: 42,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
      data: (catalog) {
        return SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: catalog.categories.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final isAll = index == 0;
              final category = isAll ? null : catalog.categories[index - 1];
              final selected = isAll
                  ? catalog.selectedCategoryId == null
                  : catalog.selectedCategoryId == category!.id;

              return ChoiceChip(
                label: Text(isAll ? 'Semua' : category!.name),
                selected: selected,
                showCheckmark: false,
                onSelected: (_) => ref
                    .read(catalogProvider.notifier)
                    .selectCategory(category?.id),
              );
            },
          ),
        );
      },
    );
  }
}
