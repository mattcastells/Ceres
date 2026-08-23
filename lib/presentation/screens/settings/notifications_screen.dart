import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/models/reminder.dart';
import '../../components/system/inputs.dart';
import '../../components/system/nm_screen.dart';
import '../../components/system/surfaces.dart';
import '../../providers/app_providers.dart';
import '../../providers/reminder_providers.dart';

/// Recordatorios: qué avisa la app y a qué hora.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.invalidate(notificationPermissionProvider),
    );
  }

  /// Guarda y reprograma. Las dos cosas juntas siempre: un cambio guardado que
  /// no se reprograma deja sonando el horario viejo.
  Future<void> _save(Reminder reminder) async {
    final repo = ref.read(repositoryProvider);
    await repo.saveReminder(reminder);
    await ref.read(reminderSchedulerProvider)?.apply(repo.reminders);
    if (mounted) setState(() {});
  }

  Future<void> _toggle(Reminder reminder, {required bool on}) async {
    if (on && !(ref.read(notificationPermissionProvider).valueOrNull ?? false)) {
      final granted =
          await ref.read(reminderSchedulerProvider)?.requestPermission() ??
          false;
      ref.invalidate(notificationPermissionProvider);
      if (!granted) return;
    }
    await _save(reminder.copyWith(enabled: on));
  }

  Future<void> _addTime(Reminder reminder) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
    );
    if (picked == null) return;
    await _save(
      reminder.withTimeAdded(ReminderTime(picked.hour, picked.minute)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheduler = ref.watch(reminderSchedulerProvider);
    final granted = ref.watch(notificationPermissionProvider).valueOrNull;
    final repo = ref.watch(repositoryProvider);

    if (scheduler == null) {
      return const NmScreen(
        title: 'Recordatorios',
        child: Padding(
          padding: EdgeInsets.only(top: NmSpace.s6),
          child: InfoNote(
            text: 'Este dispositivo no admite notificaciones.',
            tone: NmNoteTone.caution,
          ),
        ),
      );
    }

    return NmScreen(
      title: 'Recordatorios',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: NmSpace.s4),

          if (granted == false) ...<Widget>[
            InfoNote(
              text: 'Android tiene bloqueadas las notificaciones de Ceres.',
              tone: NmNoteTone.caution,
              action: 'Permitir',
              onAction: () async {
                await scheduler.requestPermission();
                ref.invalidate(notificationPermissionProvider);
              },
            ),
            const SizedBox(height: NmSpace.s4),
          ],

          for (final kind in ReminderKind.values) ...<Widget>[
            _ReminderCard(
              reminder: repo.reminderFor(kind),
              onToggle: (on) => _toggle(repo.reminderFor(kind), on: on),
              onAdd: () => _addTime(repo.reminderFor(kind)),
              onRemove: (time) =>
                  _save(repo.reminderFor(kind).withTimeRemoved(time)),
            ),
            const SizedBox(height: NmSpace.s6),
          ],
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.onToggle,
    required this.onAdd,
    required this.onRemove,
  });

  final Reminder reminder;
  final void Function(bool) onToggle;
  final VoidCallback onAdd;
  final void Function(ReminderTime) onRemove;

  @override
  Widget build(BuildContext context) {
    final nm = context.nm;

    return NmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          NmSwitchRow(
            title: reminder.kind.label,
            subtitle: reminder.kind.title,
            value: reminder.enabled,
            onChanged: onToggle,
          ),
          if (reminder.enabled) ...<Widget>[
            const NmDivider(),
            const SizedBox(height: NmSpace.s3),
            Wrap(
              spacing: NmSpace.s2,
              runSpacing: NmSpace.s2,
              children: <Widget>[
                for (final time in reminder.times)
                  // Tocar el horario lo saca: con pocos horarios, un menú por
                  // cada uno sería más estorbo que ayuda.
                  NmChip(
                    label: time.label,
                    selected: true,
                    onTap: () => onRemove(time),
                  ),
                if (reminder.times.length < Reminder.maxTimes)
                  NmChip(
                    label: '+ Agregar',
                    selected: false,
                    onTap: onAdd,
                  ),
              ],
            ),
            const SizedBox(height: NmSpace.s2),
            Text(
              reminder.times.isEmpty
                  ? 'Agregá al menos un horario.'
                  : 'Tocá un horario para sacarlo.',
              style: NmTextStyles.from(NmType.caption, color: nm.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
