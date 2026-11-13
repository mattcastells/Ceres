import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/dates.dart';
import '../../../domain/calculations/meal_title.dart';
import '../../../domain/enums/enums.dart';
import '../../../domain/models/meal.dart';

const _uuid = Uuid();

/// Borrador de `/meal/new` y de la revisión de IA.
///
/// El borrador sobrevive a la navegación al buscador de alimentos y se
/// persistiría en `drafts` con vencimiento a las 48 h (13-state §2).
class MealDraft {
  const MealDraft({
    required this.id,
    required this.slot,
    required this.date,
    required this.eatenAt,
    required this.items,
    required this.source,
    this.name,
    this.editingMealId,
    this.photoPath,
    this.aiAnalysisId,
  });

  final String id;
  final MealSlot slot;
  final DateTime date;
  final DateTime eatenAt;
  final List<MealItem> items;
  final MealSource source;

  /// El título que escribió la persona, o el que propuso la IA. `null` mientras
  /// nadie tocó nada: ahí el título sale de los ítems ([autoTitle]).
  final String? name;
  final String? editingMealId;
  final String? photoPath;
  final String? aiAnalysisId;

  /// El resumen que se guardaría si nadie escribe un título.
  String get autoTitle => MealTitle.fromItems(items);

  /// Lo que se muestra como título de la comida en cualquier pantalla.
  String get displayTitle {
    final custom = name?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final derived = autoTitle;
    return derived.isEmpty ? slot.label : derived;
  }

  int get totalKcal => items.fold(0, (acc, i) => acc + i.kcal);
  double get proteinG => items.fold(0.0, (acc, i) => acc + i.proteinG);
  double get carbsG => items.fold(0.0, (acc, i) => acc + i.carbsG);
  double get fatG => items.fold(0.0, (acc, i) => acc + i.fatG);

  bool get isEmpty => items.isEmpty;

  MealDraft copyWith({
    MealSlot? slot,
    DateTime? date,
    DateTime? eatenAt,
    List<MealItem>? items,
    MealSource? source,
    String? photoPath,
    String? aiAnalysisId,
  }) => MealDraft(
    id: id,
    slot: slot ?? this.slot,
    date: date ?? this.date,
    eatenAt: eatenAt ?? this.eatenAt,
    items: items ?? this.items,
    source: source ?? this.source,
    name: name,
    editingMealId: editingMealId,
    photoPath: photoPath ?? this.photoPath,
    aiAnalysisId: aiAnalysisId ?? this.aiAnalysisId,
  );

