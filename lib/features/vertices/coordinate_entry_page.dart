import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/core/crs/coordinates.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';
import 'package:terrenos/core/geometry/geodesy.dart';
import 'package:terrenos/core/model/vertex.dart';
import 'package:terrenos/core/settings/app_settings.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// A typed vertex position, with the input kept exactly as typed.
typedef TypedCoordinate = ({LonLat position, CoordinateInput input});

/// Typing one vertex's coordinates (VTX-3, SPEC.md §4.1, §7.5): a format
/// selector, two separate fields, a ± button, inline errors and the
/// sign/swap suggestions. Returns a [TypedCoordinate] when saved.
class CoordinateEntryPage extends ConsumerStatefulWidget {
  const new({this.initial, this.title, super.key});

  /// The vertex being edited, if any.
  final Vertex? initial;

  /// Overrides the default "Add vertex" / "Edit coordinates" title.
  final String? title;

  static Future<TypedCoordinate?> open(
    BuildContext context, {
    Vertex? vertex,
    String? title,
  }) => Navigator.of(context).push<TypedCoordinate>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CoordinateEntryPage(initial: vertex, title: title),
    ),
  );

  @override
  ConsumerState<CoordinateEntryPage> createState() =>
      _CoordinateEntryPageState();
}

class _CoordinateEntryPageState extends ConsumerState<CoordinateEntryPage> {
  late CoordinateFormat _format = ref.read(settingsProvider).coordinateFormat;
  final _first = TextEditingController();
  final _second = TextEditingController();
  var _submitted = false;

  @override
  void initState() {
    super.initState();
    _fill();
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  String get _language => Localizations.localeOf(context).languageCode;

  /// Shows the vertex being edited in the current format, using the typed
  /// values when they were typed in this format.
  void _fill() {
    final v = widget.initial;
    if (v == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final language = _language;
      final (a, b) = switch (_format) {
        CoordinateFormat.decimalDegrees => (
          formatDecimalDegrees(v.lat, language),
          formatDecimalDegrees(v.lon, language),
        ),
        CoordinateFormat.degreesMinutesSeconds => (
          formatDms(v.lat, CoordinateAxis.latitude, language),
          formatDms(v.lon, CoordinateAxis.longitude, language),
        ),
        CoordinateFormat.ptTm06 => () {
          final typed = v.input?.crs == PtTm06.epsg ? v.input : null;
          final pt = typed != null
              ? (m: typed.x, p: typed.y)
              : PtTm06.fromLatLon(v.lat, v.lon);
          return (
            formatMetres(pt.m, language, grouping: false),
            formatMetres(pt.p, language, grouping: false),
          );
        }(),
      };
      _first.text = a;
      _second.text = b;
      setState(() {});
    });
  }

  Parsed _parse(String text, CoordinateAxis axis) => switch (_format) {
    CoordinateFormat.decimalDegrees => parseDecimalDegrees(text, axis),
    CoordinateFormat.degreesMinutesSeconds => parseDms(text, axis),
    CoordinateFormat.ptTm06 => parseNumber(text),
  };

  Parsed get _a => _parse(_first.text, CoordinateAxis.latitude);
  Parsed get _b => _parse(_second.text, CoordinateAxis.longitude);

  CoordinateSystem get _system => _format == CoordinateFormat.ptTm06
      ? CoordinateSystem.ptTm06
      : CoordinateSystem.wgs84;

  /// The typed values as (first, second) in the format's own system:
  /// (lat, lon) or (M, P), rounded to the stored precision.
  (double, double) get _values => _format == CoordinateFormat.ptTm06
      ? (roundMetres(_a.value!), roundMetres(_b.value!))
      : (roundDegrees(_a.value!), roundDegrees(_b.value!));

  void _save() {
    setState(() => _submitted = true);
    if (!_a.isValid || !_b.isValid) return;
    final (first, second) = _values;
    final check = checkPair(_system, first, second);
    final input = _format == CoordinateFormat.ptTm06
        ? CoordinateInput(crs: PtTm06.epsg, x: first, y: second)
        : CoordinateInput(crs: 'EPSG:4326', x: second, y: first);
    Navigator.of(context).pop<TypedCoordinate>((
      position: (lon: check.lon, lat: check.lat),
      input: input,
    ));
  }

