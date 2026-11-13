import '../../core/utils/dates.dart';
import '../calculations/meal_title.dart';
import '../enums/enums.dart';
import 'ai_analysis.dart';

/// Un ítem dentro de una comida. El nombre es un **snapshot**: no cambia si el
/// alimento de origen se edita después (10-types §MealItem).
class MealItem {
  const MealItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.position,
    this.foodId,
    this.aiConfidence,
    this.wasAiCorrected = false,
  });

  final String id;
  final String? foodId;
  final String name;
  final double quantity;
  final String unit;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// 0–1 cuando el ítem viene de un análisis de foto.
  final double? aiConfidence;
  final bool wasAiCorrected;
  final int position;

  /// "150 g" · "1 taza" · "2 porciones".
  String get portionLabel {
    final q = quantity == quantity.roundToDouble()
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(1).replaceAll('.', ',');
    return '$q ${unitLabel(unit, quantity)}';
  }

  /// La unidad como se lee. El valor guardado es el del contrato con el
  /// servidor (`porcion`, `unidad`, sin tilde ni plural): se traduce solo al
  /// mostrarlo, así no cambia lo que viaja ni lo que ya está en la base.
  static String unitLabel(String unit, double quantity) {
    final plural = quantity != 1;
    return switch (unit) {
      'porcion' => plural ? 'porciones' : 'porción',
      'unidad' => plural ? 'unidades' : 'unidad',
      'taza' => plural ? 'tazas' : 'taza',
      'cucharada' => plural ? 'cucharadas' : 'cucharada',
      'rebanada' => plural ? 'rebanadas' : 'rebanada',
      _ => unit,
    };
  }

  MealItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    int? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    int? position,
    bool? wasAiCorrected,
  }) => MealItem(
    id: id,
    foodId: foodId,
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    aiConfidence: aiConfidence,
    wasAiCorrected: wasAiCorrected ?? this.wasAiCorrected,
    position: position ?? this.position,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'foodId': foodId,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'aiConfidence': aiConfidence,
    'wasAiCorrected': wasAiCorrected,
    'position': position,
  };

  /// Un ítem estimado por la IA, listo para entrar en una comida.
  ///
  /// Se conserva [AiAnalysisItem.confidence] en [aiConfidence] y ahí está todo
  /// el asunto: es lo que distingue un número estimado de uno del catálogo, y
  /// lo que hace que el badge de confianza diga la verdad. Lo usan la revisión
  /// del análisis y el recálculo, que tienen que convertir igual.
  static MealItem fromAnalysis(
    AiAnalysisItem item, {
    required String id,
    required int position,
  }) => MealItem(
    id: id,
    name: item.name,
    quantity: item.quantity,
    unit: item.unit,
    kcal: item.kcal,
    proteinG: item.proteinG,
    carbsG: item.carbsG,
    fatG: item.fatG,
    aiConfidence: item.confidence,
    position: position,
  );

  static MealItem fromJson(Map<String, dynamic> j) => MealItem(
    id: j['id'] as String,
    foodId: j['foodId'] as String?,
    name: j['name'] as String,
    quantity: (j['quantity'] as num).toDouble(),
    unit: j['unit'] as String,
    kcal: j['kcal'] as int,
    proteinG: (j['proteinG'] as num).toDouble(),
    carbsG: (j['carbsG'] as num).toDouble(),
    fatG: (j['fatG'] as num).toDouble(),
    aiConfidence: (j['aiConfidence'] as num?)?.toDouble(),
    wasAiCorrected: j['wasAiCorrected'] as bool? ?? false,
    position: j['position'] as int,
  );
}

/// Una comida de un slot del día (10-types §Meal).
///
/// Los totales están desnormalizados (D-11): se recalculan al editar y son la
/// única lectura que necesita Inicio.
class Meal {
  const Meal({
    required this.id,
    required this.slot,
    required this.eatenAt,
    required this.localDate,
    required this.items,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.name,
    this.aiAnalysisId,
    this.photoPath,
    this.notes,
    this.isFavorite = false,
    this.syncStatus = SyncStatus.synced,
    this.deletedAt,
  });

  final String id;
  final MealSlot slot;

  /// Cuándo se **comió**, en hora local.
  ///
  /// Se llamaba `loggedAt` y el nombre mentía desde que el formulario tiene el
  /// botón "Cambiar hora": el valor se arma con la fecha elegida más la hora
  /// elegida, no con `DateTime.now()`, y editar una comida lo conserva. Con el
  /// nombre viejo, la hora de la comida —el insumo de la ventana de
  /// alimentación y de los horarios— parecía un dato de auditoría, y por eso no
  /// la usó nunca ninguna pantalla de análisis.
  ///
  /// El resto de los modelos se quedan con `loggedAt` y hacen bien: en el
  /// sueño, el peso y el alcohol ese campo sí es cuándo se registró.
  final DateTime eatenAt;

