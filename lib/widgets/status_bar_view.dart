import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/game_store.dart';
import '../models/game_models.dart';
import 'building_info_sheet.dart';
import 'shop_sheet.dart';
import 'silo_detail_sheet.dart';

class StatusBarView extends StatelessWidget {
  const StatusBarView({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final state = store.state;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, color: Colors.amber, size: 16),
          const SizedBox(width: 4),
          Text(
            '${state.coins}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 14),
          Row(
            children: List.generate(
              GameStore.wateringCanMaxCharges,
              (i) => Icon(
                Icons.water_drop,
                size: 16,
                color: i < state.wateringCanCharges
                    ? Colors.blue
                    : Colors.grey.withValues(alpha: 0.3),
              ),
            ),
          ),
          if (state.carriedCrop != null) ...[
            const SizedBox(width: 12),
            const Icon(Icons.pan_tool, size: 15, color: Colors.brown),
          ],
          const Spacer(),
          // §23 — passive, non-blocking badges: tapping jumps to the
          // relevant sheet. Only shown when there's something to say.
          if (store.firstFullSiloTile case (final row, final col))
            IconButton(
              onPressed: () => showSiloDetailSheet(context, store, row, col),
              icon: const Icon(Icons.inventory_2, color: Colors.amber),
              tooltip: 'A Silo is full',
              visualDensity: VisualDensity.compact,
            ),
          if (store.firstDeficitTile case (final row, final col))
            IconButton(
              onPressed: () => showBuildingInfoSheet(context, store, row, col),
              icon: const Icon(Icons.warning_amber, color: Colors.redAccent),
              tooltip: 'A network is in deficit',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: () => showShopSheet(context, store),
            icon: const Icon(Icons.storefront),
            tooltip: 'Shop',
            visualDensity: VisualDensity.compact,
          ),
          if (state.mode == GameMode.manual)
            IconButton(
              onPressed: store.step,
              icon: const Icon(Icons.skip_next),
              tooltip: 'Step one tick',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: () => store.setMode(
              state.mode == GameMode.live ? GameMode.manual : GameMode.live,
            ),
            icon: Icon(
              state.mode == GameMode.live
                  ? Icons.play_circle_fill
                  : Icons.pause_circle_filled,
              color: state.mode == GameMode.live ? Colors.green : Colors.grey[700],
            ),
            tooltip: state.mode == GameMode.live
                ? 'Live — tap for Manual'
                : 'Manual — tap for Live',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
