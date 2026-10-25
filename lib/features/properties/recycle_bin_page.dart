import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Deleted properties, restorable for 30 days (MGT-3). Older ones stay as
/// tombstones so sync can't bring them back (§9.5.5), but aren't listed.
class RecycleBinPage extends ConsumerWidget {
  const new({this.now, super.key});

  static const keepDays = 30;

  /// For tests; defaults to the clock.
  final DateTime Function()? now;

  /// Whole days left before [doc] leaves the bin; 0 or less when gone.
  static int daysLeft(PropertyDocument doc, DateTime now) {
    final deletedAt = DateTime.fromMillisecondsSinceEpoch(
      doc.deleted.timestamp.millis,
      isUtc: true,
    );
    return keepDays - now.difference(deletedAt).inDays;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final today = (now ?? DateTime.now)();
    final deleted = [
      for (final doc
          in ref.watch(deletedPropertiesProvider).value ??
              const <PropertyDocument>[])
        if (daysLeft(doc, today) > 0) doc,
    ]..sort((a, b) => b.deleted.timestamp.compareTo(a.deleted.timestamp));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recycleBinTitle)),
      body: deleted.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(l10n.recycleBinEmpty, textAlign: TextAlign.center),
              ),
            )
          : ListView(
              children: [
                for (final doc in deleted)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: Text(doc.name),
                    subtitle: Text(
                      l10n.recycleBinDaysLeft(daysLeft(doc, today)),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await ref
                            .read(propertyRepositoryProvider)
                            .restore(doc.id);
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.propertyRestored)),
                        );
                      },
                      child: Text(l10n.actionRestore),
                    ),
                  ),
              ],
            ),
    );
  }
}
