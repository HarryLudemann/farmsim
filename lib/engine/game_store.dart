import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/game_models.dart';

enum PlacementResult { placed, removed, insufficientFunds, invalidTile }

/// §19's "While you were away" summary sheet content, computed once by
/// `GameStore._runCatchUp` right after a fresh load (§22).
class AwaySummary {
  final Duration elapsed;
  final int ticksSimulated;
  final int newlyReadyCrops;

  const AwaySummary({
    required this.elapsed,
    required this.ticksSimulated,
    required this.newlyReadyCrops,
  });
}

/// Static info for one Shop entry. Costs aren't specified in the design
/// doc, so these are invented but chosen to keep the "sell a few crops
/// before you can automate" pacing the doc's progression section implies.
///
/// Tier-2 ("Heavy") Wire/Pipe are a deliberate extension beyond the doc:
/// §17's Efficiency branch describes "cheaper-to-run Pumps... longer-range
/// Solar Panels" as Tech-Tree unlocks. Since the Tech Tree isn't built yet,
/// this brings that idea in early as a direct purchase: a Heavy tile boosts
/// whatever Producer feeds through it by 50%, and cuts the draw of whatever
/// Consumer sits on it by 25% — see `GameStore._tierMultiplier`.
class PlacementInfo {
  final int cost;
  final String label;
  final String description;
  final PlacementKind kind;
  final ShopCategory category;
  final BuildingType? buildingType;
  final int tier;

  const PlacementInfo({
    required this.cost,
    required this.label,
    required this.description,
    required this.kind,
    required this.category,
    this.buildingType,
    this.tier = 1,
  });
}

const Map<PlacementType, PlacementInfo> kPlacementInfo = {
  PlacementType.wireBasic: PlacementInfo(
    cost: 2,
    label: 'Wire',
    description: 'Carries Power, tile to tile.',
    kind: PlacementKind.wire,
    category: ShopCategory.infrastructure,
    tier: 1,
  ),
  PlacementType.wireHeavy: PlacementInfo(
    cost: 8,
    label: 'Heavy Wire',
    description:
        'Boosts a Solar Panel feeding through it by 50%. Cuts the power '
        'draw of a Pump sitting on it by 25%.',
    kind: PlacementKind.wire,
    category: ShopCategory.infrastructure,
    tier: 2,
  ),
  PlacementType.pipeBasic: PlacementInfo(
    cost: 2,
    label: 'Pipe',
    description: 'Carries Water, tile to tile.',
    kind: PlacementKind.pipe,
    category: ShopCategory.infrastructure,
    tier: 1,
  ),
  PlacementType.pipeHeavy: PlacementInfo(
    cost: 8,
    label: 'Heavy Pipe',
    description:
        'Boosts a Pump feeding through it by 50%. Cuts the water draw of a '
        'Sprinkler sitting on it by 25%.',
    kind: PlacementKind.pipe,
    category: ShopCategory.infrastructure,
    tier: 2,
  ),
  PlacementType.solarPanel: PlacementInfo(
    cost: 40,
    label: 'Solar Panel',
    description:
        'Outputs ${GameStore.solarOutput} Power/tick to an adjacent Wire.',
    kind: PlacementKind.building,
    category: ShopCategory.producers,
    buildingType: BuildingType.solarPanel,
  ),
  PlacementType.pump: PlacementInfo(
    cost: 30,
    label: 'Pump',
    description:
        'Needs Power on its own tile, and a Lake next door. Outputs '
        '${GameStore.pumpWaterOutput} Water/tick to an adjacent Pipe.',
    kind: PlacementKind.building,
    category: ShopCategory.producers,
    buildingType: BuildingType.pump,
  ),
  PlacementType.sprinklerBasic: PlacementInfo(
    cost: 25,
    label: 'Sprinkler',
    description: 'Waters its surrounding 3x3 automatically, every tick.',
    kind: PlacementKind.building,
    category: ShopCategory.automation,
    buildingType: BuildingType.sprinkler,
    tier: 1,
  ),
  PlacementType.sprinklerWide: PlacementInfo(
    cost: 55,
    label: 'Sprinkler (Wide)',
    description:
        'Waters a full 5x5 automatically. Draws much more Water — pair it '
        'with a strong Pipe network.',
    kind: PlacementKind.building,
    category: ShopCategory.automation,
    buildingType: BuildingType.sprinkler,
    tier: 2,
  ),
};