  final DateTime localDate;
  final String? name;
  final List<MealItem> items;
  final MealSource source;
  final String? aiAnalysisId;
  final String? photoPath;
  final String? notes;
  final bool isFavorite;
  final SyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  /// Se redondea por ítem y luego se suman los redondeados, para que la suma
  /// visible coincida con el total visible (§6).
  int get totalKcal => items.fold(0, (acc, i) => acc + i.kcal);
  double get totalProteinG => items.fold(0.0, (acc, i) => acc + i.proteinG);
  double get totalCarbsG => items.fold(0.0, (acc, i) => acc + i.carbsG);
  double get totalFatG => items.fold(0.0, (acc, i) => acc + i.fatG);

  bool get isDeleted => deletedAt != null;

  /// Cómo se llama esta comida en una lista: el nombre que le pusieron, o un
  /// resumen de sus ítems ("Milanesa y puré", "Milanesa, puré y 2 más").
  ///
  /// Antes esto era `items.first.name` y por eso una comida se llamaba como el
  /// primer ingrediente que se hubiera cargado. La regla del resumen vive en
  /// [MealTitle] porque la comparte la proyección que ven los pals.
  String get title {
    final custom = name?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final derived = MealTitle.fromItems(items);
    return derived.isEmpty ? slot.label : derived;
  }

  DataOrigin get origin =>
      source.isAi ? DataOrigin.ai : DataOrigin.manual;

  Meal copyWith({
    MealSlot? slot,
    DateTime? eatenAt,
    DateTime? localDate,
    String? name,
    List<MealItem>? items,
    MealSource? source,
    String? aiAnalysisId,
    String? photoPath,
    String? notes,
    bool? isFavorite,
    SyncStatus? syncStatus,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    bool clearPhotoPath = false,
  }) => Meal(
    id: id,
    slot: slot ?? this.slot,
    eatenAt: eatenAt ?? this.eatenAt,
    localDate: localDate ?? this.localDate,
    // Sin `clearName`: borrar el título es guardar la comida entera de nuevo
    // desde el formulario, y ahí `MealDraft.toMeal` la construye con `name` en
    // null. Un parámetro que nadie usa sugiere que hay otro camino.
    name: name ?? this.name,
    items: items ?? this.items,
    source: source ?? this.source,
    aiAnalysisId: aiAnalysisId ?? this.aiAnalysisId,
    photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
    notes: notes ?? this.notes,
    isFavorite: isFavorite ?? this.isFavorite,
    syncStatus: syncStatus ?? this.syncStatus,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
    deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'slot': slot.wire,
    'eatenAt': eatenAt.toIso8601String(),
    'localDate': isoDate(localDate),
    'name': name,
    'items': items.map((i) => i.toJson()).toList(),
    'source': source.wire,
    'aiAnalysisId': aiAnalysisId,
    'photoPath': photoPath,
    'notes': notes,
    'isFavorite': isFavorite,
    'syncStatus': syncStatus.wire,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static Meal fromJson(Map<String, dynamic> j) => Meal(
    id: j['id'] as String,
    slot: MealSlot.fromWire(j['slot'] as String),
    // `loggedAt` es el nombre viejo del mismo valor: un documento guardado
    // antes del cambio lo trae así, y sin este `??` una comida vieja se
    // quedaría sin hora al abrir la app actualizada.
    eatenAt: DateTime.parse((j['eatenAt'] ?? j['loggedAt']) as String),
    localDate: DateTime.parse(j['localDate'] as String),
    name: j['name'] as String?,
    items: (j['items'] as List<dynamic>)
        .map((e) => MealItem.fromJson(e as Map<String, dynamic>))
        .toList(),
    source: MealSource.values.firstWhere(
      (e) => e.wire == j['source'],
      orElse: () => MealSource.manual,
    ),
    aiAnalysisId: j['aiAnalysisId'] as String?,
    photoPath: j['photoPath'] as String?,
    notes: j['notes'] as String?,
    isFavorite: j['isFavorite'] as bool? ?? false,
    syncStatus: SyncStatus.values.firstWhere(
      (e) => e.wire == j['syncStatus'],
      orElse: () => SyncStatus.synced,
    ),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    deletedAt: j['deletedAt'] == null
        ? null
        : DateTime.parse(j['deletedAt'] as String),
  );
}
