/**
 * Íconos de trazo, dibujados en línea para no sumar una librería por seis.
 * Toman el color del texto (`currentColor`).
 */

const TRAZOS = {
  actividad: <path d="M22 12h-4l-3 9L9 3l-3 9H2" />,
  agua: (
    <path d="M12 22a7 7 0 0 0 7-7c0-2-1-3.9-3-5.5s-3.5-4-4-6.5c-.5 2.5-2 4.9-4 6.5C6 11.1 5 13 5 15a7 7 0 0 0 7 7z" />
  ),
  sueno: <path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z" />,
  enfermedad: <path d="M14 4v10.54a4 4 0 1 1-4 0V4a2 2 0 0 1 4 0Z" />,
  alcohol: (
    <>
      <path d="M8 22h8" />
      <path d="M12 15v7" />
      <path d="M12 15a5 5 0 0 0 5-5c0-2-.5-4-2-8H9c-1.5 4-2 6-2 8a5 5 0 0 0 5 5Z" />
    </>
  ),
  descanso: (
    <>
      <path d="M2 4v16" />
      <path d="M2 8h18a2 2 0 0 1 2 2v10" />
      <path d="M2 17h20" />
      <path d="M6 8v9" />
    </>
  ),
} as const;

export type NombreIcono = keyof typeof TRAZOS;

export function Icono({
  nombre,
  size = 12,
  titulo,
  className,
}: {
  nombre: NombreIcono;
  size?: number;
  titulo?: string;
  className?: string;
}) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      role={titulo ? 'img' : undefined}
      aria-hidden={titulo ? undefined : true}
      aria-label={titulo}
    >
      {titulo && <title>{titulo}</title>}
      {TRAZOS[nombre]}
    </svg>
  );
}
