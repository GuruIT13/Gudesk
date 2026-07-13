class Directory {
  const Directory({
    required this.id,
    required this.name,
    this.parentId,
    this.children = const [],
  });

  final String id;
  final String name;
  final String? parentId;
  final List<Directory> children;

  factory Directory.fromJson(Map<String, dynamic> json) => Directory(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parent_id'] as String?,
        children: (json['children'] as List<dynamic>? ?? [])
            .map((c) => Directory.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}
