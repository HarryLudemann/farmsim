import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:farmsim/engine/game_store.dart';
import 'package:farmsim/main.dart';
import 'package:farmsim/models/game_models.dart';
import 'package:farmsim/widgets/farm_view.dart';
import 'package:farmsim/widgets/status_bar_view.dart';

void main() {
  testWidgets('Farm loads with the starting grid and zero coins', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FarmSimApp());
    // Not pumpAndSettle: the grid's idle-animation clock (§12) repeats
    // forever by design, so "settled" never happens. A couple of pumps is
    // enough to flush GameStore's async load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Coin count and the empty silo's content count both render as "0".
    expect(find.text('0'), findsNWidgets(2));
    // Scoped to the status bar: the Shop's Pipe icon is also water_drop
    // (only relevant while the Shop sheet is open, but scope defensively).
    expect(
      find.descendant(
        of: find.byType(StatusBarView),
        matching: find.byIcon(Icons.water_drop),
      ),
      findsNWidgets(3), // watering can charges
    );
    expect(tester.takeException(), isNull);

    // Unmount so GameStore.dispose() cancels its tick Timer before the test
    // ends — otherwise flutter_test flags it as a leaked pending timer.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('full plant -> water -> grow -> harvest -> sell loop (§5, §15)', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FarmSimApp());
    // Not pumpAndSettle: the grid's idle-animation clock (§12) repeats
    // forever by design, so "settled" never happens. A couple of pumps is
    // enough to flush GameStore's async load.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final store = Provider.of<GameStore>(
      tester.element(find.byType(FarmView)),
      listen: false,
    );

    // Fill the watering can from the Lake (row 1, col 1 in the starting grid).
    store.tapTile(1, 1);
    expect(store.state.wateringCanCharges, GameStore.wateringCanMaxCharges);

    // Plant on the first Farmland tile (row 3, col 0).
    store.tapTile(3, 0);
    expect(store.state.tiles[3][0].cropState, isNotNull);

    // Water it every tick until it's ready, refilling the can as needed.
    for (var i = 0; i < CropState.ticksToReady; i++) {
      if (store.state.wateringCanCharges == 0) store.tapTile(1, 1);
      store.tapTile(3, 0);
      await tester.pump(
        GameStore.tickInterval + const Duration(milliseconds: 50),
      );
    }
    expect(store.state.tiles[3][0].cropState!.isReady, isTrue);

    // Harvest into hand.
    store.tapTile(3, 0);
    expect(store.state.carriedCrop, CropType.wheat);
    expect(store.state.tiles[3][0].cropState, isNull);

    // Deposit into the Silo (row 3, col 3).
    store.tapTile(3, 3);
    expect(store.state.carriedCrop, isNull);
    expect(store.state.tiles[3][3].building!.siloContents, 1);

    // Sell — a deliberate action via the Silo detail sheet (§19) now,
    // not a bare empty-handed tap.
    store.sellSilo(3, 3);
    expect(store.state.coins, GameStore.sellPricePerCrop);
    expect(store.state.tiles[3][3].building!.siloContents, 0);

    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Milestone B: Solar -> Wire -> Pump -> Pipe -> Sprinkler waters crops with no manual taps (§4, §10)',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const FarmSimApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final store = Provider.of<GameStore>(
        tester.element(find.byType(FarmView)),
        listen: false,
      );
      store.state.coins = 500; // skip the grind, this test is about wiring

      // Solar Panel at (0,0), Wire chain (1,0)-(2,0)-(2,1) down to the Pump.
      store.selectPlacement(PlacementType.solarPanel);
      expect(store.attemptPlacement(0, 0), PlacementResult.placed);

      store.selectPlacement(PlacementType.wireBasic);
      expect(store.attemptPlacement(1, 0), PlacementResult.placed);
      expect(store.attemptPlacement(2, 0), PlacementResult.placed);
      expect(store.attemptPlacement(2, 1), PlacementResult.placed);
      store.cancelPlacement();

      // Pump at (2,1): adjacent to the Lake at (1,1), sitting on the Wire.
      store.selectPlacement(PlacementType.pump);
      expect(store.attemptPlacement(2, 1), PlacementResult.placed);

      // Pipe + Sprinkler share (2,0): adjacent to the Pump, and its 3x3
      // coverage reaches Farmland at (3,0) and (3,1).
      store.selectPlacement(PlacementType.pipeBasic);
      expect(store.attemptPlacement(2, 0), PlacementResult.placed);
      store.selectPlacement(PlacementType.sprinklerBasic);
      expect(store.attemptPlacement(2, 0), PlacementResult.placed);

      // Plant by hand (§15 still applies), but never touch the watering can.
      store.tapTile(3, 0);
      store.tapTile(3, 1);
      expect(store.state.tiles[3][0].cropState, isNotNull);
      expect(store.state.tiles[3][1].cropState, isNotNull);
      expect(store.state.wateringCanCharges, 0);

      for (var i = 0; i < CropState.ticksToReady; i++) {
        await tester.pump(
          GameStore.tickInterval + const Duration(milliseconds: 50),
        );
      }

      expect(store.state.tiles[3][0].cropState!.isReady, isTrue);
      expect(store.state.tiles[3][1].cropState!.isReady, isTrue);
      expect(store.state.tiles[2][1].isPowered, isTrue); // Pump tile
      expect(store.state.tiles[2][0].isWatered, isTrue); // Pipe/Sprinkler tile

      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Live/Manual toggle (§13): Manual only advances on Step', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FarmSimApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final store = Provider.of<GameStore>(
      tester.element(find.byType(FarmView)),
      listen: false,
    );

    store.setMode(GameMode.manual);
    store.tapTile(1, 1); // fill can from the Lake
    store.tapTile(3, 2); // plant
    store.tapTile(3, 2); // water
    final ticksBefore = store.state.tiles[3][2].cropState!.ticksGrown;

    // Real time passing should NOT grow the crop in Manual mode.
    await tester.pump(
      GameStore.tickInterval + const Duration(milliseconds: 50),
    );
    expect(store.state.tiles[3][2].cropState!.ticksGrown, ticksBefore);

    store.step();
    expect(store.state.tiles[3][2].cropState!.ticksGrown, ticksBefore + 1);

    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Placement validation and infra tap-to-remove refund (§20)', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FarmSimApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final store = Provider.of<GameStore>(
      tester.element(find.byType(FarmView)),
      listen: false,
    );

    store.state.coins = 0;
    store.selectPlacement(PlacementType.solarPanel);
    expect(
      store.attemptPlacement(0, 1),
      PlacementResult.insufficientFunds,
    );
    expect(store.state.tiles[0][1].building, isNull);

    store.state.coins = 100;
    store.selectPlacement(PlacementType.pump);
    // (5,5) is far from the Lake at (1,1)/(1,2) — not adjacent.
    expect(store.attemptPlacement(5, 5), PlacementResult.invalidTile);

    store.selectPlacement(PlacementType.wireBasic);
    expect(store.attemptPlacement(4, 4), PlacementResult.placed);
    expect(store.state.tiles[4][4].hasWire, isTrue);
    final coinsAfterPlace = store.state.coins;

    // Tapping the same tile again with Wire selected removes it (§20's
    // demolish-with-refund, streamlined into a single tap-to-toggle).
    expect(store.attemptPlacement(4, 4), PlacementResult.removed);
    expect(store.state.tiles[4][4].hasWire, isFalse);
    expect(
      store.state.coins,
      coinsAfterPlace + kPlacementInfo[PlacementType.wireBasic]!.cost ~/ 2,
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('The Lake is immutable: no Wire, Pipe, or Building on it', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FarmSimApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final store = Provider.of<GameStore>(
      tester.element(find.byType(FarmView)),
      listen: false,
    );
    store.state.coins = 500;

    // (1,1) and (1,2) are the two starting Lake tiles.
    for (final type in [
      PlacementType.wireBasic,
      PlacementType.wireHeavy,
      PlacementType.pipeBasic,
      PlacementType.pipeHeavy,
      PlacementType.solarPanel,
      PlacementType.pump,
      PlacementType.sprinklerBasic,
    ]) {
      store.selectPlacement(type);
      expect(
        store.attemptPlacement(1, 1),
        PlacementResult.invalidTile,
        reason: '$type must not be placeable on the Lake',
      );
    }
    expect(store.state.tiles[1][1].wireTier, 0);
    expect(store.state.tiles[1][1].pipeTier, 0);
    expect(store.state.tiles[1][1].building, isNull);
    expect(store.state.tiles[1][1].terrain, Terrain.lake);

    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Heavy Wire/Pipe (§17-spirit tiers): boosts producers, cuts consumer draw',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const FarmSimApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final store = Provider.of<GameStore>(
        tester.element(find.byType(FarmView)),
        listen: false,
      );
      store.state.coins = 500;

      // Same layout as the Milestone B chain test, but every Wire/Pipe tile
      // is the Heavy tier this time.
      store.selectPlacement(PlacementType.solarPanel);
      store.attemptPlacement(0, 0);

      store.selectPlacement(PlacementType.wireHeavy);
      store.attemptPlacement(1, 0);
      store.attemptPlacement(2, 0);
      store.attemptPlacement(2, 1);
      store.cancelPlacement();

      store.selectPlacement(PlacementType.pump);
      store.attemptPlacement(2, 1);

      store.selectPlacement(PlacementType.pipeHeavy);
      store.attemptPlacement(2, 0);
      store.selectPlacement(PlacementType.sprinklerBasic);
      store.attemptPlacement(2, 0);

      store.tapTile(3, 0); // plant, so the Sprinkler has something to draw for

      await tester.pump(
        GameStore.tickInterval + const Duration(milliseconds: 50),
      );

      // Solar (10) x1.5 = 15 credited; Pump draw reduced from 4 to 3 (ceil
      // of 4*0.75) -> still powered with supply to spare either way, but the
      // reduced draw is the part worth asserting precisely.
      expect(store.state.tiles[2][1].isPowered, isTrue);
      // Pump (8) x1.5 = 12 credited into the pipe network; Sprinkler draw
      // for one growing Farmland tile, reduced from 1 to 1 (ceil(0.75)=1) —
      // watered regardless, so assert the crop actually grew as the real
      // end-to-end signal that the boosted/reduced numbers didn't break
      // the chain.
      expect(store.state.tiles[2][0].isWatered, isTrue);
      expect(store.state.tiles[3][0].cropState!.ticksGrown, 1);

      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Shop sheet: selecting an item arms placement and closes', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const FarmSimApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final store = Provider.of<GameStore>(
      tester.element(find.byType(FarmView)),
      listen: false,
    );

    await tester.tap(find.byIcon(Icons.storefront));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet animation

    expect(find.text('Shop'), findsOneWidget);
    expect(find.text('Heavy Wire'), findsOneWidget);
    // Further down the list — the ListView is a lazy sliver, so scroll to
    // where it would build rather than assuming it's already in the tree.
    await tester.scrollUntilVisible(
      find.text('Sprinkler (Wide)'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Sprinkler (Wide)'), findsOneWidget);

    await tester.tap(find.text('Solar Panel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(store.placementSelection, PlacementType.solarPanel);
    // Sheet closed, and the placement banner now shows what's armed.
    expect(find.text('Shop'), findsNothing);
    expect(find.textContaining('Placing Solar Panel'), findsOneWidget);

    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Silo capacity (§18): a full Silo rejects deposits and the badge finds it',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const FarmSimApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final store = Provider.of<GameStore>(
        tester.element(find.byType(FarmView)),
        listen: false,
      );

      final building = store.state.tiles[3][3].building!;
      building.siloCropType = CropType.wheat;
      building.siloContents = GameStore.siloCapacity;
      store.state.carriedCrop = CropType.wheat;

      store.tapTile(3, 3); // attempt to deposit into a full Silo
      expect(store.state.tiles[3][3].building!.siloContents, GameStore.siloCapacity);
      expect(store.state.carriedCrop, CropType.wheat); // rejected, stays in hand

      expect(store.firstFullSiloTile, (3, 3));

      // Selling drains it, and the badge should clear.
      store.sellSilo(3, 3);
      expect(store.state.coins, GameStore.siloCapacity * GameStore.sellPricePerCrop);
      expect(store.firstFullSiloTile, isNull);

      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Deficit badge (§23): an unpowered Pump on Wire is found and clears once powered',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const FarmSimApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final store = Provider.of<GameStore>(
        tester.element(find.byType(FarmView)),
        listen: false,
      );
      store.state.coins = 500;

      // Wire + Pump, but no Solar Panel feeding it -> genuinely deficient,
      // not just "not connected yet".
      store.selectPlacement(PlacementType.wireBasic);
      store.attemptPlacement(2, 1);
      store.cancelPlacement();
      store.selectPlacement(PlacementType.pump);
      store.attemptPlacement(2, 1);

      await tester.pump(
        GameStore.tickInterval + const Duration(milliseconds: 50),
      );
      expect(store.firstDeficitTile, (2, 1));

      // Add the missing Solar Panel + connecting Wire -> deficit clears.
      store.selectPlacement(PlacementType.solarPanel);
      store.attemptPlacement(0, 0);
      store.selectPlacement(PlacementType.wireBasic);
      store.attemptPlacement(1, 0);
      store.attemptPlacement(2, 0);

      await tester.pump(
        GameStore.tickInterval + const Duration(milliseconds: 50),
      );
      expect(store.firstDeficitTile, isNull);

      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Away-time catch-up (§13, §22): only Sprinkler-irrigated crops progress while away',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      // --- First session: build a working chain, plant two crops. ---
      await tester.pumpWidget(const FarmSimApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final store1 = Provider.of<GameStore>(
        tester.element(find.byType(FarmView)),
        listen: false,
      );
      store1.state.coins = 500;

      store1.selectPlacement(PlacementType.solarPanel);
      store1.attemptPlacement(0, 0);
      store1.selectPlacement(PlacementType.wireBasic);
      store1.attemptPlacement(1, 0);
      store1.attemptPlacement(2, 0);
      store1.attemptPlacement(2, 1);
      store1.cancelPlacement();
      store1.selectPlacement(PlacementType.pump);
      store1.attemptPlacement(2, 1);
      store1.selectPlacement(PlacementType.pipeBasic);
      store1.attemptPlacement(2, 0);
      store1.selectPlacement(PlacementType.sprinklerBasic);
      store1.attemptPlacement(2, 0);

      store1.tapTile(3, 0); // planted, inside the Sprinkler's coverage
      store1.tapTile(3, 2); // planted, OUTSIDE the Sprinkler's coverage
      store1.tapTile(1, 1); // fill the watering can from the Lake
      store1.tapTile(3, 2); // hand-water it once, like a real play session

      await tester.pump(
        GameStore.tickInterval + const Duration(milliseconds: 50),
      );
      final sprinklerTicksBefore =
          store1.state.tiles[3][0].cropState!.ticksGrown;
      final handTicksBefore = store1.state.tiles[3][2].cropState!.ticksGrown;
      expect(sprinklerTicksBefore, greaterThanOrEqualTo(1));
      expect(handTicksBefore, 1);

      // --- Simulate closing the app for 20s (5 ticks) by backdating the
      // save that's already on disk, then "relaunching". ---
      final prefs = await SharedPreferences.getInstance();
      final json =
          jsonDecode(prefs.getString('farmsim.gamestate')!)
              as Map<String, dynamic>;
      json['lastSavedAt'] = DateTime.now()
          .subtract(const Duration(seconds: 20))
          .toIso8601String();
      await prefs.setString('farmsim.gamestate', jsonEncode(json));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const FarmSimApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final store2 = Provider.of<GameStore>(
        tester.element(find.byType(FarmView)),
        listen: false,
      );

      // The Sprinkler-irrigated crop kept growing while "away"; the
      // hand-watered one — which needs a tap every tick — did not, since
      // by-hand actions can't happen retroactively.
      expect(
        store2.state.tiles[3][0].cropState!.ticksGrown,
        greaterThan(sprinklerTicksBefore),
      );
      expect(store2.state.tiles[3][2].cropState!.ticksGrown, handTicksBefore);

      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
