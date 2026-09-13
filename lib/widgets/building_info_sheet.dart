import 'package:flutter/material.dart';

import '../engine/game_store.dart';
import '../models/game_models.dart';

/// §19 "Building info" sheet — type, connection status, and Move/Demolish
/// actions (§20). Not used for the Silo, which keeps its fast direct-tap
/// deposit/sell interaction from §15.
void showBuildingInfoSheet(
  BuildContext context,
  GameStore store,
  int row,
  int col,
) {
  final tile = store.state.tiles[row][col];
  final building = tile.building;
  if (building == null) return;

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      final label = building.type == BuildingType.sprinkler
          ? (building.tier >= 2 ? 'Sprinkler (Wide)' : 'Sprinkler')
          : kBuildingLabel[building.type] ?? building.type.name;
      final statusLine = switch (building.type) {
        BuildingType.solarPanel =>
          'Producing ${GameStore.solarOutput} Power/tick (ambient sun).',
        BuildingType.pump => tile.isPowered
            ? 'Powered — pumping ${GameStore.pumpWaterOutput} Water/tick.'
                  '${tile.wireTier >= 2 ? ' Sitting on Heavy Wire: draw cut 25%.' : ''}'
            : 'Not powered — connect a Wire chain back to a Solar Panel with enough output.',
        BuildingType.sprinkler => tile.isWatered
            ? 'Watered — irrigating its ${building.tier >= 2 ? '5x5' : '3x3'} coverage this tick.'
                  '${tile.pipeTier >= 2 ? ' Sitting on Heavy Pipe: draw cut 25%.' : ''}'
            : 'Not watered — connect a Pipe chain back to a powered Pump.',
        BuildingType.silo => '',
      };

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                statusLine,
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        store.moveBuilding(row, col);
                        Navigator.pop(sheetContext);
                      },
                      child: const Text('Move'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () {
                        store.demolishBuilding(row, col);
                        Navigator.pop(sheetContext);
                      },
                      child: const Text('Demolish (50% refund)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
