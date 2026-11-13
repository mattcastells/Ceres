// Devoluciones e indicaciones de la nutricionista: cómo se leen las filas y
// qué va a Inicio.
//
// La regla de Inicio es de producto y por eso tiene test: la última devolución
// **sin leer** y todas las indicaciones vigentes, leídas o no. Una indicación
// sigue valiendo hasta que la profesional la saque; una devolución leída ya
// cumplió.

import 'package:ceres/data/remote/care_feedback_client.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/care_feedback.dart';
import 'package:ceres/domain/models/goal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Map<String, dynamic> _row({
  String id = 'f1',
  String kind = 'feedback',
  String body = 'Muy bien la semana.',
  String publishedAt = '2026-11-08T14:00:00Z',
  String? readAt,
  String? localDate,
  String authorId = 'pro-1',
}) => <String, dynamic>{
  'id': id,
  'author_id': authorId,
  'kind': kind,
  'local_date': localDate,
  'body': body,
  'published_at': publishedAt,
  'read_at': readAt,
};

CareFeedback _f(
  String id, {
  CareFeedbackKind kind = CareFeedbackKind.feedback,
  required DateTime at,
  bool read = false,
}) => CareFeedback(
  id: id,
  authorId: 'pro-1',
  authorName: 'Natalia',
  kind: kind,
  body: 'texto $id',
  publishedAt: at,
  readAt: read ? at : null,
);