const Map<BuildingType, String> kBuildingLabel = {
  BuildingType.silo: 'Silo',
  BuildingType.solarPanel: 'Solar Panel',
  BuildingType.pump: 'Pump',
  BuildingType.sprinkler: 'Sprinkler',
};

/// Milestone A+B engine: by-hand interaction (§15) plus the automated chain
/// (§4, §10, §18) — Solar Panel → Wire → Pump → Pipe → Sprinkler — and the
/// Live/Manual toggle (§13).
class GameStore extends ChangeNotifier {
  static const int wateringCanMaxCharges = 3;
  static const int sellPricePerCrop = 5; // §18
  static const Duration tickInterval = Duration(seconds: 4); // §18

  static const int solarOutput = 10; // §18
  static const int pumpPowerDraw = 4;
  static const int pumpWaterOutput = 8;
  static const int siloCapacity = 50; // §18
  static const Duration _catchUpCap = Duration(hours: 12); // §22
  static const Duration _periodicSyncInterval = Duration(seconds: 12); // §22

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  String? _uid;

  late GameState state;
  Timer? _timer;
  Timer? _syncTimer;

  /// UI-only selection state — deliberately not persisted (§20: placement
  /// mode shouldn't survive a relaunch).
  PlacementType? placementSelection;
  PlacementType? _freeMoveType;

  /// Set once, right after load, if enough real time passed to simulate
  /// missed ticks (§13, §22). The UI shows the "while you were away" sheet
  /// once and calls `clearAwaySummary()`.
  AwaySummary? pendingAwaySummary;

  /// §27's connectivity gate: false until sign-in + the initial Firestore
  /// fetch complete. `loadError` is set instead if that fails — the app
  /// requires a network connection at launch (§1, §27), there's no local
  /// fallback to render in the meantime.
  bool isReady = false;
  String? loadError;

  GameStore({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance {
    state = _freshGrid();
    _load();
  }

  int get rows => state.tiles.length;
  int get cols => state.tiles.isEmpty ? 0 : state.tiles[0].length;

  // MARK: - Status Bar badges (§23) — passive, non-blocking: a Silo at
  // capacity, or a Consumer that's wired/piped into a network but not
  // actually getting power/water this tick (a genuine deficit, not just
  // "not built yet"). Only the first of each is surfaced, since today
  // there's only ever one Silo — good enough until multiple exist.

  (int, int)? get firstFullSiloTile {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final b = state.tiles[r][c].building;
        if (b?.type == BuildingType.silo && b!.siloContents >= siloCapacity) {
          return (r, c);
        }
      }
    }
    return null;
  }

