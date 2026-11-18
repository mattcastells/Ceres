// El escenario de demostración: quiénes son y cómo se comportan.
//
// Todo lo de acá es inventado. Cada cuenta usa un mail de DEMO_DOMAIN, que es
// la única marca que necesita `limpiar.mjs` para borrarlas.

export const DEMO_DOMAIN = 'demo.ceres.app';

export const ORGANIZACION = {
  name: 'Consultorio Ruiz · Nutrición clínica',
  ai_monthly_quota: 1800,
};

// Las profesionales. `owner` es la que se usa en la demo. El código es fijo
// para poder tenerlo anotado en la defensa (solo letras y números que se
// dictan sin confundir: sin 0/O, 1/I/L).
export const PROFESIONALES = [
  { key: 'valentina', name: 'Lic. Valentina Ruiz', email: 'valentina', sex: 'female', birth: '1988-04-12', height: 165, role: 'owner', code: 'CE-VRUZ26' },
];

// Cada paciente tiene un patrón: es lo que el tablero y los informes tienen
// que poder contar. Los campos:
//   target      objetivo diario de kcal       eats    cuánto del objetivo come (1 = justo)
//   weekend     multiplicador de sáb/dom      adh     probabilidad de registrar un día
//   kgWeek      cambio real de peso por semana (lo que muestra la balanza)
//   stopsAgo    dejó de registrar hace N días  days    días de historial
//   protein     multiplicador de la proteína  late    cena tarde
//   sickAgo     tuvo un día de enfermedad hace N días
//   drinks      'weekend': toma viernes y sábado; esa noche duerme peor y al
//               otro día se mueve menos (lo que cuenta "Con alcohol contra
//               sin" en Hábitos)
//   share       categorías compartidas         plan    plan propio (free = paga la Pro)
export const PACIENTES = [
  { key: 'lucia', of: 'valentina', name: 'Lucía Fernández', sex: 'female', birth: '1992-02-20', height: 164, weight: 74, goal: 'lose', target: 1600, eats: 0.98, weekend: 1.05, adh: 0.96, kgWeek: -0.5, activity: 'moderate', act: ['walking', 'pilates'], actPerWeek: 4, share: 'all', plan: 'free' },
  { key: 'diego', of: 'valentina', name: 'Diego Romero', sex: 'male', birth: '1985-06-11', height: 178, weight: 96, goal: 'lose', target: 2100, eats: 0.95, weekend: 1.4, adh: 0.86, kgWeek: 0.0, drinks: 'weekend', activity: 'light', act: ['walking'], actPerWeek: 2, share: 'all', plan: 'free' },
  { key: 'carla', of: 'valentina', name: 'Carla Méndez', sex: 'female', birth: '1998-09-02', height: 160, weight: 58, goal: 'maintain', target: 1900, eats: 1.0, weekend: 1.1, adh: 0.9, kgWeek: 0.0, protein: 0.6, activity: 'moderate', act: ['yoga', 'running'], actPerWeek: 3, share: 'meals_wellbeing', plan: 'premium' },
  { key: 'pablo', of: 'valentina', name: 'Pablo Giménez', sex: 'male', birth: '1974-01-30', height: 172, weight: 101, goal: 'lose', target: 2000, eats: 1.02, weekend: 1.2, adh: 0.8, kgWeek: -0.3, stopsAgo: 6, activity: 'sedentary', act: ['walking'], actPerWeek: 1, share: 'all', plan: 'free' },
  { key: 'sofia', of: 'valentina', name: 'Sofía Herrera', sex: 'female', birth: '1989-11-15', height: 168, weight: 79, goal: 'lose', target: 1500, eats: 1.0, weekend: 1.15, adh: 0.82, kgWeek: -0.35, sickAgo: 9, activity: 'light', act: ['walking', 'strength_training'], actPerWeek: 3, share: 'all', plan: 'free' },
  { key: 'martina', of: 'valentina', name: 'Martina López', sex: 'female', birth: '2002-05-08', height: 170, weight: 61, goal: 'gain', target: 2500, eats: 0.84, weekend: 1.0, adh: 0.9, kgWeek: 0.05, activity: 'high', act: ['strength_training', 'running'], actPerWeek: 5, share: 'all', plan: 'premium' },
  { key: 'javier', of: 'valentina', name: 'Javier Castro', sex: 'male', birth: '1981-03-22', height: 182, weight: 104, goal: 'lose', target: 2200, eats: 1.0, weekend: 1.25, adh: 0.85, kgWeek: -0.2, late: true, activity: 'light', act: ['cycling'], actPerWeek: 2, share: 'meals', plan: 'free' },
  { key: 'ana', of: 'valentina', name: 'Ana Torres', sex: 'female', birth: '1966-07-19', height: 158, weight: 66, goal: 'maintain', target: 1700, eats: 1.0, weekend: 1.0, adh: 0.98, kgWeek: 0.0, activity: 'sedentary', act: ['walking'], actPerWeek: 2, share: 'meals_body', plan: 'free' },
  { key: 'nicolas', of: 'valentina', name: 'Nicolás Paz', sex: 'male', birth: '1993-12-01', height: 176, weight: 92, goal: 'lose', target: 2300, eats: 0.97, weekend: 1.05, adh: 0.92, kgWeek: -0.8, activity: 'high', act: ['running', 'strength_training', 'sports'], actPerWeek: 5, share: 'all', plan: 'premium' },
  { key: 'camila', of: 'valentina', name: 'Camila Ríos', sex: 'female', birth: '1996-04-27', height: 162, weight: 70, goal: 'lose', target: 1600, eats: 1.0, weekend: 1.1, adh: 0.95, kgWeek: -0.4, days: 10, activity: 'moderate', act: ['dancing', 'walking'], actPerWeek: 3, share: 'all', plan: 'free' },
  // Con poco historial: empezaron hace tres semanas.
  { key: 'raul', of: 'valentina', name: 'Raúl Benítez', sex: 'male', birth: '1979-08-14', height: 175, weight: 88, goal: 'lose', target: 2100, eats: 1.0, weekend: 1.2, adh: 0.85, kgWeek: -0.3, days: 21, activity: 'light', act: ['walking'], actPerWeek: 2, share: 'all', plan: 'free' },
  { key: 'paula', of: 'valentina', name: 'Paula Acosta', sex: 'female', birth: '1991-10-05', height: 166, weight: 63, goal: 'maintain', target: 1850, eats: 1.0, weekend: 1.1, adh: 0.9, kgWeek: 0.0, days: 21, activity: 'moderate', act: ['yoga'], actPerWeek: 3, share: 'all', plan: 'free' },
  { key: 'esteban', of: 'valentina', name: 'Esteban Molina', sex: 'male', birth: '1970-02-11', height: 170, weight: 84, goal: 'lose', target: 2000, eats: 1.05, weekend: 1.3, adh: 0.75, kgWeek: -0.1, days: 21, activity: 'sedentary', act: ['walking'], actPerWeek: 1, share: 'meals', plan: 'free' },
];

