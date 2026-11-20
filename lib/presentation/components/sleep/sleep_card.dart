import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/nm_theme.dart';
import '../../../core/theme/text_styles.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/phosphor_icons.dart';
import '../../providers/app_providers.dart';
import '../../screens/sleep/sleep_sheet.dart';
import '../system/surfaces.dart';

/// El sueño del día en Inicio. Si no hay registro, invita a cargarlo.
class SleepCard extends ConsumerWidget {
  const SleepCard({required this.date, super.key});

  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nm = context.nm;
    ref.watch(appRevisionProvider);
    final sleep = ref.watch(repositoryProvider).sleepOn(date);

    return NmCard(
      padding: const EdgeInsets.symmetric(vertical: NmSpace.s1),
      child: NmListRow(
        title: 'Sueño',
        subtitle: sleep == null
            ? null
            : '${sleep.label} · ${sleep.quality.label}',
        leading: Icon(PhosphorIcons.moon(), size: 20, color: nm.info),
        trailing: Text(
          sleep == null ? 'Cargar' : 'Editar',
          style: NmTextStyles.from(NmType.bodySm, color: nm.accent),
        ),
        onTap: () => showSleepSheet(context, date: date),
      ),
    );
  }
}