void main() {
  group('CareFeedback.fromRow', () {
    test('lee una fila completa', () {
      final f = CareFeedback.fromRow(
        _row(localDate: '2026-11-07', readAt: '2026-11-08T15:00:00Z'),
        authorName: 'Natalia',
      )!;
      expect(f.id, 'f1');
      expect(f.authorName, 'Natalia');
      expect(f.kind, CareFeedbackKind.feedback);
      expect(f.localDate, DateTime(2026, 11, 7));
      expect(f.isUnread, isFalse);
      expect(f.body, 'Muy bien la semana.');
    });

    test('sin read_at está sin leer', () {
      expect(CareFeedback.fromRow(_row())!.isUnread, isTrue);
    });

    test('las indicaciones se reconocen', () {
      expect(
        CareFeedback.fromRow(_row(kind: 'indication'))!.isIndication,
        isTrue,
      );
    });

    test('un tipo desconocido se lee como devolución', () {
      // Así un texto nuevo no queda clavado en Inicio para siempre.
      expect(
        CareFeedback.fromRow(_row(kind: 'otra_cosa'))!.kind,
        CareFeedbackKind.feedback,
      );
    });

    test('una fila sin lo indispensable se descarta en vez de romper', () {
      expect(CareFeedback.fromRow(_row(body: '   ')), isNull);
      expect(
        CareFeedback.fromRow(<String, dynamic>{'id': 'x', 'body': 'hola'}),
        isNull,
      );
      expect(CareFeedback.fromRow(<String, dynamic>{'id': 3}), isNull);
    });
  });

  test('parseRows descarta las filas rotas y pone los nombres', () {
    final list = CareFeedbackClient.parseRows(
      <dynamic>[
        _row(id: 'a'),
        <String, dynamic>{'id': 'roto'},
        'ni siquiera un mapa',
        _row(id: 'b', authorId: 'desconocida'),
      ],
      namesById: const <String, String>{'pro-1': 'Natalia'},
    );
    expect(list.map((f) => f.id), <String>['a', 'b']);
    expect(list.first.authorName, 'Natalia');
    // Sin nombre se muestra igual: lo escrito sigue valiendo.
    expect(list.last.authorName, '');
  });

  group('CareInbox', () {
    final base = DateTime(2026, 11, 1, 10);

    test('ordena de lo más nuevo a lo más viejo', () {
      final inbox = CareInbox(<CareFeedback>[
        _f('viejo', at: base),
        _f('nuevo', at: base.add(const Duration(days: 2))),
        _f('medio', at: base.add(const Duration(days: 1))),
      ]);
      expect(inbox.items.map((f) => f.id), <String>['nuevo', 'medio', 'viejo']);
    });

    test('a Inicio va la última devolución sin leer', () {
      final inbox = CareInbox(<CareFeedback>[
        _f('leida-reciente', at: base.add(const Duration(days: 3)), read: true),
        _f('sin-leer-vieja', at: base),
        _f('sin-leer-nueva', at: base.add(const Duration(days: 1))),
      ]);
      expect(inbox.latestUnreadFeedback?.id, 'sin-leer-nueva');
      expect(inbox.unreadCount, 2);
      expect(inbox.hasSomethingForHome, isTrue);
    });

    test('las indicaciones van a Inicio aunque estén leídas', () {
      final inbox = CareInbox(<CareFeedback>[
        _f('ind', kind: CareFeedbackKind.indication, at: base, read: true),
        _f('dev', at: base, read: true),
      ]);
      expect(inbox.latestUnreadFeedback, isNull);
      expect(inbox.indications.map((f) => f.id), <String>['ind']);
      expect(inbox.hasSomethingForHome, isTrue);
    });

    test('una indicación sin leer no cuenta como "la última devolución"', () {
      final inbox = CareInbox(<CareFeedback>[
        _f('ind', kind: CareFeedbackKind.indication, at: base),
      ]);
      expect(inbox.latestUnreadFeedback, isNull);
      expect(inbox.unreadCount, 1);
    });

    test('todo leído y sin indicaciones: Inicio no muestra nada', () {
      final inbox = CareInbox(<CareFeedback>[_f('a', at: base, read: true)]);
      expect(inbox.hasSomethingForHome, isFalse);
      expect(CareInbox(const <CareFeedback>[]).hasSomethingForHome, isFalse);
    });
  });

  group('el objetivo recomendado', () {
    setUpAll(() => initializeDateFormatting('es_AR'));

    Map<String, dynamic> target({
      String id = 't1',
      String kind = 'indication',
      Object? kcal = 1800,
      Object? p = 120,
      Object? c = 180,
      Object? g = 60,
      String? appliedAt,
      String publishedAt = '2026-11-08T21:00:00Z',
    }) => <String, dynamic>{
      ..._row(
        id: id,
        kind: kind,
        publishedAt: publishedAt,
        body:
            'Objetivo recomendado: 1.800 kcal por día · proteínas 120 g.\n\n'
            'Subimos la proteína en el desayuno.',
      ),
      'target_kcal': kcal,
      'target_protein_g': p,
      'target_carbs_g': c,
      'target_fat_g': g,
      'applied_at': appliedAt,
    };

    Goal goal({int kcal = 2000, int p = 110, int c = 220, int g = 60}) => Goal(
      id: 'g',
      goalType: GoalType.lose,
      rateKgPerWeek: 0.5,
      targetWeightKg: 70,
      baseCalorieTarget: kcal,
      targetMethod: TargetMethod.calculated,
      bmrKcal: 1500,
      tdeeKcal: 2300,
      proteinG: p,
      carbsG: c,
      fatG: g,
      macroMethod: 'default',
      startsOn: DateTime(2026, 10),
    );

    test('lee los números, la nota y si se aplicó', () {
      final f = CareFeedback.fromRow(
        target(appliedAt: '2026-11-09T12:00:00Z'),
      )!;
      expect(f.isTarget, isTrue);
      expect(f.target!.kcal, 1800);
      expect(f.target!.proteinG, 120);
      expect(f.target!.hasAllMacros, isTrue);
      expect(f.isApplied, isTrue);
      expect(f.note, 'Subimos la proteína en el desayuno.');
      expect(f.target!.compact, '1.800 kcal · P 120 g · C 180 g · G 60 g');
    });

    test('los macros pueden no venir', () {
      final t = CareFeedback.fromRow(
        target(p: null, c: null, g: null),
      )!.target!;
      expect(t.hasAllMacros, isFalse);
      expect(t.compact, '1.800 kcal');
    });

    test('sin calorías, fuera de rango o en una devolución no es objetivo', () {
      expect(CareFeedback.fromRow(target(kcal: null))!.target, isNull);
      expect(CareFeedback.fromRow(target(kcal: 700))!.target, isNull);
      expect(CareFeedback.fromRow(target(kcal: '1800'))!.target, isNull);
      expect(CareFeedback.fromRow(target(kind: 'feedback'))!.target, isNull);
      // Un macro fuera de rango se descarta solo, sin perder las calorías.
      expect(CareFeedback.fromRow(target(g: 900))!.target!.fatG, isNull);
    });

    test('la nota: sin la línea de números, o el texto entero', () {
      expect(CareTarget.noteOf('Objetivo recomendado: 1.800 kcal.'), '');
      expect(
        CareTarget.noteOf('Objetivo recomendado: 1.800 kcal.\n\nNota.'),
        'Nota.',
      );
      expect(CareTarget.noteOf('Otra cosa.\n'), 'Otra cosa.');
    });

    test('difiere del objetivo vigente solo en lo que trae', () {
      const t = CareTarget(kcal: 1800, proteinG: 120, carbsG: 180, fatG: 60);
      expect(t.differsFrom(null), isTrue);
      expect(t.differsFrom(goal()), isTrue);
      expect(t.differsFrom(goal(kcal: 1800, p: 120, c: 180)), isFalse);
      expect(t.differsFrom(goal(kcal: 1800, p: 121, c: 180)), isTrue);
      // Sin macros, mirar los macros no tiene sentido: la app los recalcula.
      const soloKcal = CareTarget(kcal: 1800);
      expect(soloKcal.differsFrom(goal(kcal: 1800, p: 1, c: 2, g: 3)), isFalse);
    });

    test('el objetivo que se guarda conserva tipo y ritmo', () {
      const t = CareTarget(kcal: 1800, proteinG: 120, carbsG: 180, fatG: 60);
      final g = t.toGoal(
        current: goal(),
        weightKg: 80,
        id: 'nuevo',
        startsOn: DateTime(2026, 11, 13),
      );
      expect(g.id, 'nuevo');
      expect(g.baseCalorieTarget, 1800);
      expect(g.targetMethod, TargetMethod.manual);
      expect(g.macroMethod, 'custom');
      expect(<int>[g.proteinG, g.carbsG, g.fatG], <int>[120, 180, 60]);
      expect(g.goalType, GoalType.lose);
      expect(g.rateKgPerWeek, 0.5);
      expect(g.targetWeightKg, 70);
      expect(g.isCurrent, isTrue);
    });

    test('sin los tres macros, se reparten como siempre', () {
      const t = CareTarget(kcal: 1800, proteinG: 130);
      final g = t.toGoal(
        current: goal(),
        weightKg: 80,
        id: 'nuevo',
        startsOn: DateTime(2026, 11, 13),
      );
      expect(g.macroMethod, 'default');
      expect(g.proteinG, 130);
      expect(g.carbsG, greaterThan(0));
      expect(g.fatG, greaterThan(0));
    });

    test('la bandeja: el vigente es el más nuevo y no es una indicación más', () {
      final inbox = CareInbox(
        CareFeedbackClient.parseRows(<dynamic>[
          target(id: 'viejo', publishedAt: '2026-11-01T10:00:00Z'),
          target(id: 'nuevo', publishedAt: '2026-11-08T10:00:00Z'),
          _row(id: 'ind', kind: 'indication', body: 'Tomá agua.'),
        ]),
      );
      expect(inbox.target?.id, 'nuevo');
      expect(inbox.indications.map((f) => f.id), <String>['ind']);
      expect(inbox.hasSomethingForHome, isTrue);
      // Ya aplicado sigue en Inicio: es una indicación vigente más.
      expect(
        CareInbox(<CareFeedback>[
          CareFeedback.fromRow(target(appliedAt: '2026-11-09T12:00:00Z'))!,
        ]).hasSomethingForHome,
        isTrue,
      );
    });

    test('aplicarla la deja leída y aplicada', () {
      final f = CareFeedback.fromRow(target())!;
      final at = DateTime(2026, 11, 13, 10);
      final applied = f.markedApplied(at);
      expect(applied.appliedAt, at);
      expect(applied.readAt, isNotNull);
      expect(applied.target, same(f.target));
      expect(f.markedRead(at).target, same(f.target));
    });
  });
}
