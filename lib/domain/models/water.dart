import '../../core/utils/dates.dart';
import '../enums/enums.dart';

/// Vasos de agua de un día. Uno por fecha: sumar o restar actualiza el mismo
/// registro, igual que el peso (D-16).
///
/// Se guarda el **conteo de vasos** y no mililitros porque es lo que la persona
/// realmente cuenta. El tamaño del vaso es una preferencia del perfil, así que
/// cambiarla no reescribe el historial: los 8 vasos de ayer siguen siendo 8.
class WaterLog {
  const WaterLog({
    required this.id,
    required this.localDate,
    required this.glasses,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
  });

  final String id;
  final DateTime localDate;
  final int glasses;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  /// Tope defensivo: 40 vasos son 10 litros. Más que eso es un error de tipeo
  /// o un botón que se disparó solo, no una persona tomando agua.
  static const int maxGlasses = 40;

  WaterLog copyWith({int? glasses, DateTime? updatedAt}) => WaterLog(
    id: id,
    localDate: localDate,
    glasses: (glasses ?? this.glasses).clamp(0, maxGlasses),
    updatedAt: updatedAt ?? this.updatedAt,
    syncStatus: SyncStatus.pending,
  );


  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'localDate': isoDate(localDate),
    'glasses': glasses,
    'updatedAt': updatedAt.toIso8601String(),
    'syncStatus': syncStatus.wire,
  };

  static WaterLog fromJson(Map<String, dynamic> j) => WaterLog(
    id: j['id'] as String,
    localDate: DateTime.parse(j['localDate'] as String),
    glasses: (j['glasses'] as num).toInt(),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.wire == j['syncStatus'],
      orElse: () => SyncStatus.pending,
    ),
  );
}
