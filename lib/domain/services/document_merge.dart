/// Reconcilia el documento local con el que vino de las tablas.
///
/// ## Por qué existe
///
/// Hasta acá las tablas solo se consultaban **si el teléfono estaba vacío**: en
/// cuanto había algo local, la app no volvía a mirarlas nunca. Con eso el
/// documento era la fuente de verdad y las tablas un respaldo de solo escritura,
/// que es exactamente lo que había que dar vuelta — y lo que impide que la misma
/// cuenta se use desde dos lados. Un navegador que ya se visitó una vez tiene su
/// propia copia en `localStorage`, así que sin esto la web y el teléfono
/// divergen desde la segunda visita y no se vuelven a encontrar.
///
/// ## La regla
///
/// **Unión por id, gana el más reciente, y nunca se pierde nada.** En detalle:
///
/// 1. Un registro que está en los dos lados se resuelve por su marca de tiempo:
///    `updatedAt` donde existe, `loggedAt` donde es lo que se reescribe en cada
///    guardado.
/// 2. Empate, o sin marca de tiempo de ninguno de los dos lados: **gana el
///    local**. Es el conservador: lo que la persona tiene delante no se
///    reemplaza por algo del servidor que no se puede probar que sea más nuevo.
/// 3. Un registro que está solo en local **se conserva**. Puede ser algo que
///    todavía no se subió; borrarlo por no estar del otro lado sería perder un
///    dato por un problema de red.
/// 4. Un registro que está solo en el servidor **se suma**. Es lo que cargaron
///    desde otro dispositivo.
///
/// De ahí sale un invariante que los tests verifican y que conviene tener a
/// mano: **el documento reconciliado nunca tiene menos registros que el local**.
/// Esta función no puede borrar nada. Lo único que puede hacer un borrado es un
/// registro marcado como borrado (`deletedAt`) que gane por ser más reciente, y
/// eso es un borrado que alguien pidió, no un accidente.
///
/// ## Lo que no se toca
///
/// El perfil, la integración, los filtros y las preferencias se quedan **como
/// están en local**. No son un historial: son la configuración de este
/// dispositivo, cambian poco, y pisarlas con las de otro lado es molesto sin
/// aportar nada. La excepción natural ya está cubierta: si el documento local
/// está vacío, no hay nada local que conservar y entra el remoto entero.
library;

/// Las listas del documento que se reconcilian por id, y con qué marca de
/// tiempo se desempata cada una.
///
/// Está escrito así —una tabla, no un `if` por colección— para que agregar una
/// lista nueva sea agregar una fila. Una colección que se olvide acá no se
/// rompe: cae en [_keepLocal] y se conserva la local, que es el lado seguro.
const Map<String, List<String>> _timestampFields = <String, List<String>>{
  'meals': <String>['updatedAt'],
  'activities': <String>['updatedAt'],
  'waterLogs': <String>['updatedAt'],
  // El peso, las medidas y el sueño reescriben `loggedAt` en cada guardado, así
  // que cumple el mismo papel que `updatedAt` en los otros.
  'weightLogs': <String>['loggedAt'],
  // Las medidas no tienen `loggedAt` —el modelo nunca lo tuvo—, así que esta
  // fila nombraba un campo inexistente y el desempate siempre caía en "gana el
  // local". Ahora tienen `updatedAt` y desempata de verdad.
  'measurements': <String>['updatedAt'],
  'sleepLogs': <String>['loggedAt'],
  // Las marcas del día y el alcohol desempatan por `updatedAt` como el resto.
  // Las marcas **tienen** que desempatar: desmarcar un día de descanso en un
  // teléfono le escribe la lápida, y sin desempate el otro teléfono —que
  // todavía la tiene viva— la resucitaría en la siguiente reconciliación.
  'dayMarkers': <String>['updatedAt'],
  'alcoholLogs': <String>['updatedAt'],
  // Los objetivos sí desempatan: cerrar uno en un dispositivo tiene que ganarle
  // al que todavía lo tiene abierto, o el push del segundo lo des-cierra y
  // quedan dos vigentes para el mismo día.
  'goals': <String>['updatedAt'],
  // Sin marca de tiempo: se unen por id y ante conflicto gana el local.
  'activityGoals': <String>[],
  'userFoods': <String>[],
  'templates': <String>[],
  'customTypes': <String>[],
};

/// `reminders` **no está** en la tabla de arriba, y es a propósito.
///
/// No tienen id: el modelo se identifica por tipo, así que la unión por id no
/// aplica. Caen en "gana el local", y eso da la semántica correcta para lo que
/// son —una configuración del aparato—: un teléfono nuevo arranca vacío, entra
/// el documento remoto entero y se los trae; uno que ya tiene datos se queda
/// con los suyos, que es lo que uno espera de un horario de notificación que
/// depende del permiso y del "no molestar" de ese teléfono.
///
/// Lo que sí se resolvió es que **suban**: hasta la migración 44 la tabla
/// existía y el cliente no la nombraba, así que cambiar de teléfono los perdía.

