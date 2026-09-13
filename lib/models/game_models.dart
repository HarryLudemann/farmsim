// Data shapes follow §25 of the design doc, extended for Milestone B
// (§11): the automated chain (Solar Panel → Wire → Pump → Pipe →
// Sprinkler) plus the Live/Manual toggle (§13).

enum Terrain { openGround, farmland, lake, rockyOutcrop, elevatedGround }

enum BuildingType {
  silo,
  solarPanel,
  pump,
  sprinkler,
  // After Milestone B: windTurbine, mine, factory, fertilizerSpreader, hub,
  // autoSeeder, autoHarvester, decoration
}

enum CropType { wheat }

/// §13 — ticks fire on a timer in Live mode, only on an explicit Step in
/// Manual mode. Both modes share the same tick function.
enum GameMode { live, manual }

/// Placeable infrastructure/buildings for the Shop (§19–20). Wire/Pipe are
/// presence-tile flags with a tier, not `Building`s (§2).
///
/// §4/§17 spec Sprinkler tiers as 3x3 -> 4x4 -> 5x5, gated behind the Tech
/// Tree (not built yet), and don't mention tiers for Wire/Pipe at all.
/// Since Tech Tree gating doesn't exist yet, tiers here are directly
/// purchasable, and Wire/Pipe tiers are a deliberate extension in the
/// spirit of §17's Efficiency branch (see `PlacementInfo` docs on
/// `GameStore`) — a reasonable simplification, not a doc requirement.
enum PlacementType {
  wireBasic,
  wireHeavy,
  pipeBasic,
  pipeHeavy,
  solarPanel,
  pump,
  sprinklerBasic,
  sprinklerWide,
}

enum PlacementKind { wire, pipe, building }

enum ShopCategory { infrastructure, producers, automation }

class Building {
  BuildingType type;
  int tier;
  CropType? siloCropType;
  int siloContents;

  Building({
    required this.type,
    this.tier = 1,
    this.siloCropType,
    this.siloContents = 0,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'tier': tier,
    'siloCropType': siloCropType?.name,
    'siloContents': siloContents,
  };

  factory Building.fromJson(Map<String, dynamic> json) => Building(
    type: BuildingType.values.byName(json['type'] as String),
    tier: json['tier'] as int,
    siloCropType: (json['siloCropType'] as String?) != null
        ? CropType.values.byName(json['siloCropType'] as String)
        : null,
    siloContents: json['siloContents'] as int,
  );
}

class CropState {
  static const int ticksToReady = 6; // §18: ready after 6 ticks (24s at 4s/tick)

  CropType cropType;
  int ticksGrown;
  bool isWateredThisTick;
  bool hasFertilizer;

  CropState({
    required this.cropType,
    this.ticksGrown = 0,
    this.isWateredThisTick = false,
    this.hasFertilizer = false,
  });

  bool get isReady => ticksGrown >= ticksToReady;

  Map<String, dynamic> toJson() => {
    'cropType': cropType.name,
    'ticksGrown': ticksGrown,
    'isWateredThisTick': isWateredThisTick,
    'hasFertilizer': hasFertilizer,
  };

  factory CropState.fromJson(Map<String, dynamic> json) => CropState(
    cropType: CropType.values.byName(json['cropType'] as String),
    ticksGrown: json['ticksGrown'] as int,
    isWateredThisTick: json['isWateredThisTick'] as bool,
    hasFertilizer: json['hasFertilizer'] as bool,
  );
}

class Tile {
  Terrain terrain;
  Building? building;

  /// 0 = none, 1 = basic, 2 = Heavy (§17-spirit efficiency upgrade — see
  /// `GameStore`'s network resolution for what tier 2 actually does).
  int pipeTier;
  int wireTier;
  CropState? cropState;

  /// Recomputed every tick by the flood-fill in §10 — not a durable fact,
  /// just this tick's connectivity result, kept here for tile-glow
  /// rendering (§12). Persisted for convenience; harmless if stale on load
  /// since it's recomputed immediately after load anyway.
  bool isPowered;
  bool isWatered;

  Tile({
    required this.terrain,
    this.building,
    this.pipeTier = 0,
    this.wireTier = 0,
    this.cropState,
    this.isPowered = false,
    this.isWatered = false,
  });

  bool get hasPipe => pipeTier > 0;
  bool get hasWire => wireTier > 0;

  Map<String, dynamic> toJson() => {
    'terrain': terrain.name,
    'building': building?.toJson(),
    'pipeTier': pipeTier,
    'wireTier': wireTier,
    'cropState': cropState?.toJson(),
    'isPowered': isPowered,
    'isWatered': isWatered,
  };

  factory Tile.fromJson(Map<String, dynamic> json) => Tile(
    terrain: Terrain.values.byName(json['terrain'] as String),
    building: (json['building'] as Map<String, dynamic>?) != null
        ? Building.fromJson(json['building'] as Map<String, dynamic>)
        : null,
    pipeTier:
        json['pipeTier'] as int? ?? ((json['hasPipe'] as bool? ?? false) ? 1 : 0),
    wireTier:
        json['wireTier'] as int? ?? ((json['hasWire'] as bool? ?? false) ? 1 : 0),
    cropState: (json['cropState'] as Map<String, dynamic>?) != null
        ? CropState.fromJson(json['cropState'] as Map<String, dynamic>)
        : null,
    isPowered: json['isPowered'] as bool? ?? false,
    isWatered: json['isWatered'] as bool? ?? false,
  );
}

class GameState {
  List<List<Tile>> tiles;
  int coins;
  int wateringCanCharges;
  CropType? carriedCrop;
  GameMode mode;
  DateTime lastSavedAt;

  GameState({
    required this.tiles,
    this.coins = 0,
    this.wateringCanCharges = 0,
    this.carriedCrop,
    this.mode = GameMode.live,
    DateTime? lastSavedAt,
  }) : lastSavedAt = lastSavedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'tiles': tiles.map((row) => row.map((t) => t.toJson()).toList()).toList(),
    'coins': coins,
    'wateringCanCharges': wateringCanCharges,
    'carriedCrop': carriedCrop?.name,
    'mode': mode.name,
    'lastSavedAt': lastSavedAt.toIso8601String(),
  };

  factory GameState.fromJson(Map<String, dynamic> json) => GameState(
    tiles: (json['tiles'] as List)
        .map(
          (row) => (row as List)
              .map((t) => Tile.fromJson(t as Map<String, dynamic>))
              .toList(),
        )
        .toList(),
    coins: json['coins'] as int,
    wateringCanCharges: json['wateringCanCharges'] as int,
    carriedCrop: (json['carriedCrop'] as String?) != null
        ? CropType.values.byName(json['carriedCrop'] as String)
        : null,
    mode: (json['mode'] as String?) != null
        ? GameMode.values.byName(json['mode'] as String)
        : GameMode.live,
    lastSavedAt: DateTime.parse(json['lastSavedAt'] as String),
  );
}
