// El informe en PDF: primero que las cuentas sean honestas, después que el
// archivo se genere de verdad.
//
// Lo primero importa porque un promedio mal calculado en un informe es peor que
// no tener informe: nadie lo va a revisar contra el historial. La regla es una
// sola y se prueba de tres maneras — **un día sin registrar no es un día de
// cero**, así que no entra en ningún promedio.
//
// Lo segundo importa porque todo el dibujo del PDF vive fuera del análisis
// estático: una fuente que no está en los assets o un gráfico con cero puntos
// no se ven hasta que alguien toca "Generar".

import 'package:ceres/core/utils/dates.dart';
import 'package:ceres/data/local/local_store.dart';
import 'package:ceres/data/local/pdf_report.dart';
import 'package:ceres/data/repositories/local_repository.dart';
import 'package:ceres/domain/enums/enums.dart';
import 'package:ceres/domain/models/meal.dart';
import 'package:ceres/domain/models/summaries.dart';
import 'package:ceres/domain/services/report_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El informe escribe fechas largas ("martes 12 de agosto"), y eso pide los
  // símbolos del locale igual que en el arranque de la app.
  setUpAll(() => initializeDateFormatting(appLocale));

  late LocalRepository repo;
  final hoy = today();

  Meal comida(DateTime fecha, {int kcal = 600, double proteina = 40}) => Meal(
    id: 'm-${isoDate(fecha)}',
    slot: MealSlot.lunch,
    eatenAt: fecha,
    localDate: dateOnly(fecha),
    items: <MealItem>[
      MealItem(
        id: 'i-${isoDate(fecha)}',
        name: 'Milanesa con puré',
        quantity: 1,
        unit: 'porcion',
        kcal: kcal,
        proteinG: proteina,
        carbsG: 60,
        fatG: 20,
        position: 0,
      ),
    ],
    source: MealSource.manual,
    createdAt: fecha,
    updatedAt: fecha,
  );

  /// El mismo armado que hace la pantalla, para que el test cubra ese camino y
  /// no uno paralelo.
  NutritionReport informe({int days = 30}) {
    final to = today();
    final from = to.subtract(Duration(days: days - 1));
    return ReportBuilder.build(
      profile: repo.profile,
      goal: repo.currentGoalOrNull,
      progress: repo.progress(from: from, to: to),
      days: <DailySummary>[
        for (var i = 0; i < days; i++) repo.daily(from.add(Duration(days: i))),
      ],
      glassesOn: repo.glassesOn,
      sleepMinutesOn: (date) => repo.sleepOn(date)?.minutes,
      measurementsOf: repo.measurements,
      trackingSince: repo.trackingSince,
      generatedAt: DateTime(2026, 8, 12),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = await LocalStore.open();
    repo = LocalRepository(store, onChanged: () {});
    await repo.signIn('yo@ceres.test');
  });

  group('promedios', () {
    test('sin nada registrado no hay promedios que mostrar', () {
      final r = informe();
      expect(r.daysWithRecords, 0);
      expect(r.calories.hasData, isFalse);
      expect(r.hasEnoughData, isFalse);
      expect(ReportBuilder.headline(r), isNull);
    });

    test('el promedio sale de los días con registro, no del período', () async {
      // Tres días de 600 kcal en un período de 30. El promedio es 600, no 60:
      // los 27 días que no se cargaron no son días de cero calorías.
      for (var i = 0; i < 3; i++) {
        await repo.saveMeal(comida(hoy.subtract(Duration(days: i))));
      }

      final r = informe();
      expect(r.daysWithRecords, 3);
      expect(r.calories.value, 600);
      expect(r.calories.days, 3);
    });

    test('los macros se promedian sobre los mismos días que las calorías',
        () async {
      for (var i = 0; i < 3; i++) {
        await repo.saveMeal(comida(hoy.subtract(Duration(days: i))));
      }

      final r = informe();
      final proteina = r.nutrients.firstWhere((n) => n.label == 'Proteínas');
      expect(proteina.average.value, 40);
      expect(proteina.average.days, r.calories.days);
    });

    test('el agua se promedia sobre los días que la tienen', () async {
      await repo.saveMeal(comida(hoy));
      await repo.saveMeal(comida(hoy.subtract(const Duration(days: 1))));
      // Un solo día con agua: el promedio son esos 8 vasos, no 8 repartidos
      // entre los dos días con comida.
      await repo.addGlasses(hoy, 8);

      final r = informe();
      expect(r.water.value, 8);
      expect(r.water.days, 1);
    });

    test('con dos pesos hay diferencia y con uno solo no hay curva', () async {
      await repo.logWeight(
        weightKg: 82,
        date: hoy.subtract(const Duration(days: 20)),
      );
      var r = informe();
      expect(r.weight!.first, 82);
      expect(r.weight!.delta, 0);

      await repo.logWeight(weightKg: 80.4, date: hoy);
      r = informe();
      expect(r.weight!.last, 80.4);
      expect(r.weight!.delta, closeTo(-1.6, 0.001));
    });
  });

  group('extremos y objetivo', () {
    test('con un solo día registrado no hay extremos que comparar', () async {
      await repo.saveMeal(comida(hoy));
      expect(ReportBuilder.calorieExtremes(informe()), isNull);
    });

    test('los extremos son el día más bajo y el más alto', () async {
      await repo.saveMeal(comida(hoy, kcal: 500));
      await repo.saveMeal(
        comida(hoy.subtract(const Duration(days: 1)), kcal: 2400),
      );

      final extremos = ReportBuilder.calorieExtremes(informe());
      expect(extremos!.$1.consumed, 500);
      expect(extremos.$2.consumed, 2400);
    });

    test('"sin pasarte" es no pasarse, no acertar el número', () async {
      final objetivo = repo.currentGoalOrNull!.baseCalorieTarget;
      // Muy por debajo, justo en el número, y pasado por poco.
      await repo.saveMeal(comida(hoy, kcal: (objetivo * 0.6).round()));
      await repo.saveMeal(
        comida(hoy.subtract(const Duration(days: 1)), kcal: objetivo),
      );
      await repo.saveMeal(
        comida(hoy.subtract(const Duration(days: 2)), kcal: objetivo + 300),
      );

      final r = informe();
      // Dos de tres. El día de 60 % del objetivo cuenta: es exactamente un día
      // en el que no se pasó, y antes quedaba afuera por estar a más de un
      // 10 % del número.
      expect(r.daysNotOver, 2);
      expect(r.daysWithRecords, 3);
    });

    test('un día sin registro no cuenta ni a favor ni en contra', () async {
      await repo.saveMeal(comida(hoy, kcal: 1000));
      final r = informe();
      expect(r.daysWithRecords, 1);
      expect(r.daysNotOver, 1);
    });
  });

  group('desde cuándo se cuenta', () {
    test('sin nada cargado, no hay días que contar', () {
      // Antes esto daba 30 —el período entero como denominador—, y era la
      // única forma en que el informe podía decir "0 de 30 · 0 %" sobre una
      // cuenta que **nunca registró nada**. Ese 0 % es un reproche por días que
      // no se sabe si existieron: sin un solo registro no hay ningún momento en
      // que la información válida haya empezado, así que no hay período
      // efectivo. La pantalla que lo genera ya no deja apretar el botón con
      // cero registros; el que quede en 0 es para que ninguna cuenta se haga
      // sobre un denominador inventado. Ver `docs/contexto-diario.md`.
      final r = informe();
      expect(r.totalDays, 0);
      expect(r.coveragePct, 0);
      expect(r.startedMidPeriod, isFalse);
    });

    test('empezando a mitad del período, se cuenta desde ahí', () async {
      // Registró los últimos 5 días de una ventana de 30: registró 5 de 5, no
      // 5 de 30. Los otros 25 no son huecos, son días sin la app.
      for (var i = 0; i < 5; i++) {
        await repo.saveMeal(comida(hoy.subtract(Duration(days: i))));
      }

      final r = informe();
      expect(r.trackingSince, repo.trackingSince);
      expect(r.startedMidPeriod, isTrue);
      expect(r.totalDays, 5);
      expect(r.daysWithRecords, 5);
      expect(r.coveragePct, 100);
    });

    test('lo que ya venía de antes no recorta el período', () async {
      await repo.saveMeal(comida(hoy.subtract(const Duration(days: 200))));
      await repo.saveMeal(comida(hoy));

      final r = informe();
      expect(r.startedMidPeriod, isFalse);
      expect(r.totalDays, 30);
    });
  });

  group('el archivo', () {
    test('se genera un PDF de verdad, en los dos temas', () async {
      for (var i = 0; i < 5; i++) {
        final dia = hoy.subtract(Duration(days: i));
        await repo.saveMeal(comida(dia, kcal: 1800 + i * 60));
        await repo.logWeight(weightKg: 82 - i * 0.2, date: dia);
      }
      await repo.addGlasses(hoy, 6);

      for (final dark in <bool>[true, false]) {
        final bytes = await PdfReport(report: informe(), dark: dark).build();
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        // Un PDF con las tres fuentes embebidas y dos gráficos no baja de unos
        // cuantos kilobytes: si saliera de 2 kB sería una hoja en blanco.
        expect(bytes.length, greaterThan(20000));
      }
    });

    test('un período sin ningún registro también genera archivo', () async {
      // Nadie debería llegar acá —el botón se apaga sin registros— pero un
      // gráfico con cero puntos no puede tirar una excepción.
      final bytes = await PdfReport(report: informe(), dark: true).build();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('con un solo peso no se intenta dibujar la curva', () async {
      await repo.saveMeal(comida(hoy));
      await repo.logWeight(weightKg: 80, date: hoy);
      final bytes = await PdfReport(report: informe(), dark: true).build();
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
