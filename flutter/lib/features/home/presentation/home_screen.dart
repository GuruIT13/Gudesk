import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../core/api/api_client.dart';
import '../../auth/presentation/login_screen.dart';
import '../../directories/data/directories_repository.dart';
import '../../directories/presentation/directory_tree.dart';
import '../../devices/presentation/device_grid.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await secureStorage.deleteJwt();
    apiClient.setJwt(null);
    ref.read(jwtProvider.notifier).state = null;
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDirId = ref.watch(selectedDirectoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GuDesk'),
        actions: [
          TextButton.icon(
            onPressed: () => _logout(context, ref),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Logout'),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Directories',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const Expanded(child: DirectoryTree()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selectedDirId == null
                ? const Center(child: Text('Select a directory to view devices'))
                : DeviceGrid(directoryId: selectedDirId),
          ),
        ],
      ),
    );
  }
}
