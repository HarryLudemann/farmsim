import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/game_store.dart';
import 'farm_view.dart';

/// §1/§27 — "always-online... no offline mode." Blocks on sign-in + the
/// initial Firestore fetch before showing the Farm at all, with a friendly
/// "waiting for a connection" state and a retry button rather than
/// rendering stale or empty data.
class ConnectionGate extends StatelessWidget {
  const ConnectionGate({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();

    if (store.loadError != null) {
      return _Message(
        icon: Icons.cloud_off,
        title: 'Couldn\'t connect',
        body: store.loadError!,
        action: FilledButton(
          onPressed: store.retryLoad,
          child: const Text('Retry'),
        ),
      );
    }

    if (!store.isReady) {
      return const _Message(
        icon: null,
        title: 'Waiting for a connection…',
        body: 'Farm Sim needs a network connection to load your farm.',
        action: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    return const FarmView();
  }
}

class _Message extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String body;
  final Widget action;

  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(245, 247, 237, 1),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 40, color: Colors.black45),
                const SizedBox(height: 16),
              ],
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
