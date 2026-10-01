/// Prompt de la estimación por texto, versión 3: el de v2 más la tabla SARA 2.
///
/// Par de `analyze-meal-photo/prompts/v5.ts`: las porciones de referencia y las
/// reglas de v2 siguen igual; los valores cada 100 g salen de la fila de la
/// tabla oficial que elija el modelo (ver `_shared/sara2.ts`).
import { PROMPT_TEXT_V2 } from './text_v2.ts';
import { SARA2_PROMPT } from '../../_shared/sara2.ts';

export const PROMPT_TEXT_V3 = `${PROMPT_TEXT_V2}\n${SARA2_PROMPT}`;