// Usuarios del plan gratis sin profesional: los que ven anuncios. Opcionalmente
// quedan como pals de una cuenta real (`--amigo-de`).
// Tomás es la cuenta Gratis de la demo (anuncios, sin IA) y Julieta la
// Premium (toda la IA, sin anuncios). Los topes diarios de IA de la demo los
// sube `levantar.ps1`, así que Premium no se corta en medio de una prueba.
export const AMIGOS = [
  { key: 'tomas', name: 'Tomás Vega', sex: 'male', birth: '1994-03-03', height: 180, weight: 84, goal: 'lose', target: 2300, eats: 1.0, weekend: 1.2, adh: 0.8, kgWeek: -0.2, days: 14, activity: 'moderate', act: ['running'], actPerWeek: 3, plan: 'free', manualOnly: true },
  { key: 'julieta', name: 'Julieta Sanz', sex: 'female', birth: '1995-08-21', height: 163, weight: 60, goal: 'maintain', target: 1900, eats: 1.0, weekend: 1.1, adh: 0.85, kgWeek: 0, days: 14, activity: 'moderate', act: ['pilates'], actPerWeek: 3, plan: 'premium', manualOnly: true },
];

// Lo que la nutricionista ya le escribió a algunos pacientes. Tu propia cuenta
// no recibe nada sembrado: la devolución para vos se escribe en vivo.
export const DEVOLUCIONES = [
  { to: 'lucia', kind: 'feedback', daysAgo: 6, read: true, body: 'Lucía, muy bien estas dos semanas: registraste casi todos los días y el promedio quedó en tu objetivo. Se nota en la balanza. Para esta semana te propongo sumar una colación con proteína a la tarde (un yogur o un huevo duro), así llegás con menos hambre a la cena.' },
  { to: 'carla', kind: 'indication', daysAgo: 12, read: true, body: 'Sumá una porción de proteína en el desayuno: un huevo, queso o yogur.' },
  { to: 'javier', kind: 'indication', daysAgo: 10, read: false, body: 'Intentá cenar antes de las 22 h, y si se hace tarde, que sea algo liviano.' },
  { to: 'sofia', kind: 'feedback', daysAgo: 4, read: false, body: 'Sofía, vi que estuviste con angina la semana pasada: es normal que el registro y la actividad bajen esos días, no te preocupes por eso. Retomá de a poco, empezando por las caminatas.' },
];

