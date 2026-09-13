import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/game_store.dart';
import 'away_summary_sheet.dart';
import 'grid_view.dart';
import 'placement_banner.dart';
import 'status_bar_view.dart';

/// The Farm is the only root screen (§19) — the Shop and Building info are
/// both sheets over this; everything else in the full design comes later.
class FarmView extends StatefulWidget {
  const FarmView({super.key});

  @override
  State<FarmView> createState() => _FarmViewState();
}

class _FarmViewState extends State<FarmView> {
  bool _awaySummaryScheduled = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GameStore>();

    final summary = store.pendingAwaySummary;
    if (summary != null && !_awaySummaryScheduled) {
      _awaySummaryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showAwaySummarySheet(context, summary);
        store.clearAwaySummary();
        _awaySummaryScheduled = false;
      });
    }

    return Scaffold(
      backgroundColor: const Color.fromRGBO(245, 247, 237, 1),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            const StatusBarView(),
            const SizedBox(height: 8),
            const PlacementBanner(),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Center(child: FarmGridView()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
