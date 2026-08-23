-- 46 · El push de day_markers nunca pudo escribir.
--
-- La migración 40 le puso a `day_markers` un único **parcial**:
--
--     create unique index day_markers_uniq
--       on public.day_markers (user_id, local_date, kind)
--       where deleted_at is null;
--
-- y la app sube con `onConflict: 'user_id,local_date,kind'`, que PostgREST
-- traduce a `insert ... on conflict (user_id, local_date, kind) do update`.
-- Postgres **no infiere un índice parcial** para un `on conflict` que no
-- repita el predicado (`where deleted_at is null`), y PostgREST no tiene cómo
-- mandarlo: cada push de marcas moría con 42P10 —"no unique or exclusion
-- constraint matching the ON CONFLICT specification"—. Como el cliente aísla
-- el fallo por tabla (migración 30), todo lo demás sincronizaba y solo las
-- marcas se quedaban en el teléfono: un día de enfermedad marcado el 23 de
-- agosto no existía en la base.
--
-- Se notó recién ahora porque la tabla nunca tuvo tráfico real: `rest_days` no
-- se sincronizó nunca (lo dice la migración 40) y el contexto del día es de la
-- misma tanda. `water_logs`, `sleep_logs` y `reminders` siempre anduvieron
-- porque su único es un **constraint** sin predicado, que sí se infiere.
--
-- El arreglo es que el único sea total, lápidas incluidas. Cambia una cosa y
-- es deliberada: ya no puede haber una fila muerta y una viva para el mismo
-- (usuario, día, tipo). No hace falta: la app **revive** la lápida con el
-- mismo id en vez de insertar al lado (`setMarker` busca la marca enterrada), y
-- del lado del servidor el upsert que choca con una lápida la pisa y la revive,
-- que es exactamente lo que se quiere. La purga (redefinida en la 40, con
-- `day_markers` adentro) sigue levantando las lápidas a los 30 días.
--
-- El contrato queda probado en `sync_contract_test.sql`: el mismo
-- `on conflict` que manda la app, contra el esquema real.

-- Si algún día entraron duplicados (una viva y una muerta del mismo día y
-- tipo), queda la más nueva. Hoy es un no-op: la tabla está vacía en
-- producción, porque escribirla era justamente lo que fallaba.
delete from public.day_markers a
  using public.day_markers b
 where a.user_id = b.user_id
   and a.local_date = b.local_date
   and a.kind = b.kind
   and a.id <> b.id
   and (a.updated_at, a.id) < (b.updated_at, b.id);

drop index if exists public.day_markers_uniq;
create unique index day_markers_uniq
  on public.day_markers (user_id, local_date, kind);
