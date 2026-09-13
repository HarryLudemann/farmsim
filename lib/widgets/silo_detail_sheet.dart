import 'package:flutter/material.dart';

import '../engine/game_store.dart';
import '../models/game_models.dart';

/// §19 "Silo detail" sheet — fill level, contents, Sell button. Deposit
/// (tapping while carrying a crop) stays an instant by-hand action per
/// §15; this sheet is what an empty-handed tap on the Silo opens instead.
void showSiloDetailSheet(BuildContext context, GameStore store, int row, int col) {
  final tile = store.state.tiles[row][col];
  final building = tile.building;
  if (building == null || building.type != BuildingType.silo) return;

  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final contents = building.siloContents;
          final cropName = building.siloCropType?.name ?? 'empty';
          final fraction = contents / GameStore.siloCapacity;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Silo', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    building.siloCropType == null
                        ? 'Empty — deposit a matching crop to claim it.'
                        : '$contents / ${GameStore.siloCapacity} $cropName',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: fraction.clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: Colors.black12,
                      color: fraction >= 1.0 ? Colors.amber : Colors.green,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: contents > 0
                          ? () {
                              store.sellSilo(row, col);
                              Navigator.pop(context);
                            }
                          : null,
                      child: Text(
                        contents > 0
                            ? 'Sell all ($contents x ${GameStore.sellPricePerCrop}c = ${contents * GameStore.sellPricePerCrop}c)'
                            : 'Nothing to sell yet',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
