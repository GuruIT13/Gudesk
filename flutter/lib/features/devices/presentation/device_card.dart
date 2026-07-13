import 'package:flutter/material.dart';
import '../domain/device.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.device, required this.onTap});

  final Device device;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final canConnect = device.status == DeviceStatus.online;
    final statusColor = switch (device.status) {
      DeviceStatus.online => Colors.green,
      DeviceStatus.busy => Colors.orange,
      DeviceStatus.offline => Colors.grey,
    };
    final statusLabel = switch (device.status) {
      DeviceStatus.online => 'online',
      DeviceStatus.busy => 'busy',
      DeviceStatus.offline => 'offline',
    };

    return Card(
      child: InkWell(
        onTap: canConnect ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.computer,
                size: 36,
                color: canConnect ? Theme.of(context).colorScheme.primary : Colors.grey,
              ),
              const SizedBox(height: 8),
              Text(
                device.hostname,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(statusLabel, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
