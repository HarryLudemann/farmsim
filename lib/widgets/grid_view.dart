import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/game_store.dart';
import '../models/game_models.dart';
import 'building_info_sheet.dart';
import 'silo_detail_sheet.dart';
import 'tile_view.dart';

class FarmGridView extends StatefulWidget {
  const FarmGridView({super.key});

  @override
  State<FarmGridView> createState() => _FarmGridViewState();
}

class _FarmGridViewState extends State<FarmGridView>
    with SingleTickerProviderStateMixin {
  // Shared idle-animation clock for crop sway / water shimmer / solar sweep
  // (§12) — one controller driving every tile keeps them all in sync.
  late final AnimationController _clock;
  final Map<String, Color> _flashes = {};

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  void _flash(int row, int col, Color color) {
    final key = '$row,$col';
    setState(() => _flashes[key] = color);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _flashes.remove(key));
    });
  }

  void _handleTap(BuildContext context, GameStore store, int row, int col) {
    if (store.placementSelection != null) {
      final result = store.attemptPlacement(row, col);
      switch (result) {
        case PlacementResult.placed:
        case PlacementResult.removed:
          _flash(row, col, Colors.green);
        case PlacementResult.invalidTile:
          _flash(row, col, Colors.red);
        case PlacementResult.insufficientFunds:
          _flash(row, col, Colors.red);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not enough coins'),
              duration: Duration(seconds: 1),
            ),
          );
      }
      return;
    }

    final tile = store.state.tiles[row][col];
    if (tile.building?.type == BuildingType.silo &&
        store.state.carriedCrop == null) {
      // §19 Silo detail sheet — an empty-handed tap checks status/sells,
      // rather than the old instant-sell-on-tap. Depositing (tap while
      // carrying) still falls through to `store.tapTile` below, unsheeted,
      // per §15's no-friction by-hand rule.
      showSiloDetailSheet(context, store, row, col);
      return;
    }
    if (tile.building != null && tile.building!.type != BuildingType.silo) {
      showBuildingInfoSheet(context, store, row, col);
      return;
    }
    store.tapTile(row, col);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();
    final tiles = store.state.tiles;
    const spacing = 4.0;
    final cols = tiles.isEmpty ? 1 : tiles[0].length;

    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // §14: keep touch targets at Apple's ~44x44pt minimum, and size
            // by whichever dimension is tighter so the grid never overflows
            // (matters on short/wide viewports, e.g. iPhone landscape).
            final byWidth =
                (constraints.maxWidth - spacing * (cols - 1)) / cols;
            final rowCount = tiles.length;
            final byHeight = constraints.maxHeight.isFinite
                ? (constraints.maxHeight - spacing * (rowCount - 1)) / rowCount
                : byWidth;
            final tileSize = (byWidth < byHeight ? byWidth : byHeight).clamp(
              44.0,
              100.0,
            );

            // Native Row/Column `spacing` only inserts gaps *between*
            // children (not after the last one), matching the byWidth/
            // byHeight math above exactly — manual per-item padding was
            // adding one extra gap and overflowing by `spacing` pixels.
            return Column(
              mainAxisSize: MainAxisSize.min,
              spacing: spacing,
              children: [
                for (var row = 0; row < tiles.length; row++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: spacing,
                    children: [
                      for (var col = 0; col < tiles[row].length; col++)
                        GestureDetector(
                          onTap: () => _handleTap(context, store, row, col),
                          child: SizedBox(
                            width: tileSize,
                            height: tileSize,
                            child: TileView(
                              tile: tiles[row][col],
                              row: row,
                              col: col,
                              clockPhase: _clock.value,
                              flashColor: _flashes['$row,$col'],
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
