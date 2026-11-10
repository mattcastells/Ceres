// Devoluciones e indicaciones de la nutricionista: cómo se leen las filas y
// qué va a Inicio.
//
// La regla de Inicio es de producto y por eso tiene test: la última devolución
// **sin leer** y todas las indicaciones vigentes, leídas o no. Una indicación
// sigue valiendo hasta que la profesional la saque; una devolución leída ya
// cumplió.

import 'package:ceres/data/remote/care_feedback_client.dart';
import 'package:ceres/domain/models/care_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
