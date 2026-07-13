import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/directories_repository.dart';
import '../domain/directory.dart';

class DirectoryTree extends ConsumerWidget {
  const DirectoryTree({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirs = ref.watch(directoriesProvider);
    return dirs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (roots) => ListView(
        children: roots.map((d) => _DirectoryTile(dir: d)).toList(),
      ),
    );
  }
}

class _DirectoryTile extends ConsumerWidget {
  const _DirectoryTile({required this.dir});

  final Directory dir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedDirectoryProvider);
    final isSelected = selected == dir.id;

    if (dir.children.isEmpty) {
      return ListTile(
        dense: true,
        selected: isSelected,
        leading: const Icon(Icons.folder, size: 18),
        title: Text(dir.name),
        onTap: () => ref.read(selectedDirectoryProvider.notifier).state = dir.id,
      );
    }

    return ExpansionTile(
      dense: true,
      leading: const Icon(Icons.folder_open, size: 18),
      title: Text(dir.name),
      initiallyExpanded: true,
      onTap: () => ref.read(selectedDirectoryProvider.notifier).state = dir.id,
      children: dir.children.map((c) => _DirectoryTile(dir: c)).toList(),
    );
  }
}
