import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/game_store.dart';

/// Shown only while a Shop item is selected — §20's "small X near the
/// Status Bar" to cancel Placement Mode, plus a reminder of what's active
/// since there's no longer a highlighted Tray icon doing that job.
class PlacementBanner extends StatelessWidget {
  const PlacementBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final type = store.placementSelection;
    if (type == null) return const SizedBox.shrink();
    final info = kPlacementInfo[type]!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.touch_app, size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Placing ${info.label} (${info.cost}c) — tap a tile',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: store.cancelPlacement,
            child: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