  (int, int)? get firstDeficitTile {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final tile = state.tiles[r][c];
        final b = tile.building;
        if (b?.type == BuildingType.pump && tile.wireTier > 0 && !tile.isPowered) {
          return (r, c);
        }
        if (b?.type == BuildingType.sprinkler && tile.pipeTier > 0 && !tile.isWatered) {
          return (r, c);
        }
      }
    }
    return null;
  }

  // MARK: - Starting layout (6x6, portrait iPhone only — §11 Milestone A)
  // The Lake is fixed terrain (§4) — no infrastructure or building can ever
  // be placed on it (see `_placeInfra`/`_placeBuilding`), so it never
  // changes after this.

  static GameState _freshGrid() {
    const rows = 6, cols = 6;
    final tiles = List.generate(
      rows,
      (_) => List.generate(cols, (_) => Tile(terrain: Terrain.openGround)),
    );
    tiles[1][1] = Tile(terrain: Terrain.lake);
    tiles[1][2] = Tile(terrain: Terrain.lake);
    for (var c = 0; c < 3; c++) {
      tiles[3][c] = Tile(terrain: Terrain.farmland);
    }
    tiles[3][3] = Tile(
      terrain: Terrain.openGround,
      building: Building(type: BuildingType.silo),
    );
    return GameState(tiles: tiles);
  }

  /// §22/§27: anonymous sign-in, then fetch `/users/{uid}/gameState/current`
  /// from Firestore. No local-only fallback — if this fails, `loadError` is
  /// set and the UI shows a retry screen rather than rendering stale/empty
  /// state, matching §1/§27's "no offline mode" requirement.
  Future<void> _load() async {
    try {
      final user = _auth.currentUser ?? (await _auth.signInAnonymously()).user;
      final uid = user!.uid;
      _uid = uid;

      final snapshot = await _gameDoc(uid).get();
      final data = snapshot.data();
      if (data != null) {
        try {
          state = _fromFirestoreDoc(data);
        } catch (_) {
          state = _freshGrid();
        }
      }

      _runCatchUp();
      _computeNetworksAndWatering(); // so glows are right before the first tick
      isReady = true;
      notifyListeners();
      if (state.mode == GameMode.live) _startTicking();
      _startPeriodicSync();
    } catch (e) {
      loadError = e.toString();
      notifyListeners();
    }
  }

  /// Retry button on the connection-error screen.
  void retryLoad() {
    loadError = null;
    notifyListeners();
    _load();
  }

  DocumentReference<Map<String, dynamic>> _gameDoc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('gameState')
      .doc('current');

  /// §13/§22 — Live Mode "catches up on elapsed time on reopen." Only
  /// meaningful for infrastructure already running (Sprinklers etc.): this
  /// is exactly what makes automation "pay off while you're away" real
  /// rather than just a slogan (§13's own framing). By-hand actions can't
  /// happen retroactively, so hand-watered crops correctly do NOT progress
  /// during catch-up — only what a Sprinkler would have kept doing.
  ///
  /// Capped at 12h (§22). Runs the core tick logic directly rather than via
  /// `_tick()` so it doesn't write to Firestore once per simulated tick —
  /// up to ~10,800 ticks at the cap, cheap computationally but wasteful to
  /// persist that often.
  void _runCatchUp() {
    if (state.mode != GameMode.live) return;
    final elapsed = DateTime.now().difference(state.lastSavedAt);
    if (elapsed <= tickInterval) return;
    final capped = elapsed > _catchUpCap ? _catchUpCap : elapsed;
    final ticks = capped.inMilliseconds ~/ tickInterval.inMilliseconds;
    if (ticks <= 0) return;

    var newlyReady = 0;
    for (var i = 0; i < ticks; i++) {
      _computeNetworksAndWatering();
      newlyReady += _growCrops();
    }
    pendingAwaySummary = AwaySummary(
      elapsed: elapsed,
      ticksSimulated: ticks,
      newlyReadyCrops: newlyReady,
    );
  }

  void clearAwaySummary() {
    pendingAwaySummary = null;
    notifyListeners();
  }

  // MARK: - Live / Manual mode (§13)

  void setMode(GameMode mode) {
    if (state.mode == mode) return;
    state.mode = mode;
    if (mode == GameMode.live) {
      _startTicking();
    } else {
      _timer?.cancel();
    }
    notifyListeners();
    _saveNow();
  }

  /// Manual mode's "Step" button — runs exactly one tick on demand.
  void step() {
    if (state.mode != GameMode.manual) return;
    _tick();
  }

  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => _tick());
  }

  // MARK: - By-hand interaction (§15)

  void tapTile(int row, int col) {
    final tile = state.tiles[row][col];

    switch (tile.terrain) {
      case Terrain.lake:
        state.wateringCanCharges = wateringCanMaxCharges;
      case Terrain.farmland:
        _handleFarmlandTap(tile);
      case Terrain.openGround:
      case Terrain.rockyOutcrop:
      case Terrain.elevatedGround:
        _handleSiloDeposit(tile);
    }

    notifyListeners();
    _saveNow();
  }

  void _handleFarmlandTap(Tile tile) {
    final crop = tile.cropState;
    if (crop != null) {
      if (crop.isReady) {
        if (state.carriedCrop == null) {
          state.carriedCrop = crop.cropType;
          tile.cropState = null;
        }
      } else if (state.wateringCanCharges > 0 && !crop.isWateredThisTick) {
        crop.isWateredThisTick = true;
        state.wateringCanCharges -= 1;
      }
    } else if (state.carriedCrop == null) {
      tile.cropState = CropState(cropType: CropType.wheat);
    }
  }

  /// §15's instant by-hand deposit (tap a Silo while carrying) — no sheet,
  /// no distance limit. Selling is a separate, deliberate action via the
  /// Silo detail sheet (§19), triggered from the view layer, not from a
  /// bare tap.
  void _handleSiloDeposit(Tile tile) {
    final building = tile.building;
    if (building == null || building.type != BuildingType.silo) return;
    final carried = state.carriedCrop;
    if (carried == null) return;

    building.siloCropType ??= carried;
    if (building.siloCropType != carried) return; // §4: mismatched crops can't enter
    if (building.siloContents >= siloCapacity) return; // §18: 50-unit cap

    building.siloContents += 1;
    state.carriedCrop = null;
  }

  /// §19 Silo detail sheet's Sell button.
  void sellSilo(int row, int col) {
    final building = state.tiles[row][col].building;
    if (building == null || building.type != BuildingType.silo) return;
    if (building.siloContents == 0) return;
    state.coins += building.siloContents * sellPricePerCrop;
    building.siloContents = 0;
    HapticFeedback.lightImpact();
    notifyListeners();
    _saveNow();
  }

  // MARK: - Placement (§19–20)

  void selectPlacement(PlacementType? type) {
    placementSelection = type;
    _freeMoveType = null;
    notifyListeners();
  }

  void cancelPlacement() {
    placementSelection = null;
    _freeMoveType = null;
    notifyListeners();
  }

  bool _inBounds(int r, int c) => r >= 0 && r < rows && c >= 0 && c < cols;

  PlacementResult attemptPlacement(int row, int col) {
    final type = placementSelection;
    if (type == null) return PlacementResult.invalidTile;
    final tile = state.tiles[row][col];
    final info = kPlacementInfo[type]!;
    final free = _freeMoveType == type;

    PlacementResult result;
    switch (info.kind) {
      case PlacementKind.wire:
        result = _placeInfra(
          tile,
          isWire: true,
          tier: info.tier,
          cost: info.cost,
          free: free,
        );
      case PlacementKind.pipe:
        result = _placeInfra(
          tile,
          isWire: false,
          tier: info.tier,
          cost: info.cost,
          free: free,
        );
      case PlacementKind.building:
        result = _placeBuildingFor(type, info, tile, row, col, free);
    }

    if (result == PlacementResult.placed && free) {
      _freeMoveType = null;
    }
    if (result == PlacementResult.placed && info.kind == PlacementKind.building) {
      // Buildings place one at a time; infra stays selected to lay a chain.
      placementSelection = null;
    }

    if (result == PlacementResult.placed || result == PlacementResult.removed) {
      HapticFeedback.selectionClick();
      _computeNetworksAndWatering();
      notifyListeners();
      _saveNow();
    }
    return result;
  }

  PlacementResult _placeBuildingFor(
    PlacementType type,
    PlacementInfo info,
    Tile tile,
    int row,
    int col,
    bool free,
  ) {
    switch (info.buildingType!) {
      case BuildingType.solarPanel:
        return _placeBuilding(
          tile,
          BuildingType.solarPanel,
          cost: info.cost,
          free: free,
          isValidTerrain: (t) =>
              t == Terrain.openGround || t == Terrain.elevatedGround,
        );
      case BuildingType.pump:
        return _placeBuilding(
          tile,
          BuildingType.pump,
          cost: info.cost,
          free: free,
          isValidTerrain: (t) => t != Terrain.farmland && t != Terrain.lake,
          extraValid: () => _neighbors4(row, col).any(
            (rc) => state.tiles[rc.$1][rc.$2].terrain == Terrain.lake,
          ),
        );
      case BuildingType.sprinkler:
        return _placeBuilding(
          tile,
          BuildingType.sprinkler,
          cost: info.cost,
          free: free,
          tier: info.tier,
          isValidTerrain: (t) => t != Terrain.farmland && t != Terrain.lake,
        );
      case BuildingType.silo:
        return PlacementResult.invalidTile; // not purchasable (yet)
    }
  }

  /// The Lake is immutable (§4/§11 comment above) — no Wire/Pipe of any
  /// tier can ever be placed on it, matching the same rule already applied
  /// to every Building.
  PlacementResult _placeInfra(
    Tile tile, {
    required bool isWire,
    required int tier,
    required int cost,
    required bool free,
  }) {
    if (tile.terrain == Terrain.farmland || tile.terrain == Terrain.lake) {
      return PlacementResult.invalidTile;
    }
    final currentTier = isWire ? tile.wireTier : tile.pipeTier;
    if (currentTier > 0) {
      // Tap-to-remove: acts as the §20 demolish-with-refund flow for infra.
      // Refunds whatever tier is actually on the tile, not the tier
      // currently selected in the Shop.
      final removedType = _infraTypeFor(isWire, currentTier);
      final refund = kPlacementInfo[removedType]!.cost ~/ 2;
      if (isWire) {
        tile.wireTier = 0;
      } else {
        tile.pipeTier = 0;
      }
      state.coins += refund;
      return PlacementResult.removed;
    }
    if (!free) {
      if (state.coins < cost) return PlacementResult.insufficientFunds;
      state.coins -= cost;
    }
    if (isWire) {
      tile.wireTier = tier;
    } else {
      tile.pipeTier = tier;
    }
    return PlacementResult.placed;
  }

  PlacementType _infraTypeFor(bool isWire, int tier) {
    if (isWire) {
      return tier >= 2 ? PlacementType.wireHeavy : PlacementType.wireBasic;
    }
    return tier >= 2 ? PlacementType.pipeHeavy : PlacementType.pipeBasic;
  }

  PlacementResult _placeBuilding(
    Tile tile,
    BuildingType type, {
    required int cost,
    required bool free,
    required bool Function(Terrain) isValidTerrain,
    bool Function()? extraValid,
    int tier = 1,
  }) {
    if (tile.building != null) return PlacementResult.invalidTile;
    if (!isValidTerrain(tile.terrain)) return PlacementResult.invalidTile;
    if (extraValid != null && !extraValid()) return PlacementResult.invalidTile;
    if (!free) {
      if (state.coins < cost) return PlacementResult.insufficientFunds;
      state.coins -= cost;
    }
    tile.building = Building(type: type, tier: tier);
    return PlacementResult.placed;
  }

  /// §20 Demolish — refunds 50% of the building's cost, leaves Pipe/Wire
  /// on the tile intact.
  void demolishBuilding(int row, int col) {
    final tile = state.tiles[row][col];
    final building = tile.building;
    if (building == null || building.type == BuildingType.silo) return;
    final type = _placementTypeFor(building);
    if (type != null) {
      state.coins += kPlacementInfo[type]!.cost ~/ 2;
    }
    tile.building = null;
    _computeNetworksAndWatering();
    notifyListeners();
    _saveNow();
  }

  /// §20 Move — clears the building with no refund and re-enters placement
  /// mode for it at zero additional cost for the next tap.
  void moveBuilding(int row, int col) {
    final tile = state.tiles[row][col];
    final building = tile.building;
    if (building == null || building.type == BuildingType.silo) return;
    final type = _placementTypeFor(building);
    tile.building = null;
    _computeNetworksAndWatering();
    if (type != null) {
      placementSelection = type;
      _freeMoveType = type;
    }
    notifyListeners();
    _saveNow();
  }

  PlacementType? _placementTypeFor(Building building) => switch (building.type) {
    BuildingType.solarPanel => PlacementType.solarPanel,
    BuildingType.pump => PlacementType.pump,
    BuildingType.sprinkler => building.tier >= 2
        ? PlacementType.sprinklerWide
        : PlacementType.sprinklerBasic,
    BuildingType.silo => null,
  };

  // MARK: - Tick (§10, §18)

  /// §22's write cadence: ticks are passive, tick-driven progress (crop
  /// growth, network state) — synced only via the periodic batch timer,
  /// not written to Firestore individually. Discrete player actions
  /// (placement, demolish, harvest, sell...) call `_saveNow()` directly.
  void _tick() {
    _computeNetworksAndWatering();
    _growCrops();
    notifyListeners();
  }

  List<(int, int)> _neighbors4(int r, int c) => [
    for (final d in const [(-1, 0), (1, 0), (0, -1), (0, 1)])
      if (_inBounds(r + d.$1, c + d.$2)) (r + d.$1, c + d.$2),
  ];

  /// Ring of tiles at Chebyshev distance 1..[radius] around (r, c) — radius
  /// 1 is the doc's base 3x3 Sprinkler coverage (§4); radius 2 is a 5x5,
  /// consolidating the doc's Tier 2 (4x4, off-center) and Tier 3 (5x5) into
  /// one "Wide" upgrade for now — the 4x4's off-center direction picker
  /// (§20) is real added UI that's deferred, not built here.
  List<(int, int)> _neighborsRing(int r, int c, int radius) => [
    for (var dr = -radius; dr <= radius; dr++)
      for (var dc = -radius; dc <= radius; dc++)
        if ((dr != 0 || dc != 0) && _inBounds(r + dr, c + dc)) (r + dr, c + dc),
  ];

  String _key(int r, int c) => '$r,$c';

  /// Tier-2 ("Heavy") multiplier applied to a Producer feeding through it.
  double _tierMultiplier(int tier) => tier >= 2 ? 1.5 : 1.0;

  /// Tier-2 ("Heavy") draw reduction applied to a Consumer sitting on it.
  int _reducedDraw(int baseDraw, int tier) =>
      tier >= 2 ? (baseDraw * 3 / 4).ceil() : baseDraw;

  /// Flood-fills a presence grid (Wire or Pipe tiles of any tier) into
  /// components, then resolves each component's supply-vs-draw per §18:
  /// surplus is wasted, a deficit means the whole network's consumers
  /// produce nothing this tick (no partial output).
  void _computeNetworksAndWatering() {
    for (final row in state.tiles) {
      for (final tile in row) {
        tile.isPowered = false;
        tile.isWatered = false;
      }
    }

    // ---- Power: Solar Panel -> Wire -> Pump ----
    final wireComponentOf = <String, int>{};
    final wireComponents = _floodFillComponents(
      (t) => t.wireTier > 0,
      wireComponentOf,
    );
    final powerSupply = List<int>.filled(wireComponents.length, 0);
    final powerDraw = List<int>.filled(wireComponents.length, 0);

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final tile = state.tiles[r][c];
        final building = tile.building;
        if (building?.type == BuildingType.solarPanel) {
          final bestTier = <int, int>{};
          for (final n in _neighbors4(r, c)) {
            final nTile = state.tiles[n.$1][n.$2];
            if (nTile.wireTier <= 0) continue;
            final id = wireComponentOf[_key(n.$1, n.$2)]!;
            if (nTile.wireTier > (bestTier[id] ?? 0)) bestTier[id] = nTile.wireTier;
          }
          bestTier.forEach((id, tier) {
            powerSupply[id] += (solarOutput * _tierMultiplier(tier)).round();
          });
        } else if (building?.type == BuildingType.pump && tile.wireTier > 0) {
          final id = wireComponentOf[_key(r, c)];
          if (id != null) {
            powerDraw[id] += _reducedDraw(pumpPowerDraw, tile.wireTier);
          }
        }
      }
    }
    final poweredComponent = [
      for (var i = 0; i < wireComponents.length; i++)
        powerSupply[i] >= powerDraw[i],
    ];
    for (var i = 0; i < wireComponents.length; i++) {
      if (!poweredComponent[i]) continue;
      for (final rc in wireComponents[i]) {
        state.tiles[rc.$1][rc.$2].isPowered = true;
      }
    }
    bool pumpIsPowered(int r, int c) {
      final id = wireComponentOf[_key(r, c)];
      return id != null && poweredComponent[id];
    }

    // ---- Water: Pump -> Pipe -> Sprinkler ----
    final pipeComponentOf = <String, int>{};
    final pipeComponents = _floodFillComponents(
      (t) => t.pipeTier > 0,
      pipeComponentOf,
    );
    final waterSupply = List<int>.filled(pipeComponents.length, 0);
    final waterDraw = List<int>.filled(pipeComponents.length, 0);
    // componentId -> list of (sprinkler tile, candidate farmland tiles)
    final sprinklerCandidates = <int, List<(int, int, List<(int, int)>)>>{};

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final tile = state.tiles[r][c];
        final building = tile.building;
        final adjLake = _neighbors4(
          r,
          c,
        ).any((rc) => state.tiles[rc.$1][rc.$2].terrain == Terrain.lake);
        if (building?.type == BuildingType.pump &&
            pumpIsPowered(r, c) &&
            adjLake) {
          final bestTier = <int, int>{};
          for (final n in _neighbors4(r, c)) {
            final nTile = state.tiles[n.$1][n.$2];
            if (nTile.pipeTier <= 0) continue;
            final id = pipeComponentOf[_key(n.$1, n.$2)]!;
            if (nTile.pipeTier > (bestTier[id] ?? 0)) bestTier[id] = nTile.pipeTier;
          }
          bestTier.forEach((id, tier) {
            waterSupply[id] += (pumpWaterOutput * _tierMultiplier(tier)).round();
          });
        } else if (building?.type == BuildingType.sprinkler && tile.pipeTier > 0) {
          final id = pipeComponentOf[_key(r, c)];
          if (id == null) continue;
          final radius = building!.tier >= 2 ? 2 : 1;
          final targets = <(int, int)>[
            for (final n in _neighborsRing(r, c, radius))
              if (state.tiles[n.$1][n.$2].terrain == Terrain.farmland &&
                  state.tiles[n.$1][n.$2].cropState != null &&
                  !state.tiles[n.$1][n.$2].cropState!.isReady)
                n,
          ];
          waterDraw[id] += _reducedDraw(targets.length, tile.pipeTier);
          sprinklerCandidates.putIfAbsent(id, () => []).add((r, c, targets));
        }
      }
    }
    final wateredComponent = [
      for (var i = 0; i < pipeComponents.length; i++)
        waterSupply[i] >= waterDraw[i],
    ];
    for (var i = 0; i < pipeComponents.length; i++) {
      if (!wateredComponent[i]) continue;
      for (final rc in pipeComponents[i]) {
        state.tiles[rc.$1][rc.$2].isWatered = true;
      }
    }
    sprinklerCandidates.forEach((componentId, sprinklers) {
      if (!wateredComponent[componentId]) return;
      for (final (_, _, targets) in sprinklers) {
        for (final t in targets) {
          state.tiles[t.$1][t.$2].cropState!.isWateredThisTick = true;
        }
      }
    });
  }

  /// Returns each connected component as a list of coordinates, and fills
  /// [componentOf] with `_key(r, c)` -> component index for every tile where
  /// [predicate] holds.
  List<List<(int, int)>> _floodFillComponents(
    bool Function(Tile) predicate,
    Map<String, int> componentOf,
  ) {
    final visited = <String>{};
    final components = <List<(int, int)>>[];
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final key = _key(r, c);
        if (!predicate(state.tiles[r][c]) || visited.contains(key)) continue;
        final component = <(int, int)>[];
        final queue = <(int, int)>[(r, c)];
        visited.add(key);
        while (queue.isNotEmpty) {
          final (cr, cc) = queue.removeLast();
          component.add((cr, cc));
          componentOf[_key(cr, cc)] = components.length;
          for (final n in _neighbors4(cr, cc)) {
            final nk = _key(n.$1, n.$2);
            if (predicate(state.tiles[n.$1][n.$2]) && !visited.contains(nk)) {
              visited.add(nk);
              queue.add(n);
            }
          }
        }
        components.add(component);
      }
    }
    return components;
  }

  /// Returns how many crops crossed into "ready" this call — used to build
  /// the away-time catch-up summary (§22).
  int _growCrops() {
    var newlyReady = 0;
    for (final row in state.tiles) {
      for (final tile in row) {
        final crop = tile.cropState;
        if (crop == null || crop.isReady) continue;
        if (crop.isWateredThisTick) {
          crop.ticksGrown += 1;
          crop.isWateredThisTick = false;
          if (crop.isReady) newlyReady++;
        }
      }
    }
    return newlyReady;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  // MARK: - Persistence (§22, §27)
  // Firestore-backed: `/users/{uid}/gameState/current`. Two write paths per
  // §22's cadence — `_saveNow()` fires on every discrete player action
  // (placement, demolish, harvest, sell, mode switch); `_startPeriodicSync`
  // covers passive tick-driven progress that no single action owns.
  //
  // What §27 also describes that ISN'T built here yet: the Cloud Function
  // bounds-check on writes (needs the Blaze billing plan — deliberately
  // deferred), the "offline — reconnecting" Status Bar badge for a
  // mid-session network drop, and the blocking "waiting for a connection"
  // screen only covers launch, not a drop mid-session (the client will
  // just start throwing on the next `_saveNow()`/tick fetch attempt).

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(_periodicSyncInterval, (_) => _saveNow());
  }

  Future<void> _saveNow() async {
    final uid = _uid;
    if (uid == null) return;
    state.lastSavedAt = DateTime.now();
    await _gameDoc(uid).set(_toFirestoreDoc(state));
  }

  /// Firestore rejects nested arrays (a `List<List<...>>` field), so
  /// `tiles` — a 2D array in the local shape (§25) — gets remapped to
  /// `{"<row>": {"<col>": tileJson}}` for storage, and back on read. Every
  /// other field round-trips through `GameState.toJson`/`fromJson`
  /// unchanged.
  Map<String, dynamic> _toFirestoreDoc(GameState s) {
    final json = s.toJson();
    final tiles = json['tiles'] as List;
    json['tiles'] = {
      for (var r = 0; r < tiles.length; r++)
        '$r': {
          for (var c = 0; c < (tiles[r] as List).length; c++)
            '$c': (tiles[r] as List)[c],
        },
    };
    return json;
  }

  GameState _fromFirestoreDoc(Map<String, dynamic> doc) {
    final json = Map<String, dynamic>.from(doc);
    final rowMap = Map<String, dynamic>.from(json['tiles'] as Map);
    final rowKeys = rowMap.keys.map(int.parse).toList()..sort();
    json['tiles'] = [
      for (final r in rowKeys)
        () {
          final colMap = Map<String, dynamic>.from(rowMap['$r'] as Map);
          final colKeys = colMap.keys.map(int.parse).toList()..sort();
          return [
            for (final c in colKeys) Map<String, dynamic>.from(colMap['$c'] as Map),
          ];
        }(),
    ];
    return GameState.fromJson(json);
  }
}
