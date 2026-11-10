/// Lo que la nutricionista le escribe a la persona desde el panel.
///
/// Dos clases, con vidas distintas:
///
/// - [CareFeedbackKind.feedback]: una devolución sobre un día, una comida o la
///   semana. Se lee y queda en la lista.
/// - [CareFeedbackKind.indication]: una indicación que **sigue vigente**
///   ("sumá proteína en el desayuno") mientras ella no la saque. Por eso se
///   muestra en Inicio aunque ya se haya leído.
///
/// La app solo recibe lo publicado y no borrado: un borrador es de quien lo
/// escribe, y eso lo decide RLS, no un filtro de acá.
enum CareFeedbackKind {
  feedback('feedback'),
  indication('indication');

  const CareFeedbackKind(this.wire);

  final String wire;

  /// Un tipo que esta versión no conoce se lee como devolución: es la clase
  /// que se lee y se archiva sola, así que un texto nuevo no queda clavado en
  /// Inicio para siempre.
  static CareFeedbackKind fromWire(Object? raw) =>
      raw == 'indication' ? indication : feedback;
}

class CareFeedback {
  const CareFeedback({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.kind,
    required this.body,
    required this.publishedAt,
    this.localDate,
    this.readAt,
  });

  final String id;
  final String authorId;

  /// Vacío si la vista de nombres no lo devolvió. La pantalla sabe mostrar
  /// una devolución sin firma: perderla entera por el nombre sería peor.
  final String authorName;

  final CareFeedbackKind kind;
  final String body;
  final DateTime publishedAt;

  /// El día del que habla, si habla de uno. Sin fecha es sobre el seguimiento
  /// en general.
  final DateTime? localDate;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
  bool get isIndication => kind == CareFeedbackKind.indication;

  CareFeedback markedRead(DateTime at) => CareFeedback(
    id: id,
    authorId: authorId,
    authorName: authorName,
    kind: kind,
    body: body,
    publishedAt: publishedAt,
    localDate: localDate,
    readAt: readAt ?? at,
  );

  /// Lee una fila de `care_feedback`, o devuelve `null` si no cierra.
  ///
  /// Una fila rota se descarta y no tumba la lista: la forma la decide el
  /// servidor y acá se la trata como entrada. Un `as String` sobre un campo
  /// que no vino lanza un `TypeError`, que no es una `Exception` y se escapa
  /// de los `catch` de quien llama.
  static CareFeedback? fromRow(
    Map<String, dynamic> row, {
    String authorName = '',
  }) {
    final id = row['id'];
    final authorId = row['author_id'];
    final body = row['body'];
    final published = _parseInstant(row['published_at']);
    if (id is! String || id.isEmpty) return null;
    if (body is! String || body.trim().isEmpty) return null;
    if (published == null) return null;

    final rawDate = row['local_date'];
    final localDate = rawDate is String ? DateTime.tryParse(rawDate) : null;

    return CareFeedback(
      id: id,
      authorId: authorId is String ? authorId : '',
      authorName: authorName,
      kind: CareFeedbackKind.fromWire(row['kind']),
      body: body.trim(),
      publishedAt: published,
      localDate: localDate == null
          ? null
          : DateTime(localDate.year, localDate.month, localDate.day),
      readAt: _parseInstant(row['read_at']),
    );
  }

  static DateTime? _parseInstant(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toLocal() : null;
}

/// Lo que va a la tarjeta de Inicio, sacado de la lista entera.
///
/// Es una regla de producto y por eso vive acá y no en el widget: la última
/// devolución **sin leer** y todas las indicaciones vigentes. Una devolución
/// ya leída no vuelve a Inicio —para eso está la lista—; una indicación sí,
/// porque sigue valiendo hasta que la profesional la saque.
class CareInbox {
  CareInbox(List<CareFeedback> all)
    : items = List<CareFeedback>.unmodifiable(
        <CareFeedback>[...all]
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
      );

  /// Todo, de lo más nuevo a lo más viejo.
  final List<CareFeedback> items;

  List<CareFeedback> get indications =>
      items.where((f) => f.isIndication).toList();

  List<CareFeedback> get unread => items.where((f) => f.isUnread).toList();

  /// La devolución sin leer más reciente. Las indicaciones no cuentan acá:
  /// ya tienen su propio lugar en la tarjeta.
  CareFeedback? get latestUnreadFeedback {
    for (final f in items) {
      if (!f.isIndication && f.isUnread) return f;
    }
    return null;
  }

  int get unreadCount => unread.length;

  /// Si la tarjeta de Inicio tiene algo que decir.
  bool get hasSomethingForHome =>
      latestUnreadFeedback != null || indications.isNotEmpty;
}
