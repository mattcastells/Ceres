-- 51 · Compra simulada de un plan (escenario de demostración).
--
-- En la demo, una cuenta del plan gratis toca "Pasarme a Premium" y la app
-- cambia en el momento: sin anuncios y con la IA. No hay cobro: es la pieza
-- que haría un sistema de pagos, simulada.
--
-- **Solo para cuentas de demostración**, reconocidas por el dominio del mail.
-- Una cuenta real que llame a esta función recibe un error: su plan no lo
-- cambia nadie desde un cliente.
create or replace function public.demo_switch_plan(p_plan text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  correo text;
begin
  if p_plan not in ('free', 'premium') then
    raise exception 'ERR_VALIDATION' using hint = 'Plan desconocido.';
  end if;

  select email into correo from auth.users where id = auth.uid();
  if correo is null or lower(correo) not like '%@demo.ceres.app' then
    raise exception 'ERR_FORBIDDEN' using hint = 'Solo las cuentas de demostración cambian de plan así.';
  end if;

  insert into public.account_plans (user_id, plan)
  values (auth.uid(), p_plan)
  on conflict (user_id) do update set plan = excluded.plan, updated_at = now();

  return public.effective_plan();
end $$;

revoke all on function public.demo_switch_plan(text) from public;
grant execute on function public.demo_switch_plan(text) to authenticated;
