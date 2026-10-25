/// Offers an unfinished boundary on launch (REG-12).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Asks about the newest draft left by a crash or a closed app, then
/// reopens the editor, which picks the draft up, or deletes it.
Future<void> offerDraft(BuildContext context, WidgetRef ref) async {
  final drafts = ref.read(draftStorageProvider);
  final draft = drafts.loadAll().firstOrNull;
  if (draft == null) return;

  final propertyId = draft.propertyId;
  String? name;
  if (propertyId != null) {
    await ref.read(propertiesProvider.future);
    name = ref.read(propertyProvider(propertyId))?.name;
    // The property was deleted meanwhile, so there is nothing to resume.
    if (name == null) {
      await drafts.delete(draft.key);
      return;
    }
  }
  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context);
  final resume = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.draftResumeTitle),
      content: Text(
        name == null
            ? l10n.draftResumeNew(draft.vertexCount)
            : l10n.draftResumeEdit(name),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.actionDiscard),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.actionContinue),
        ),
      ],
    ),
  );
  if (resume == null || !context.mounted) return;
  if (!resume) {
    await drafts.delete(draft.key);
    return;
  }
  unawaited(
    context.push(
      propertyId == null
          ? Routes.newPropertyDraw
          : Routes.propertyBoundary(propertyId),
    ),
  );
}