  void _toggleSign(TextEditingController controller) {
    final text = controller.text.trim();
    controller.text = text.startsWith('-') || text.startsWith('−')
        ? text.substring(1)
        : '-$text';
    setState(() {});
  }

  String? _errorText(Parsed parsed, String text, AppLocalizations l10n) {
    if (parsed.isValid || (!_submitted && text.trim().isEmpty)) return null;
    return switch (parsed.error!) {
      CoordinateError.empty => l10n.coordinateErrorEmpty,
      CoordinateError.notANumber => l10n.coordinateErrorNumber,
      CoordinateError.outOfRange => l10n.coordinateErrorRange,
      CoordinateError.minutesOrSecondsTooLarge => l10n.coordinateErrorMinutes,
      CoordinateError.wrongHemisphere => l10n.coordinateErrorHemisphere,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = _language;
    final numeric = _format != CoordinateFormat.degreesMinutesSeconds;
    final (firstLabel, secondLabel) = _format == CoordinateFormat.ptTm06
        ? (l10n.fieldM, l10n.fieldP)
        : (l10n.fieldLatitude, l10n.fieldLongitude);
    final (firstHint, secondHint) = switch (_format) {
      CoordinateFormat.decimalDegrees => (
        formatDecimalDegrees(41.15835, language),
        formatDecimalDegrees(-8.6285, language),
      ),
      CoordinateFormat.degreesMinutesSeconds => (
        formatDms(41.15835, CoordinateAxis.latitude, language),
        formatDms(-8.6285, CoordinateAxis.longitude, language),
      ),
      CoordinateFormat.ptTm06 => (
        formatMetres(-41234.56, language, grouping: false),
        formatMetres(164321.78, language, grouping: false),
      ),
    };

    final a = _a;
    final b = _b;
    final check = a.isValid && b.isValid
        ? checkPair(_system, _values.$1, _values.$2)
        : null;

    Widget field(
      TextEditingController controller,
      String label,
      String hint,
      Parsed parsed,
    ) => TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(signed: true, decimal: true)
          : TextInputType.text,
      inputFormatters: [
        if (numeric) FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-−+ ]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: _errorText(parsed, controller.text, l10n),
        // Many Android number keyboards have no minus key (§4.1).
        suffixIcon: numeric
            ? IconButton(
                tooltip: l10n.toggleSign,
                icon: const Text('±', style: TextStyle(fontSize: 22)),
                onPressed: () => _toggleSign(controller),
              )
            : null,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _save(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title ??
              (widget.initial == null
                  ? l10n.vertexAddTitle
                  : l10n.vertexEditTitle),
        ),
        actions: [TextButton(onPressed: _save, child: Text(l10n.actionSave))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<CoordinateFormat>(
            segments: [
              ButtonSegment(
                value: CoordinateFormat.decimalDegrees,
                label: Text(l10n.formatDecimalShort),
              ),
              ButtonSegment(
                value: CoordinateFormat.degreesMinutesSeconds,
                label: Text(l10n.formatDmsShort),
              ),
              ButtonSegment(
                value: CoordinateFormat.ptTm06,
                label: Text(l10n.formatPtTm06Short),
              ),
            ],
            selected: {_format},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              setState(() {
                _format = selection.single;
                _first.clear();
                _second.clear();
                _submitted = false;
              });
              _fill();
            },
          ),
          const SizedBox(height: 24),
          field(_first, firstLabel, firstHint, a),
          const SizedBox(height: 16),
          field(_second, secondLabel, secondHint, b),
          const SizedBox(height: 16),
          if (check != null && check.outsidePortugal)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.coordinateOutsidePortugal),
                    if (check.suggestNegativeLongitude)
                      TextButton(
                        onPressed: () => _toggleSign(_second),
                        child: Text(
                          l10n.coordinateSuggestNegative(
                            formatDecimalDegrees(-_values.$2, language),
                          ),
                        ),
                      ),
                    if (check.suggestSwap)
                      TextButton(
                        onPressed: () => setState(() {
                          final text = _first.text;
                          _first.text = _second.text;
                          _second.text = text;
                        }),
                        child: Text(l10n.coordinateSuggestSwap),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.coordinateOnlySystems,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
