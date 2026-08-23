import { SLOT_LABEL, type Meal } from '@/lib/queries';
import { hora, miles, num } from '@/lib/format';

/**
 * Cómo se llama una comida en la lista.
 *
 * La mayoría no tiene nombre: se cargan eligiendo ítems del catálogo y `name`
 * queda en null. Antes todas decían "Comida", así que un día abierto era cuatro
 * filas idénticas y había que abrirlas una por una para saber cuál era cuál —en
 * la pantalla donde lo que se busca es exactamente eso, qué comió—.
 *
 * El nombre sale de los ítems, que es de donde saldría si uno lo escribiera:
 * los dos primeros y "+2" si hay más. Dos y no todos porque el título tiene que
 * entrar en una línea junto a la hora, la etiqueta de IA y las calorías; una
 * lista completa de seis ítems empuja el total fuera de la pantalla en un
 * teléfono.
 *
 * El orden es el de carga y no por calorías: es el orden en que la persona los
 * anotó, y reordenarlo por peso pondría primero el aceite de la ensalada.
 */
export function tituloDeComida(meal: Meal): string {
  if (meal.name?.trim()) return meal.name.trim();

  const nombres = meal.meal_items
    .map((i) => i.name?.trim())
    .filter((n): n is string => !!n);

  if (nombres.length === 0) return 'Comida';

  const visibles = nombres.slice(0, 2).join(', ');
  const resto = nombres.length - 2;
  return resto > 0 ? `${visibles} +${resto}` : visibles;
}

/**
 * Una comida: el nombre, la hora y el total; adentro, los ítems y la foto.
 *
 * La tabla de ítems es lo que hace pesado a un día —seis columnas por comida,
 * cuatro comidas— y casi nunca es lo primero que se busca. Con la comida
 * cerrada, el día entra entero en una pantalla.
 */
export function MealRow({
  meal,
  photoUrls,
  sharePhotos,
  defaultOpen = false,
}: {
  meal: Meal;
  photoUrls: Record<string, string>;
  sharePhotos: boolean;
  defaultOpen?: boolean;
}) {
  const foto = sharePhotos && meal.photo_path ? photoUrls[meal.photo_path] : null;

  return (
    <details className="meal" open={defaultOpen}>
      <summary>
        <Chev />
        <span>{tituloDeComida(meal)}</span>
        <span className="caption tnum">{hora(meal.eaten_at)}</span>
        {foto && <Camara />}
        <span className="tnum meal-kcal">
          {miles(meal.total_kcal)}
          <span className="muted"> kcal</span>
        </span>
      </summary>

      <div className="meal-body">
        <div className="scroll-x">
          <table>
            <thead>
              <tr>
                <th>Ítem</th>
                <th style={{ textAlign: 'right' }}>Cantidad</th>
                <th style={{ textAlign: 'right' }}>kcal</th>
                <th style={{ textAlign: 'right' }}>P</th>
                <th style={{ textAlign: 'right' }}>C</th>
                <th style={{ textAlign: 'right' }}>G</th>
              </tr>
            </thead>
            <tbody>
              {meal.meal_items.map((it) => (
                <tr key={it.id}>
                  <td>
                    {it.name}
                    {it.ai_confidence !== null && it.ai_confidence < 0.5 && (
                      <span
                        className="caption estimate"
                        style={{ marginLeft: 6 }}
                      >
                        confianza baja
                      </span>
                    )}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.quantity)} {it.unit}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {it.kcal}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.protein_g)}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.carbs_g)}
                  </td>
                  <td className="tnum" style={{ textAlign: 'right' }}>
                    {num(it.fat_g)}
                  </td>
                </tr>
              ))}
              {meal.meal_items.length === 0 && (
                <tr>
                  <td colSpan={6} className="muted">
                    Esta comida no tiene el detalle cargado.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {foto && (
          /* eslint-disable-next-line @next/next/no-img-element */
          <img
            src={foto}
            alt={`Foto de ${SLOT_LABEL[meal.slot] ?? meal.slot}`}
            loading="lazy"
            style={{
              marginTop: 'var(--s4)',
              maxWidth: 260,
              width: '100%',
              borderRadius: 'var(--radius-md)',
              display: 'block',
            }}
          />
        )}
      </div>
    </details>
  );
}

/** "Esta comida tiene foto", dibujado y no con un emoji: el emoji lo pinta cada
 *  sistema a su manera y mete un color que no es de la paleta en una fila que
 *  es toda gris. */
function Camara() {
  return (
    <svg
      width="13"
      height="13"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.3"
      className="muted"
      role="img"
      aria-label="con foto"
    >
      <title>Con foto</title>
      <path d="M1.8 5.2h2.6l1.1-1.6h4.9l1.1 1.6h2.7v7.2H1.8z" />
      <circle cx="8" cy="8.8" r="2.4" />
    </svg>
  );
}

/** La flecha del colapsable. Gira 90° cuando el `<details>` está abierto. */
export function Chev() {
  return (
    <svg
      className="chev"
      width="11"
      height="11"
      viewBox="0 0 10 10"
      aria-hidden="true"
    >
      <path
        d="M3.2 1.4 L6.9 5 L3.2 8.6"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