  Meal toMeal({required SyncStatus syncStatus, DateTime? createdAt}) => Meal(
    id: editingMealId ?? id,
    slot: slot,
    eatenAt: eatenAt,
    localDate: dateOnly(date),
    // Solo se guarda el título si alguien lo eligió: lo escribió la persona o
    // lo propuso la IA. El resumen de los ítems **no** se congela acá a
    // propósito — si se guardara, agregarle un ítem a la comida dejaría el
    // nombre viejo para siempre, que es la misma clase de bug que se está
    // arreglando. Sin nombre, `Meal.title` lo deriva al leer y siempre
    // describe lo que la comida tiene hoy.
    name: name?.trim().isEmpty ?? true ? null : name!.trim(),
    items: <MealItem>[
      for (var i = 0; i < items.length; i++) items[i].copyWith(position: i),
    ],
    source: source,
    photoPath: photoPath,
    aiAnalysisId: aiAnalysisId,
    syncStatus: syncStatus,
    createdAt: createdAt ?? DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

class MealDraftController extends Notifier<MealDraft?> {
  @override
  MealDraft? build() => null;

  void start({
    required MealSlot slot,
    required DateTime date,
    MealSource source = MealSource.manual,
    String? name,
    String? photoPath,
    String? aiAnalysisId,
    List<MealItem> items = const <MealItem>[],
  }) {
    final now = DateTime.now();
    state = MealDraft(
      id: _uuid.v4(),
      slot: slot,
      date: date,
      eatenAt: DateTime(
        date.year,
        date.month,
        date.day,
        now.hour,
        now.minute,
      ),
      items: items,
      source: source,
      name: name,
      photoPath: photoPath,
      aiAnalysisId: aiAnalysisId,
    );
  }

  void edit(Meal meal) {
    state = MealDraft(
      id: meal.id,
      slot: meal.slot,
      date: meal.localDate,
      eatenAt: meal.eatenAt,
      items: meal.items,
      source: meal.source,
      // El nombre viajaba perdido: editar una comida con título propio la
      // guardaba de vuelta sin él, así que corregir un gramo le borraba el
      // nombre a la comida.
      name: meal.name,
      editingMealId: meal.id,
      photoPath: meal.photoPath,
      aiAnalysisId: meal.aiAnalysisId,
    );
  }

  /// El título que escribió la persona. Vacío lo borra y devuelve la comida al
  /// resumen automático.
  void setName(String value) {
    final current = state;
    if (current == null) return;
    final clean = value.trim();
    state = MealDraft(
      id: current.id,
      slot: current.slot,
      date: current.date,
      eatenAt: current.eatenAt,
      items: current.items,
      source: current.source,
      name: clean.isEmpty ? null : clean,
      editingMealId: current.editingMealId,
      photoPath: current.photoPath,
      aiAnalysisId: current.aiAnalysisId,
    );
  }

  void addItem(MealItem item) {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(items: <MealItem>[...draft.items, item]);
  }

  /// Suma a la comida abierta lo que estimó la IA, sin tirar lo que ya había.
  ///
  /// Es lo que hace falta cuando el análisis se pide **desde** una comida a
  /// medio armar: empezar un borrador nuevo ahí borraría los ítems ya cargados
  /// sin decirlo. Si no hay ninguno abierto no hace nada y quien llama arranca
  /// uno con `start`.
  ///
  /// El `source` pasa a ser el del análisis aunque la comida tenga ítems
  /// cargados a mano. Es a propósito: marcarla como manual diría que ninguno de
  /// sus números es una estimación, y eso sería falso. Ante la duda se marca
  /// como estimada, que es el lado que no engaña. La procedencia fina está por
  /// ítem, en `MealItem.aiConfidence`.
  void appendAnalysis({
    required MealSource source,
    required List<MealItem> items,
    String? photoPath,
    String? aiAnalysisId,
  }) {
    final current = state;
    if (current == null) return;
    state = MealDraft(
      id: current.id,
      slot: current.slot,
      date: current.date,
      eatenAt: current.eatenAt,
      items: <MealItem>[...current.items, ...items],
      source: source,
      // El título del análisis **no** pisa al de la comida abierta: acá lo
      // estimado se suma a algo que ya existe, y el nombre describiría solo la
      // mitad que trajo la IA.
      name: current.name,
      editingMealId: current.editingMealId,
      photoPath: photoPath ?? current.photoPath,
      aiAnalysisId: aiAnalysisId ?? current.aiAnalysisId,
    );
  }

  /// Suma al plato uno o más ítems estimados desde el campo "Sumar un ítem".
  ///
  /// Se parece a [appendAnalysis] y difiere en lo que importa: acá se agrega
  /// **un ítem más** a un plato que ya tiene identidad, así que no se pisa lo
  /// que el plato ya dice de sí mismo.
  ///
  /// - El origen pasa a "estimado por texto" solo si el plato no tenía ningún
  ///   número estimado (`manual`, código de barras, duplicado): con un ítem
  ///   estimado adentro ya no es cierto que ninguno lo sea. Si el plato salió
  ///   de una foto, sigue siendo de foto — es lo que dice que hay una imagen
  ///   que volver a mirar al recalcular.
  /// - El vínculo con el análisis se conserva si ya había uno: es el del plato
  ///   entero, y el de una feta de queso no lo describe.
  ///
  /// Devuelve `false` si no hay borrador abierto o si el abierto ya no es
  /// [draftId]: la respuesta llegó tarde, después de cerrar esa comida, y
  /// sumarla a otra sería meterle un ítem a un plato que nadie tocó.
  bool appendEstimatedItems({
    required String draftId,
    required List<MealItem> items,
    String? aiAnalysisId,
  }) {
    final current = state;
    if (current == null || current.id != draftId || items.isEmpty) {
      return false;
    }
    state = MealDraft(
      id: current.id,
      slot: current.slot,
      date: current.date,
      eatenAt: current.eatenAt,
      items: <MealItem>[...current.items, ...items],
      source: current.source.isAi ? current.source : MealSource.aiText,
      name: current.name,
      editingMealId: current.editingMealId,
      photoPath: current.photoPath,
      aiAnalysisId: current.aiAnalysisId ?? aiAnalysisId,
    );
    return true;
  }

  /// Reemplaza los ítems por los que devolvió un recálculo.
  ///
  /// Al revés que [appendAnalysis], que suma: el recálculo devuelve la comida
  /// **entera** ya corregida —lo que la corrección no toca vuelve igual—, así
  /// que sumarla dejaría todo por duplicado. La identidad de la comida no se
  /// toca: mismo id, mismo momento del día y misma fecha, porque lo que se
  /// está corrigiendo son los números, no la comida.
  void replaceAnalysis({
    required MealSource source,
    required List<MealItem> items,
    String? photoPath,
    String? aiAnalysisId,
  }) {
    final current = state;
    if (current == null) return;
    state = MealDraft(
      id: current.id,
      slot: current.slot,
      date: current.date,
      eatenAt: current.eatenAt,
      items: <MealItem>[
        for (var i = 0; i < items.length; i++) items[i].copyWith(position: i),
      ],
      source: source,
      name: current.name,
      editingMealId: current.editingMealId,
      photoPath: photoPath ?? current.photoPath,
      aiAnalysisId: aiAnalysisId ?? current.aiAnalysisId,
    );
  }

  /// Devuelve el borrador a un estado anterior, o lo cierra si no había ninguno.
  ///
  /// Se usa al descartar un análisis: quien lo abrió puede haber estado armando
  /// una comida, y cerrar la revisión tiene que dejarla como estaba.
  void restore(MealDraft? previous) => state = previous;

  void replaceItem(int index, MealItem item) {
    final draft = state;
    if (draft == null) return;
    final items = <MealItem>[...draft.items];
    items[index] = item;
    state = draft.copyWith(items: items);
  }

  void removeItem(String itemId) {
    final draft = state;
    if (draft == null) return;
    state = draft.copyWith(
      items: draft.items.where((i) => i.id != itemId).toList(),
    );
  }

  /// Adjunta o quita la foto.
  ///
  /// No usa `copyWith`: ese resuelve el null como "no cambies", así que por ahí
  /// no habría forma de sacar una foto ya puesta.
  void setPhoto(String? path) {
    final current = state;
    if (current == null) return;
    state = MealDraft(
      id: current.id,
      slot: current.slot,
      date: current.date,
      eatenAt: current.eatenAt,
      items: current.items,
      source: current.source,
      name: current.name,
      editingMealId: current.editingMealId,
      photoPath: path,
      aiAnalysisId: current.aiAnalysisId,
    );
  }

  void setSlot(MealSlot slot) => state = state?.copyWith(slot: slot);

  void setEatenAt(DateTime value) => state = state?.copyWith(eatenAt: value);

  void clear() => state = null;
}

final mealDraftProvider = NotifierProvider<MealDraftController, MealDraft?>(
  MealDraftController.new,
);
