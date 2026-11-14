/// Un permiso vigente sobre los datos propios, dado a un profesional.
///
/// Es lo que ve el dueño en su pantalla: a quién le dio acceso, a qué, y hasta
/// cuándo. Del otro lado —el backoffice— la misma fila se lee al revés, como
/// "a quién puedo seguir".
///
/// No hay un `status` acá. La app solo lista lo vigente: un permiso revocado
/// no es una cosa que la persona tenga que administrar, es una que ya no
/// existe. El historial queda en la base para poder auditarlo, no para
/// mostrarlo.
class CareGrant {
  const CareGrant({
    required this.id,
    required this.professionalId,
    required this.displayName,
    required this.shareMeals,
    required this.sharePhotos,
    required this.shareBody,
    required this.shareWellbeing,
    this.expiresAt,
  });

  final String id;
  final String professionalId;

  /// Vacío si la vista no lo devuelve. La pantalla sabe mostrar un permiso sin
  /// nombre, y quedarse sin la lista entera por un nombre que falta sería peor.
  final String displayName;

  final bool shareMeals;
  final bool sharePhotos;
  final bool shareBody;
  final bool shareWellbeing;

  /// Sin fecha, el permiso dura hasta que se revoque.
  final DateTime? expiresAt;

  static CareGrant fromRow(
    Map<String, dynamic> row, {
    required String displayName,
  }) => CareGrant(
    id: row['id'] as String,
    professionalId: row['professional_id'] as String,
    displayName: displayName,
    shareMeals: row['share_meals'] as bool? ?? false,
    sharePhotos: row['share_photos'] as bool? ?? false,
    shareBody: row['share_body'] as bool? ?? false,
    shareWellbeing: row['share_wellbeing'] as bool? ?? false,
    expiresAt: row['expires_at'] == null
        ? null
        : DateTime.tryParse(row['expires_at'] as String)?.toLocal(),
  );
}
