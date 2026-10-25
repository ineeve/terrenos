import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/editing/boundary_draft.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/core/properties/property_query.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// The details form (SPEC.md §4.1, §3.6): identifier name and process
/// number first, then type and land use, the location filled in from CAOP,
/// and the optional official references in a collapsed *Registo* section.
/// Only name, type and land use are required (D16). Used after drawing a
/// new boundary, and to edit an existing property's details (IDN-8).
class PropertyDetailsFormPage extends ConsumerStatefulWidget {
  /// Exactly one of [boundary] (a new property) and [propertyId] (editing).
  const new({this.boundary, this.propertyId, super.key})
    : assert((boundary == null) != (propertyId == null), 'new or edit');

  final BoundaryParts? boundary;
  final String? propertyId;

  @override
  ConsumerState<PropertyDetailsFormPage> createState() =>
      _PropertyDetailsFormPageState();
}

/// The optional official references (PROP-5 to PROP-8) and their limits.
const List<({String key, int max})> _registo = [
  (key: PropertyField.matrixArticle, max: 20),
  (key: PropertyField.matrixParish, max: 80),
  (key: PropertyField.registryDescription, max: 30),
  (key: PropertyField.cadastralSection, max: 20),
];

class _PropertyDetailsFormPageState
    extends ConsumerState<PropertyDetailsFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final PropertyDocument? _existing = switch (widget.propertyId) {
    null => null,
    final id => ref.read(propertyRepositoryProvider).byId(id),
  };
  late final _name = TextEditingController(text: _existing?.name);
  late final _processNumber = TextEditingController(
    text: _existing?.processNumber,
  );
  late final Map<String, TextEditingController> _references = {
    for (final r in _registo)
      r.key: TextEditingController(
        text: _existing?.field(r.key) as String? ?? '',
      ),
  };
  late PropertyType? _type = PropertyType.fromCode(
    _existing?.field(PropertyField.type),
  );
  late LandUse? _landUse = LandUse.fromCode(
    _existing?.field(PropertyField.landUse),
  );

  // PROP-9: filled in from CAOP once, then the user's to change.
  late final _distrito = TextEditingController();
  late final _concelho = TextEditingController();
  late final _freguesia = TextEditingController();
  String? _dicofre;
  bool _locationFilled = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    if (_existing case final doc? when locationOf(doc) != null) {
      _setLocation(locationOf(doc)!);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _processNumber,
      _distrito,
      _concelho,
      _freguesia,
      ..._references.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  BoundaryParts? get _boundary =>
      widget.boundary ?? _existing?.geometry.current?.parts;

  void _setLocation(PropertyLocation location) {
    _locationFilled = true;
    _distrito.text = location.distrito ?? '';
    _concelho.text = location.concelho ?? '';
    _freguesia.text = location.freguesia ?? '';
    _dicofre = location.dicofre;
  }

  /// Fills the location from CAOP when it's loaded, unless already set.
  void _fillLocation(AdminBoundaries caop) {
    if (_locationFilled) return;
    // Once only, even when the parcel is outside every freguesia.
    _locationFilled = true;
    final boundary = _boundary;
    final found = boundary == null ? null : locateBoundary(caop, boundary);
    if (found != null) setState(() => _setLocation(found));
  }

  PropertyLocation get _location {
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return PropertyLocation(
      distrito: text(_distrito),
      concelho: text(_concelho),
      freguesia: text(_freguesia),
      dicofre: _dicofre,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final others = ref.read(propertiesProvider).value ?? const [];
    final duplicates = Identifiers.sameProcessNumber(
      _processNumber.text,
      others,
      exceptId: widget.propertyId,
    );
    if (duplicates.isNotEmpty && !await _confirmDuplicate(duplicates.first)) {
      return;
    }
    setState(() => _saving = true);
    final repository = ref.read(propertyRepositoryProvider);
    final fields = <String, Object?>{
      PropertyField.processNumber: Identifiers.storedProcessNumber(
        _processNumber.text,
      ),
      PropertyField.type: _type!.name,
      PropertyField.landUse: _landUse!.code,
      PropertyField.location: _location.toJson(),
      for (final r in _registo)
        r.key: switch (_references[r.key]!.text.trim()) {
          '' => null,
          final value => value,
        },
    };

    final id = widget.propertyId;
    if (id != null) {
      await repository.setFields(id, {
        PropertyField.name: _name.text.trim(),
        ...fields,
      });
      if (mounted) context.pop();
      return;
    }
    final doc = await repository.create(
      name: _name.text,
      boundary: widget.boundary,
      // Empty optional fields aren't stored at all.
      fields: {
        for (final MapEntry(:key, :value) in fields.entries) key: ?value,
      },
    );
    // The boundary is saved now, so its draft isn't needed (REG-12).
    await ref.read(draftStorageProvider).delete(BoundaryDraft.newProperty);
    if (!mounted) return;
    context.go(Routes.properties);
    await context.push(Routes.property(doc.id));
  }

  /// IDN-4: warns about a process number another property has, and offers
  /// to open that property instead.
  Future<bool> _confirmDuplicate(PropertyDocument other) async {
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.processNumberDuplicateTitle),
        content: Text(l10n.processNumberDuplicateBody(other.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('open'),
            child: Text(l10n.actionOpenProperty(other.name)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: Text(l10n.actionSaveAnyway),
          ),
        ],
      ),
    );
    if (choice == 'open' && mounted) {
      await context.push(Routes.property(other.id));
    }
    return choice == 'save';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final others = ref.watch(propertiesProvider).value ?? const [];
    final sameName = Identifiers.sameName(
      _name.text,
      others,
      exceptId: widget.propertyId,
    );
    final sameNumber = Identifiers.sameProcessNumber(
      _processNumber.text,
      others,
      exceptId: widget.propertyId,
    );
    if (ref.watch(adminBoundariesProvider).value case final caop?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fillLocation(caop);
      });
    }

    Widget text(
      TextEditingController controller,
      String label, {
      int? maxLength,
      String? helper,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, helperText: helper),
        onChanged: (_) => setState(() {
          // Names the user typed aren't CAOP's any more.
          if (controller == _distrito ||
              controller == _concelho ||
              controller == _freguesia) {
            _dicofre = null;
          }
        }),
      ),
    );

    String referenceLabel(String key) => switch (key) {
      PropertyField.matrixArticle => l10n.fieldMatrixArticle,
      PropertyField.matrixParish => l10n.fieldMatrixParish,
      PropertyField.registryDescription => l10n.fieldRegistryDescription,
      _ => l10n.fieldCadastralSection,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.propertyId == null ? l10n.detailsTitle : l10n.editDetailsTitle,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              autofocus: widget.propertyId == null,
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
            const SizedBox(height: 16),
            // PROP-9: filled in from CAOP, editable.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: true,
              title: Text(l10n.locationTitle),
              subtitle: _dicofre == null ? null : Text(l10n.locationFromMap),
              children: [
                text(_freguesia, l10n.fieldFreguesia),
                text(_concelho, l10n.fieldConcelho),
                text(_distrito, l10n.fieldDistrito),
              ],
            ),
            // PROP-5 to PROP-8, all optional (D16), collapsed by default.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: _registo.any(
                (r) => _references[r.key]!.text.isNotEmpty,
              ),
              title: Text(l10n.registoTitle),
              children: [
                for (final r in _registo)
                  text(
                    _references[r.key]!,
                    referenceLabel(r.key),
                    maxLength: r.max,
                    helper: r.key == PropertyField.matrixParish
                        ? l10n.fieldMatrixParishHint
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              widget.propertyId == null
                  ? l10n.actionSaveProperty
                  : l10n.actionSave,
            ),
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
