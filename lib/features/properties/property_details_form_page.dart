import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/core/model/property_kinds.dart';
import 'package:terrenos/core/properties/location.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Property details (SPEC.md §3.6, §4.1). Creates a property after its
/// boundary, or edits an existing one (IDN-8). Name and process number come
/// first; only name, type and land use are required (D16); the optional
/// sections start collapsed.
class PropertyDetailsFormPage extends ConsumerStatefulWidget {
  const new create({required BoundaryParts this.boundary, super.key})
    : propertyId = null;

  const new edit({required String this.propertyId, super.key})
    : boundary = null;

  final BoundaryParts? boundary;
  final String? propertyId;

  @override
  ConsumerState<PropertyDetailsFormPage> createState() =>
      _PropertyDetailsFormPageState();
}

class _PropertyDetailsFormPageState
    extends ConsumerState<PropertyDetailsFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _text = <String, TextEditingController>{};
  final _owners = <(TextEditingController, TextEditingController)>[];
  PropertyType? _type;
  LandUse? _landUse;
  DateTime? _acquiredOn;

  /// Whether the location still comes from CAOP (PROP-9).
  var _locationAuto = true;
  var _saving = false;

  static const Map<String, int> _maxLengths = {
    PropertyField.matrixArticle: 20,
    PropertyField.matrixParish: 80,
    PropertyField.registryDescription: 30,
    PropertyField.cadastralSection: 20,
    PropertyField.placeName: 80,
    PropertyField.notes: 2000,
    'distrito': 80,
    'concelho': 80,
    'freguesia': 120,
    'n': 120,
    's': 120,
    'e': 120,
    'w': 120,
  };

  bool get _editing => widget.propertyId != null;

  TextEditingController _c(String key) =>
      _text.putIfAbsent(key, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    final id = widget.propertyId;
    if (id != null) {
      _load(ref.read(propertyRepositoryProvider).byId(id)!);
    } else {
      unawaited(_fillLocationFromCaop());
    }
  }

  void _load(PropertyDocument doc) {
    String text(Object? v) => v is String ? v : '';
    _c(PropertyField.name).text = doc.name;
    _c(PropertyField.processNumber).text = doc.processNumber ?? '';
    _type = PropertyType.fromCode(doc.field(PropertyField.type));
    _landUse = LandUse.fromCode(doc.field(PropertyField.landUse));
    for (final key in [
      PropertyField.matrixArticle,
      PropertyField.matrixParish,
      PropertyField.registryDescription,
      PropertyField.cadastralSection,
      PropertyField.placeName,
      PropertyField.notes,
    ]) {
      _c(key).text = text(doc.field(key));
    }
    if (readLocation(doc) case final location?) {
      _c('distrito').text = location.distrito;
      _c('concelho').text = location.concelho;
      _c('freguesia').text = location.freguesia;
    }
    _locationAuto = isAutoLocation(doc);
    if (doc.field(PropertyField.confrontations)
        case final Map<String, Object?> c) {
      for (final side in ['n', 's', 'e', 'w']) {
        _c(side).text = text(c[side]);
      }
    }
    if (doc.field(PropertyField.owners) case final List<Object?> owners) {
      for (final owner in owners.whereType<Map<String, Object?>>()) {
        final share = owner['share'];
        _owners.add((
          TextEditingController(text: text(owner['name'])),
          TextEditingController(text: share is num ? _shareText(share) : ''),
        ));
      }
    }
    if (doc.field(PropertyField.acquiredOn) case final String date) {
      _acquiredOn = DateTime.tryParse(date);
    }
  }

  static String _shareText(num share) =>
      share == share.roundToDouble() ? '${share.round()}' : '$share';

  Future<void> _fillLocationFromCaop() async {
    final caop = await ref.read(caopOrNullProvider.future);
    final location = autoLocation(caop, widget.boundary!);
    if (location == null || !mounted || !_locationAuto) return;
    setState(() {
      _c('distrito').text = location['distrito']! as String;
      _c('concelho').text = location['concelho']! as String;
      _c('freguesia').text = location['freguesia']! as String;
    });
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    for (final (name, share) in _owners) {
      name.dispose();
      share.dispose();
    }
    super.dispose();
  }

  String? _optional(String key) {
    final value = _c(key).text.trim();
    return value.isEmpty ? null : value;
  }

  Map<String, Object?> _fields() {
    final location = [
      _optional('distrito'),
      _optional('concelho'),
      _optional('freguesia'),
    ];
    final confrontations = {
      for (final side in ['n', 's', 'e', 'w']) side: ?_optional(side),
    };
    final owners = [
      for (final (name, share) in _owners)
        if (name.text.trim().isNotEmpty)
          {'name': name.text.trim(), 'share': ?_parseShare(share.text)},
    ];
    final date = _acquiredOn;
    return {
      PropertyField.name: _c(PropertyField.name).text.trim(),
      PropertyField.processNumber: Identifiers.storedProcessNumber(
        _c(PropertyField.processNumber).text,
      ),
      PropertyField.type: _type!.name,
      PropertyField.landUse: _landUse!.code,
      PropertyField.matrixArticle: _optional(PropertyField.matrixArticle),
      PropertyField.matrixParish: _optional(PropertyField.matrixParish),
      PropertyField.registryDescription: _optional(
        PropertyField.registryDescription,
      ),
      PropertyField.cadastralSection: _optional(PropertyField.cadastralSection),
      PropertyField.location: location.every((v) => v == null)
          ? null
          : {
              'distrito': location[0] ?? '',
              'concelho': location[1] ?? '',
              'freguesia': location[2] ?? '',
              'auto': _locationAuto,
            },
      PropertyField.placeName: _optional(PropertyField.placeName),
      PropertyField.confrontations: confrontations.isEmpty
          ? null
          : confrontations,
      PropertyField.owners: owners.isEmpty ? null : owners,
      PropertyField.acquiredOn: date == null
          ? null
          : '${date.year.toString().padLeft(4, '0')}-'
                '${date.month.toString().padLeft(2, '0')}-'
                '${date.day.toString().padLeft(2, '0')}',
      PropertyField.notes: _optional(PropertyField.notes),
    };
  }

  static num? _parseShare(String text) {
    final value = num.tryParse(text.trim().replaceAll(',', '.'));
    return value == null || value < 0 || value > 100 ? null : value;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repository = ref.read(propertyRepositoryProvider);
    final fields = _fields();
    final id = widget.propertyId;
    if (id != null) {
      await repository.setFields(id, fields);
      if (mounted) context.pop();
      return;
    }
    final name = fields.remove(PropertyField.name)! as String;
    final doc = await repository.create(
      name: name,
      boundary: widget.boundary,
      // Empty optional fields aren't stored on a new property.
      fields: {
        for (final MapEntry(:key, :value) in fields.entries) key: ?value,
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
    final id = widget.propertyId;
    final sameName = Identifiers.sameName(
      _c(PropertyField.name).text,
      others,
      exceptId: id,
    );
    final sameNumber = Identifiers.sameProcessNumber(
      _c(PropertyField.processNumber).text,
      others,
      exceptId: id,
    );

    String? maxLength(String? value, int max) =>
        (value ?? '').trim().length > max ? l10n.textTooLong('$max') : null;

    Widget text(
      String key,
      String label, {
      int maxLines = 1,
      String? helper,
      ValueChanged<String>? onChanged,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _c(key),
        maxLines: maxLines,
        minLines: 1,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: label, helperText: helper),
        validator: (value) => maxLength(value, _maxLengths[key]!),
        onChanged: onChanged,
      ),
    );

    void locationEdited(String _) {
      if (_locationAuto) setState(() => _locationAuto = false);
    }

    final date = _acquiredOn;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? l10n.editDetailsTitle : l10n.detailsTitle),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _c(PropertyField.name),
              autofocus: !_editing,
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
              controller: _c(PropertyField.processNumber),
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
            const SizedBox(height: 8),
            _Section(
              title: l10n.sectionLocation,
              children: [
                text(
                  'distrito',
                  l10n.fieldDistrito,
                  onChanged: locationEdited,
                  helper: _locationAuto ? l10n.locationAutoHint : null,
                ),
                text('concelho', l10n.fieldConcelho, onChanged: locationEdited),
                text(
                  'freguesia',
                  l10n.fieldFreguesia,
                  onChanged: locationEdited,
                ),
                text(PropertyField.placeName, l10n.fieldPlaceName),
              ],
            ),
            _Section(
              title: l10n.sectionRegistry,
              children: [
                text(PropertyField.matrixArticle, l10n.fieldMatrixArticle),
                text(PropertyField.matrixParish, l10n.fieldMatrixParish),
                text(
                  PropertyField.registryDescription,
                  l10n.fieldRegistryDescription,
                ),
                text(
                  PropertyField.cadastralSection,
                  l10n.fieldCadastralSection,
                ),
              ],
            ),
            _Section(
              title: l10n.sectionConfrontations,
              children: [
                text('n', l10n.fieldNorth),
                text('s', l10n.fieldSouth),
                text('e', l10n.fieldEast),
                text('w', l10n.fieldWest),
              ],
            ),
            _Section(
              title: l10n.sectionOwners,
              children: [
                for (final (i, (name, share)) in _owners.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: name,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: l10n.fieldOwnerName,
                            ),
                            validator: (value) => maxLength(value, 80),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: share,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: l10n.fieldOwnerShare,
                            ),
                            validator: (value) =>
                                (value ?? '').trim().isEmpty ||
                                    _parseShare(value!) != null
                                ? null
                                : l10n.ownerShareInvalid,
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.actionRemoveOwner,
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                            final (n, s) = _owners.removeAt(i);
                            n.dispose();
                            s.dispose();
                          }),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _owners.add((
                        TextEditingController(),
                        TextEditingController(),
                      )),
                    ),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(l10n.actionAddOwner),
                  ),
                ),
              ],
            ),
            _Section(
              title: l10n.sectionOther,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.fieldAcquiredOn),
                  subtitle: Text(
                    date == null
                        ? l10n.noValue
                        : MaterialLocalizations.of(context)
                              .formatCompactDate(date),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (date != null)
                        IconButton(
                          tooltip: l10n.actionClearDate,
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _acquiredOn = null),
                        ),
                      IconButton(
                        tooltip: l10n.actionPickDate,
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date ?? DateTime.now(),
                            firstDate: DateTime(1800),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => _acquiredOn = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                text(PropertyField.notes, l10n.fieldNotes, maxLines: 6),
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
            child: Text(_editing ? l10n.actionSave : l10n.actionSaveProperty),
          ),
        ),
      ),
    );
  }
}

/// A collapsed-by-default group of optional fields (SPEC.md §4.1).
class _Section extends StatelessWidget {
  const new({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(title),
    tilePadding: EdgeInsets.zero,
    childrenPadding: const EdgeInsets.only(top: 8),
    // Keep fields alive when collapsed so their values are still saved.
    maintainState: true,
    children: children,
  );
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