// El objetivo recomendado (migración 53): una indicación con números que el
// paciente aplica desde la app. Carla ya lo leyó y todavía no lo aplicó; Diego
// queda sin ninguno para recomendarlo en vivo.
export const OBJETIVOS = [
  { to: 'carla', daysAgo: 5, read: true, kcal: 1900, protein: 95, carbs: 230, fat: 63, nota: 'Mantenemos las calorías y subimos la proteína: repartila entre el desayuno y la merienda.' },
];

// Lo que Valentina publicó para todo su equipo (migración 52). El último es un
// borrador: no lo ve ningún paciente.
export const ARTICULOS = [
  {
    kind: 'recipe', tag: 'Desayunos', daysAgo: 20, title: 'Budín de avena y banana',
    body: `# Ingredientes
- 2 bananas maduras
- 1 taza de avena
- 2 huevos
- Canela y esencia de vainilla

# Preparación
1. Pisá las bananas y mezclalas con los huevos.
2. Sumá la avena y la canela.
3. Horno medio, 25 minutos.

Rinde 8 porciones de unas **120 kcal**. Con un yogur natural es un desayuno completo.`,
  },
  {
    kind: 'article', tag: 'Organización', daysAgo: 9, title: 'Cómo armar una vianda en 10 minutos',
    body: `La vianda sale fácil si el domingo dejás dos o tres bases cocidas. Después es combinar.

# La regla del plato
- **Mitad** de verduras, crudas o cocidas.
- **Un cuarto** de proteína: pollo, huevo, legumbres, atún.
- **Un cuarto** de hidratos: arroz, papa, fideos, quinoa.

Sumá una fruta y agua. Si te queda corta, agregá más verdura antes que más hidratos.`,
  },
  {
    kind: 'recipe', tag: 'Colaciones', daysAgo: 3, title: 'Hummus de garbanzos',
    body: `# Ingredientes
- 1 lata de garbanzos escurridos
- 1 cucharada de tahini
- Jugo de medio limón
- 1 diente de ajo, sal y comino

# Preparación
1. Procesá todo con dos o tres cucharadas de agua.
2. Ajustá la sal y el limón.

Con bastones de zanahoria y apio es una colación que llena.`,
  },
  {
    kind: 'article', tag: 'Salidas', daysAgo: 1, draft: true, title: 'Comer afuera sin descontrolarse',
    body: 'Borrador. Ideas: mirar la carta antes, pedir la guarnición de verduras, compartir el postre.',
  },
];

