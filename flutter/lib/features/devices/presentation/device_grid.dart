import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/devices_repository.dart';
import 'device_card.dart';

class DeviceGrid extends ConsumerWidget {
  const DeviceGrid({super.key, required this.directoryId});

  final String directoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider(directoryId));
    return devices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('No devices in this directory'));
        }
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            mainAxisExtent: 140,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final device = list[i];
            return DeviceCard(
              device: device,
              onTap: () => context.push(
                '/connecting?deviceId=${device.id}&hostname=${Uri.encodeComponent(device.hostname)}',
              ),
            );
          },
        );
      },
    );
  }
}
