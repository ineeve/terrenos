import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:terrenos/app/providers.dart';
import 'package:terrenos/app/router.dart';
import 'package:terrenos/core/device/device_identity.dart';
import 'package:terrenos/l10n/gen/app_localizations.dart';

/// Validates a device name; returns an error message or `null`.
String? validateDeviceName(String? value, AppLocalizations l10n) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return l10n.deviceNameRequired;
  if (name.length > DeviceIdentity.maxNameLength) {
    return l10n.deviceNameTooLong(DeviceIdentity.maxNameLength);
  }
  return null;
}

/// First-run step 2: the name other group members will see (SET-1).
class DeviceNamePage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<DeviceNamePage> createState() => _DeviceNamePageState();
}

class _DeviceNamePageState extends ConsumerState<DeviceNamePage> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(
    text: ref.read(deviceProvider).displayName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(deviceProvider.notifier).rename(_controller.text);
    if (mounted) await context.push(Routes.welcomeIntro);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l10n.deviceNameTitle,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              Text(l10n.deviceNameExplanation),
              const SizedBox(height: 24),
              TextFormField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.deviceNameLabel,
                  hintText: l10n.deviceNameHint,
                ),
                validator: (value) => validateDeviceName(value, l10n),
                onFieldSubmitted: (_) => _continue(),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _continue,
                child: Text(l10n.actionContinue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