/// Listas de valores sueltos —sin id— que se unen sin desempatar.
///
/// `restDays` sigue acá aunque la app ya no lo escriba: un documento v1 —un
/// respaldo viejo, o un teléfono que todavía no actualizó— puede traerlo, y
/// `LocalStore._restore` lo convierte a marcas al leerlo. Sacarlo de esta lista
/// haría que esos días se perdieran en la reconciliación, justo antes de llegar
/// al convertidor.
const List<String> _idlessLists = <String>['recentFoodIds', 'restDays'];

/// Reconcilia [local] con [remote] y devuelve el documento resultante.
///
/// Los dos vienen con la forma de `LocalStore.toDocument()`: el cliente
/// relacional arma el remoto con esa misma forma justamente para que haya un
/// solo lector y un solo reconciliador.
Map<String, dynamic> mergeDocuments({
  required Map<String, dynamic> local,
  required Map<String, dynamic> remote,
}) {
  // Sin nada local, el remoto entra entero: no hay nada que reconciliar y
  // conservar la configuración vacía de un dispositivo recién instalado no le
  // sirve a nadie. Es el caso del navegador que se abre por primera vez.
  if (_isEmpty(local)) return Map<String, dynamic>.from(remote);

  final merged = Map<String, dynamic>.from(local);

  for (final entry in _timestampFields.entries) {
    final key = entry.key;
    final localRows = _rows(local[key]);
    final remoteRows = _rows(remote[key]);
    if (remoteRows.isEmpty) continue;

    merged[key] = _mergeById(
      localRows: localRows,
      remoteRows: remoteRows,
      timestampFields: entry.value,
    );
  }

  merged['measurements'] = _collapseMeasurements(
    rows: _rows(merged['measurements']),
    remoteRows: _rows(remote['measurements']),
  );

  for (final key in _idlessLists) {
    final localList = _values(local[key]);
    final remoteList = _values(remote[key]);
    if (remoteList.isEmpty) continue;
    // El orden local manda —en los recientes significa algo— y lo que solo
    // está del otro lado se agrega al final.
    merged[key] = <Object?>[
      ...localList,
      ...remoteList.where((v) => !localList.contains(v)),
    ];
  }

  return merged;
}

/// Un documento sin un solo registro de contenido.
///
/// Se mira el contenido y no las claves: un documento recién creado trae todas
/// las listas, vacías, y tratarlo como "tiene datos" haría que la reconciliación
/// conservara la nada.
///
/// **`goals` no cuenta**, y es la parte que faltaba. La app siembra un objetivo
/// por defecto apenas hay sesión (`_ensureUsableProfile`), así que su presencia
/// no dice que la persona haya cargado nada: dice que la app se abrió. Contarlo
/// hacía que un teléfono recién instalado pareciera "con datos" y la
/// reconciliación entrara por el camino de abajo, donde **el perfil no se
/// reconcilia y gana el local**. Al entrar después de reinstalar, el perfil que
/// ganaba era el recién creado: la app volvía a pedir fecha de nacimiento,
/// altura y peso —y de paso devolvía a sus valores por defecto el sexo, el
/// nivel de actividad, las unidades, el tema, el crédito de ejercicio y la meta
/// de agua, que en un perfil nuevo **no son nulos**—. Completar esa alta
/// recalculaba el objetivo y pisaba el que la persona había escrito.
///
/// Es la misma definición que usa `LocalStore.hasUserData`, que ya excluía los
/// objetivos por este mismo motivo.
bool _isEmpty(Map<String, dynamic> document) {
  for (final key in _timestampFields.keys) {
    if (key == 'goals') continue;
    if (_rows(document[key]).isNotEmpty) return false;
  }
  return true;
}

List<Map<String, dynamic>> _rows(Object? raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  return <Map<String, dynamic>>[
    for (final item in raw)
      if (item is Map<String, dynamic>) item,
  ];
}

