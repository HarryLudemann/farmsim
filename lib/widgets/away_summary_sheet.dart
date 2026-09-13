import 'package:flutter/material.dart';

import '../engine/game_store.dart';

String _formatElapsed(Duration d) {
  if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
  if (d.inMinutes >= 1) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inSeconds}s';
}

/// §19/§22 "While you were away" — auto-presented once after a Live-mode
/// catch-up actually simulated missed ticks. This is the payoff §13
/// promises for automation: only Sprinkler-irrigated crops can have grown
/// here, since by-hand actions can't happen retroactively.
void showAwaySummarySheet(BuildContext context, AwaySummary summary) {
  showModalBottomSheet(
    context: context,
    isDismissible: true,
    builder: (sheetContext) {
      final capped = summary.elapsed > const Duration(hours: 12);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'While you were away',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'You were gone ${_formatElapsed(summary.elapsed)}'
                '${capped ? ' (capped at 12h)' : ''} — the farm kept '
                'running for ${summary.ticksSimulated} ticks.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                summary.newlyReadyCrops > 0
                    ? '${summary.newlyReadyCrops} crop(s) became ready for harvest.'
                    : 'Nothing reached "ready" this time — check your Sprinkler coverage and Water supply.',
                style: Theme.of(sheetContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