// Platos para generar comidas. Cada ítem: [nombre, cantidad, unidad, kcal, prot, carb, grasa].
export const PLATOS = {
  breakfast: [
    ['Café con leche y tostadas', [['Café con leche', 250, 'ml', 120, 6, 12, 5], ['Pan francés', 60, 'g', 160, 5, 32, 1], ['Queso crema', 30, 'g', 75, 2, 1, 7]]],
    ['Yogur con granola y banana', [['Yogur natural', 200, 'g', 120, 8, 14, 3], ['Granola', 40, 'g', 180, 4, 26, 7], ['Banana', 100, 'g', 89, 1, 23, 0]]],
    ['Mate con medialunas', [['Medialunas', 90, 'g', 340, 6, 40, 17]]],
    ['Tostadas con palta y huevo', [['Pan integral', 60, 'g', 150, 6, 26, 2], ['Palta', 50, 'g', 80, 1, 4, 7], ['Huevo', 50, 'g', 70, 6, 0, 5]]],
    ['Avena con leche y manzana', [['Avena', 40, 'g', 150, 5, 27, 3], ['Leche', 200, 'ml', 100, 6, 10, 4], ['Manzana', 120, 'g', 62, 0, 16, 0]]],
  ],
  lunch: [
    ['Milanesa con puré', [['Milanesa de carne', 150, 'g', 380, 30, 18, 20], ['Puré de papas', 200, 'g', 180, 4, 30, 5]]],
    ['Ensalada completa con pollo', [['Pechuga de pollo', 150, 'g', 240, 45, 0, 5], ['Lechuga, tomate y zanahoria', 200, 'g', 50, 2, 9, 0], ['Aceite de oliva', 10, 'g', 88, 0, 0, 10]]],
    ['Fideos con salsa', [['Fideos cocidos', 250, 'g', 330, 11, 66, 2], ['Salsa de tomate', 100, 'g', 40, 1, 8, 0], ['Queso rallado', 15, 'g', 60, 5, 0, 4]]],
    ['Empanadas de carne', [['Empanada de carne', 240, 'g', 720, 30, 66, 36]]],
    ['Arroz con pollo y verduras', [['Arroz blanco', 180, 'g', 230, 4, 50, 0], ['Pollo', 120, 'g', 200, 30, 0, 8], ['Verduras salteadas', 120, 'g', 70, 2, 10, 3]]],
    ['Tarta de verdura', [['Tarta de acelga', 200, 'g', 400, 12, 36, 22], ['Ensalada de tomate', 150, 'g', 30, 1, 6, 0]]],
  ],
  snack: [
    ['Fruta', [['Manzana', 150, 'g', 78, 0, 21, 0]]],
    ['Galletitas con queso', [['Galletitas de agua', 30, 'g', 130, 3, 21, 4], ['Queso fresco', 30, 'g', 90, 6, 1, 7]]],
    ['Yogur bebible', [['Yogur bebible', 200, 'ml', 150, 6, 24, 3]]],
    ['Alfajor', [['Alfajor de chocolate', 50, 'g', 220, 3, 30, 10]]],
    ['Huevo duro y fruta', [['Huevo duro', 50, 'g', 70, 6, 0, 5], ['Mandarina', 120, 'g', 55, 1, 13, 0]]],
  ],
  dinner: [
    ['Pollo al horno con calabaza', [['Pollo al horno', 180, 'g', 330, 45, 0, 16], ['Calabaza asada', 200, 'g', 90, 2, 20, 0]]],
    ['Pizza', [['Pizza muzzarella', 300, 'g', 780, 33, 90, 30]]],
    ['Bife con ensalada', [['Bife de chorizo', 200, 'g', 450, 50, 0, 27], ['Ensalada mixta', 150, 'g', 40, 2, 7, 0]]],
    ['Omelette con verduras', [['Omelette de 2 huevos', 140, 'g', 220, 14, 2, 17], ['Verduras salteadas', 150, 'g', 80, 2, 12, 3]]],
    ['Hamburguesas caseras', [['Hamburguesa casera', 180, 'g', 420, 34, 4, 30], ['Pan de hamburguesa', 70, 'g', 190, 6, 34, 3]]],
    ['Merluza con papas', [['Merluza al horno', 200, 'g', 180, 36, 0, 3], ['Papas al horno', 200, 'g', 220, 5, 44, 4]]],
  ],
};
