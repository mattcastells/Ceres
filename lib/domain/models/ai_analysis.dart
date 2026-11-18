import '../enums/enums.dart';

/// Un ítem propuesto por el análisis de foto.
class AiAnalysisItem {
  const AiAnalysisItem({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.confidence,
  });

  final String name;
  final double quantity;
  final String unit;
  final int kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// 0–1. alta ≥ 0,75 · media 0,5–0,75 · baja < 0,5 (F-06).
  final double confidence;

  AiAnalysisItem copyWith({
    String? name,
    double? quantity,
    String? unit,
    int? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) => AiAnalysisItem(
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    confidence: confidence,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'confidence': confidence,
  };

  static AiAnalysisItem fromJson(Map<String, dynamic> j) => AiAnalysisItem(
    name: j['name'] as String,
    quantity: (j['quantity'] as num).toDouble(),
    unit: j['unit'] as String,
    kcal: j['kcal'] as int,
    proteinG: (j['proteinG'] as num).toDouble(),
    carbsG: (j['carbsG'] as num).toDouble(),
    fatG: (j['fatG'] as num).toDouble(),
    confidence: (j['confidence'] as num).toDouble(),
  );
}


/// Resultado del análisis de una foto (F-05).
class AiAnalysis {
  const AiAnalysis({
    required this.id,
    required this.photoPath,
    required this.status,
    required this.model,
    required this.promptVersion,
    required this.items,
    required this.latencyMs,
    required this.createdAt,
    this.title,
    this.errorCode,
    this.corrections,
  });

  final String id;

  /// `null` cuando la estimación salió de una descripción escrita: no hay
  /// imagen que adjuntar ni que mostrar.
  final String? photoPath;

  /// Cómo llamaría al plato quien lo miró: "Milanesa con puré", no el primer
  /// ingrediente de la lista. Puede venir vacío —modelo viejo, respuesta sin el
  /// campo— y entonces el título lo arma la app con `MealTitle`.
  final String? title;
  final AiAnalysisStatus status;
  final String model;
  final String promptVersion;
  final List<AiAnalysisItem> items;
  final int latencyMs;
  final String? errorCode;
  final AiCorrections? corrections;
  final DateTime createdAt;

  double get confidenceAvg => items.isEmpty
      ? 0
      : items.fold<double>(0, (acc, i) => acc + i.confidence) / items.length;

  int get totalKcal => items.fold(0, (acc, i) => acc + i.kcal);

  /// ≥ 1 ítem con confianza < 0,5 activa el estado `low_confidence` (S-20).
  bool get hasLowConfidenceItem => items.any((i) => i.confidence < 0.5);

  AiAnalysis copyWith({
    AiAnalysisStatus? status,
    List<AiAnalysisItem>? items,
    AiCorrections? corrections,
    String? photoPath,
    String? title,
  }) => AiAnalysis(
    id: id,
    photoPath: photoPath ?? this.photoPath,
    title: title ?? this.title,
    status: status ?? this.status,
    model: model,
    promptVersion: promptVersion,
    items: items ?? this.items,
    latencyMs: latencyMs,
    errorCode: errorCode,
    corrections: corrections ?? this.corrections,
    createdAt: createdAt,
  );
}

/// Diff entre lo propuesto y lo guardado — insumo para mejorar el prompt.
class AiCorrections {
  const AiCorrections({
    required this.itemsEdited,
    required this.itemsRemoved,
    required this.itemsAdded,
    required this.kcalDelta,
  });

  final int itemsEdited;
  final int itemsRemoved;
  final int itemsAdded;
  final int kcalDelta;

  bool get isEmpty =>
      itemsEdited == 0 && itemsRemoved == 0 && itemsAdded == 0 && kcalDelta == 0;
}
