import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/game_models.dart';

/// Flat, native-shape rendering per §12 — no image assets. Depth comes from
/// soft shadows and a shared idle-animation clock (crop sway, water
/// shimmer, a highlight sweep on the Solar Panel), not from 3D.
class TileView extends StatelessWidget {
  final Tile tile;
  final int row;
  final int col;

  /// 0..1, looping — a shared clock so every tile's idle animation stays in
  /// sync but slightly desynced per-tile via [_seed].
  final double clockPhase;

  /// Non-null briefly after a placement attempt: green for success, red for
  /// invalid (§20).
  final Color? flashColor;

  const TileView({
    super.key,
    required this.tile,
    required this.row,
    required this.col,
    required this.clockPhase,
    this.flashColor,
  });

  double get _seed => ((row * 7 + col * 13) % 10) / 10.0;
  double get _phase => (clockPhase + _seed) % 1.0;

  Color get _terrainColor => switch (tile.terrain) {
    Terrain.openGround => const Color.fromRGBO(191, 217, 166, 1),
    Terrain.farmland => const Color.fromRGBO(184, 143, 102, 1),
    Terrain.lake => const Color.fromRGBO(140, 191, 230, 1),
    Terrain.rockyOutcrop => const Color.fromRGBO(179, 173, 166, 1),
    Terrain.elevatedGround => const Color.fromRGBO(204, 209, 153, 1),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _terrainColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (tile.terrain == Terrain.lake) _lakeShimmer(),
          if (tile.building != null) _buildingView(tile.building!),
          if (tile.cropState != null) _cropView(tile.cropState!),
          if (tile.wireTier > 0)
            _cornerBadge(
              Alignment.topLeft,
              Icons.bolt,
              tile.isPowered,
              Colors.amber,
              tile.wireTier,
            ),
          if (tile.pipeTier > 0)
            _cornerBadge(
              Alignment.bottomRight,
              Icons.water_drop,
              tile.isWatered,
              Colors.blue,
              tile.pipeTier,
            ),
          if (flashColor != null)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: flashColor!.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cornerBadge(
    Alignment alignment,
    IconData icon,
    bool active,
    Color activeColor,
    int tier,
  ) {
    final isHeavy = tier >= 2;
    final child = Icon(
      icon,
      size: isHeavy ? 13 : 11,
      color: active ? activeColor : Colors.black.withValues(alpha: 0.25),
    );
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(2),
        // Tier 2 ("Heavy") gets a small amber chip behind it so its extra
        // capacity reads at a glance, even when not currently active.
        child: isHeavy
            ? Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                ),
                child: child,
              )
            : child,
      ),
    );
  }

  Widget _lakeShimmer() {
    final x = -1.4 + 2.8 * _phase;
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.35,
          child: Align(
            alignment: Alignment(x, 0),
            child: Container(
              width: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0),
                    Colors.white,
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildingView(Building building) {
    switch (building.type) {
      case BuildingType.silo:
        return _siloView(building);
      case BuildingType.solarPanel:
        return _solarPanelView();
      case BuildingType.pump:
        return _pumpView();
      case BuildingType.sprinkler:
        return _sprinklerView(building.tier);
    }
  }

  Widget _siloView(Building building) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipPath(
          clipper: _TriangleClipper(),
          child: Container(
            width: 20,
            height: 8,
            color: const Color.fromRGBO(140, 77, 51, 1),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(204, 191, 153, 1),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            '${building.siloContents}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.brown,
            ),
          ),
        ),
      ],
    );
  }

  Widget _solarPanelView() {
    final sweep = -1.3 + 2.6 * _phase;
    return Container(
      width: 26,
      height: 26,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color.fromRGBO(40, 48, 66, 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment(sweep, 0),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 8,
                height: 40,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pumpView() {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color.fromRGBO(120, 134, 150, 1),
        border: tile.isPowered
            ? Border.all(color: Colors.amber, width: 2)
            : null,
      ),
      child: CustomPaint(painter: _PumpSpoutPainter()),
    );
  }

  Widget _sprinklerView(int tier) {
    final size = tier >= 2 ? 27.0 : 22.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color.fromRGBO(90, 130, 100, 1),
        border: tile.isWatered
            ? Border.all(color: Colors.blue, width: 2)
            : null,
      ),
      child: Icon(
        tier >= 2 ? Icons.grain : Icons.water,
        size: tier >= 2 ? 15 : 12,
        color: Colors.white70,
      ),
    );
  }

  Widget _cropView(CropState crop) {
    final progress = (crop.ticksGrown / CropState.ticksToReady).clamp(0.0, 1.0);
    final size = 10 + 18 * progress;
    final swayAngle = math.sin(_phase * 2 * math.pi) * 0.12;
    return Transform.rotate(
      angle: swayAngle,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: crop.isReady
              ? const Color.fromRGBO(242, 204, 51, 1)
              : const Color.fromRGBO(102, 166, 77, 1),
          boxShadow: crop.isReady
              ? [
                  BoxShadow(
                    color: Colors.yellow.withValues(alpha: 0.7),
                    blurRadius: 6,
                  ),
                ]
              : null,
          border: crop.isWateredThisTick
              ? Border.all(color: Colors.blue.withValues(alpha: 0.6), width: 2)
              : null,
        ),
      ),
    );
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _PumpSpoutPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color.fromRGBO(70, 82, 96, 1);
    final path = Path()
      ..moveTo(size.width * 0.55, size.height * 0.3)
      ..lineTo(size.width * 0.95, size.height * 0.15)
      ..lineTo(size.width * 0.95, size.height * 0.4)
      ..lineTo(size.width * 0.6, size.height * 0.5)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