List<Object?> _values(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const <Object?>[];

/// Deja **una sola** medida por métrica y día, y la deja apuntando a la fila
/// que el servidor ya tiene.
///
/// La unión por id no alcanza para las medidas porque la base las considera
/// iguales por otra clave: hay un índice único sobre `(user_id, metric,
/// local_date)`. Cuando corregir una medida generaba un id nuevo —lo hacía
/// hasta que se arregló—, quedaban dos filas para el mismo día: la vieja del
/// servidor y la nueva de acá. Dos consecuencias, las dos feas:
///
/// 1. La pantalla mostraba la vieja, o sea el número que la persona acababa de
///    corregir.
/// 2. El `upsert` de medidas intentaba insertar la nueva contra ese índice y
///    fallaba **entero**, en cada push, para siempre.
///
/// Acá se colapsan: gana la más reciente por `updatedAt` —y ante empate o falta
/// de fecha, la local, como en todo el resto del archivo— y **se queda con el
/// id que el servidor ya conoce**. Eso último es lo que repara una cuenta que
/// ya venía rota: el push siguiente actualiza esa fila en su lugar en vez de
/// intentar insertar una que choca.
List<Map<String, dynamic>> _collapseMeasurements({
  required List<Map<String, dynamic>> rows,
  required List<Map<String, dynamic>> remoteRows,
}) {
  if (rows.isEmpty) return rows;

  final remoteIdByKey = <String, String>{};
  for (final row in remoteRows) {
    final key = _measurementKey(row);
    final id = row['id'];
    if (key != null && id is String && id.isNotEmpty) remoteIdByKey[key] = id;
  }

  // `LinkedHashMap` por defecto: conserva el orden en que se vieron, que es el
  // orden local primero. Reordenar una serie que la persona ya miró no aporta.
  final chosen = <String, Map<String, dynamic>>{};
  final sinClave = <Map<String, dynamic>>[];

  for (final row in rows) {
    final key = _measurementKey(row);
    if (key == null) {
      // Sin métrica o sin fecha no se puede aparear con nada. Se conserva:
      // descartarla sería perder un registro por venir mal formada.
      sinClave.add(row);
      continue;
    }
    final actual = chosen[key];
    if (actual == null ||
        _remoteIsNewer(actual, row, const <String>['updatedAt'])) {
      chosen[key] = row;
    }
  }

  return <Map<String, dynamic>>[
    for (final entry in chosen.entries)
      if (remoteIdByKey[entry.key] case final String remoteId
          when remoteId != entry.value['id'])
        <String, dynamic>{...entry.value, 'id': remoteId}
      else
        entry.value,
    ...sinClave,
  ];
}

String? _measurementKey(Map<String, dynamic> row) {
  final metric = row['metric'];
  final date = row['localDate'];
  if (metric is! String || date is! String) return null;
  return '$metric@$date';
}

/// Une dos listas por `id`, resolviendo los repetidos por marca de tiempo.
///
/// El resultado conserva el orden local y agrega al final lo que solo estaba del
/// otro lado, para que la reconciliación no reordene un historial que la persona
/// ya vio en cierto orden.
List<Map<String, dynamic>> _mergeById({
  required List<Map<String, dynamic>> localRows,
  required List<Map<String, dynamic>> remoteRows,
  required List<String> timestampFields,
}) {
  final remoteById = <String, Map<String, dynamic>>{};
  final remoteWithoutId = <Map<String, dynamic>>[];
  for (final row in remoteRows) {
    final id = row['id'];
    if (id is String && id.isNotEmpty) {
      remoteById[id] = row;
    } else {
      // Sin id no se puede aparear con nada. Se conserva igual: descartarlo
      // sería perder un registro por venir mal formado.
      remoteWithoutId.add(row);
    }
  }

  final out = <Map<String, dynamic>>[];
  final usados = <String>{};

  for (final localRow in localRows) {
    final id = localRow['id'];
    if (id is! String || !remoteById.containsKey(id)) {
      out.add(localRow);
      continue;
    }
    usados.add(id);
    final remoteRow = remoteById[id]!;
    out.add(
      _remoteIsNewer(localRow, remoteRow, timestampFields)
          ? remoteRow
          : localRow,
    );
  }

  for (final entry in remoteById.entries) {
    if (!usados.contains(entry.key)) out.add(entry.value);
  }
  out.addAll(remoteWithoutId);

  return out;
}

/// Si el registro remoto le gana al local.
///
/// Estrictamente más nuevo: ante un empate gana el local. La igualdad es el caso
/// normal —el mismo registro subido y bajado— y ahí reemplazarlo no cambiaría
/// nada salvo el riesgo de traerse una versión con menos campos.
bool _remoteIsNewer(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  List<String> timestampFields,
) {
  for (final field in timestampFields) {
    final localAt = _parse(local[field]);
    final remoteAt = _parse(remote[field]);
    // Sin fecha de un lado no se puede comparar, y sin comparación no se
    // reemplaza: gana el local.
    if (localAt == null || remoteAt == null) return false;
    if (remoteAt.isAfter(localAt)) return true;
    if (localAt.isAfter(remoteAt)) return false;
  }
  return false;
}

DateTime? _parse(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
