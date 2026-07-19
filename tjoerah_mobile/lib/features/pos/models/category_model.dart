class CategoryModel {
  final String id;
  final String name;
  final String? parentId;
  final int sortOrder;
  final bool isActive;

  const CategoryModel({
    required this.id,
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      parentId: _nullableString(json['parent_id']),
      sortOrder: _asInt(json['sort_order']),
      isActive: _asBool(json['is_active'], fallback: true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'parent_id': parentId,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }
}

class CategoryDraft {
  const CategoryDraft({
    required this.name,
    this.parentId,
    this.sortOrder = 0,
    this.isActive = true,
  });

  factory CategoryDraft.fromCategory(CategoryModel category) {
    return CategoryDraft(
      name: category.name,
      parentId: category.parentId,
      sortOrder: category.sortOrder,
      isActive: category.isActive,
    );
  }

  final String name;
  final String? parentId;
  final int sortOrder;
  final bool isActive;

  CategoryDraft copyWith({bool? isActive}) {
    return CategoryDraft(
      name: name,
      parentId: parentId,
      sortOrder: sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'parent_id': parentId,
      'sort_order': sortOrder,
      'is_active': isActive,
    };
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _asInt(dynamic value) {
  return value is int ? value : int.tryParse('$value') ?? 0;
}

bool _asBool(dynamic value, {required bool fallback}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value == '1' || value.toLowerCase() == 'true') return true;
    if (value == '0' || value.toLowerCase() == 'false') return false;
  }
  return fallback;
}
