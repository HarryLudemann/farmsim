import 'package:flutter/material.dart';

import '../engine/game_store.dart';
import '../models/game_models.dart';

const Map<ShopCategory, String> _categoryLabel = {
  ShopCategory.infrastructure: 'Infrastructure',
  ShopCategory.producers: 'Producers',
  ShopCategory.automation: 'Automation',
};

const Map<PlacementType, IconData> _icons = {
  PlacementType.wireBasic: Icons.bolt,
  PlacementType.wireHeavy: Icons.electric_bolt,
  PlacementType.pipeBasic: Icons.water_drop,
  PlacementType.pipeHeavy: Icons.water,
  PlacementType.solarPanel: Icons.wb_sunny,
  PlacementType.pump: Icons.plumbing,
  PlacementType.sprinklerBasic: Icons.shower,
  PlacementType.sprinklerWide: Icons.grain,
};

/// The Shop (§19) — a full menu of everything placeable, grouped by
/// category, replacing a bottom tray so every item (and every tier) is
/// visible at once rather than scrolled past.
void showShopSheet(BuildContext context, GameStore store) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Text(
                        'Shop',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final category in ShopCategory.values)
                        _ShopSectionView(
                          title: _categoryLabel[category]!,
                          entries: kPlacementInfo.entries
                              .where((e) => e.value.category == category)
                              .toList(),
                          store: store,
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _ShopSectionView extends StatelessWidget {
  final String title;
  final List<MapEntry<PlacementType, PlacementInfo>> entries;
  final GameStore store;

  const _ShopSectionView({
    required this.title,
    required this.entries,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final entry in entries)
          _ShopItemTile(type: entry.key, info: entry.value, store: store),
      ],
    );
  }
}

class _ShopItemTile extends StatelessWidget {
  final PlacementType type;
  final PlacementInfo info;
  final GameStore store;

  const _ShopItemTile({
    required this.type,
    required this.info,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final affordable = store.state.coins >= info.cost;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: const Color.fromRGBO(245, 247, 237, 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          store.selectPlacement(type);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: info.tier >= 2
                      ? Colors.amber.withValues(alpha: 0.25)
                      : Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(_icons[type], size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          info.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (info.tier >= 2) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'TIER 2',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${info.cost}c',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: affordable ? Colors.brown : Colors.red.shade300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
