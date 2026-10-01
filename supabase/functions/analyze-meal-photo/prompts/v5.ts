/// Prompt del análisis de foto, versión 5: el de v4 más la tabla SARA 2.
///
/// Las reglas para mirar el plato y estimar la porción son las mismas de v4; lo
/// que cambia es de dónde salen los valores cada 100 g. El modelo elige la fila
/// de la tabla oficial argentina y la cuenta se hace con esa fila (ver
/// `_shared/sara2.ts` y `fromTable` en `_shared/estimation.ts`).
import { PROMPT_V4 } from './v4.ts';
import { SARA2_PROMPT } from '../../_shared/sara2.ts';

export const PROMPT_V5 = `${PROMPT_V4}\n${SARA2_PROMPT}`;
