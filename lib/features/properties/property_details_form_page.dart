import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// The details form after the boundary (SPEC.md §4.1): identifier name and
/// process number first, then type and land use. Only name, type and land
/// use are required; the other official references come later (D16).
class PropertyDetailsFormPage extends ConsumerStatefulWidget {
  const new({required this.boundary, super.key});

  final BoundaryParts boundary;

  @override
  ConsumerState<PropertyDetailsFormPage> createState() =>
      _PropertyDetailsFormPageState();
}

class _PropertyDetailsFormPageState
    extends ConsumerState<PropertyDetailsFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _processNumber = TextEditingController();
  PropertyType? _type;
  LandUse? _landUse;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _processNumber.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repository = ref.read(propertyRepositoryProvider);
    final doc = await repository.create(
      name: _name.text,
      boundary: widget.boundary,
      fields: {
        PropertyField.processNumber: Identifiers.storedProcessNumber(
          _processNumber.text,
        ),
        PropertyField.type: _type!.name,
        PropertyField.landUse: _landUse!.code,
      },
    );
    if (!mounted) return;
    context.go(Routes.properties);
    await context.push(Routes.property(doc.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final others = ref.watch(propertiesProvider).value ?? const [];
    final sameName = Identifiers.sameName(_name.text, others);
    final sameNumber = Identifiers.sameProcessNumber(
      _processNumber.text,
      others,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.detailsTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: Identifiers.maxNameLength,
              decoration: InputDecoration(
                labelText: '${l10n.fieldName} *',
                hintText: l10n.nameHint,
                // IDN-2: a warning, not a block.
                helperText: sameName.isEmpty ? null : l10n.nameDuplicate,
              ),
              validator: (value) =>
                  switch (Identifiers.validateName(value ?? '')) {
                    NameError.empty => l10n.nameRequired,
                    NameError.tooLong => l10n.nameTooLong,
                    null => null,
                  },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _processNumber,
              maxLength: Identifiers.maxProcessNumberLength,
              decoration: InputDecoration(
                labelText: l10n.fieldProcessNumber,
                hintText: l10n.processNumberHint,
                // IDN-4: almost always a mistake, but still allowed.
                helperText: sameNumber.isEmpty
                    ? null
                    : l10n.processNumberDuplicate,
              ),
              validator: (value) =>
                  switch (Identifiers.validateProcessNumber(value ?? '')) {
                    ProcessNumberError.tooLong => l10n.processNumberTooLong,
                    ProcessNumberError.invalidCharacters =>
                      l10n.processNumberInvalid,
                    null => null,
                  },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PropertyType>(
              initialValue: _type,
              decoration: InputDecoration(labelText: '${l10n.fieldType} *'),
              items: [
                for (final type in PropertyType.values)
                  DropdownMenuItem(
                    value: type,
                    child: Text(propertyTypeLabel(type, l10n)),
                  ),
              ],
              validator: (value) => value == null ? l10n.fieldRequired : null,
              onChanged: (value) => setState(() => _type = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<LandUse>(
              initialValue: _landUse,
              decoration: InputDecoration(labelText: '${l10n.fieldLandUse} *'),
              items: [
                for (final use in LandUse.values)
                  DropdownMenuItem(
                    value: use,
                    child: Text(landUseLabel(use, l10n)),
                  ),
              ],
              validator: (value) => value == null ? l10n.fieldRequired : null,
              onChanged: (value) => setState(() => _landUse = value),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(l10n.actionSaveProperty),
          ),
        ),
      ),
    );
  }
}

String propertyTypeLabel(PropertyType type, AppLocalizations l10n) =>
    switch (type) {
      PropertyType.rustico => l10n.typeRustico,
      PropertyType.urbano => l10n.typeUrbano,
      PropertyType.misto => l10n.typeMisto,
    };

String landUseLabel(LandUse use, AppLocalizations l10n) => switch (use) {
  LandUse.oliveGrove => l10n.landUseOliveGrove,
  LandUse.vineyard => l10n.landUseVineyard,
  LandUse.orchard => l10n.landUseOrchard,
  LandUse.arable => l10n.landUseArable,
  LandUse.pasture => l10n.landUsePasture,
  LandUse.eucalyptus => l10n.landUseEucalyptus,
  LandUse.pine => l10n.landUsePine,
  LandUse.montado => l10n.landUseMontado,
  LandUse.scrubland => l10n.landUseScrubland,
  LandUse.builtUp => l10n.landUseBuiltUp,
  LandUse.mixed => l10n.landUseMixed,
  LandUse.other => l10n.landUseOther,
};
