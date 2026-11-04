-- Vínculos que valem hoje, para mostrar as contagens em Cadastros.
create function public.matriz_vigente_hoje() returns table (cargo_id uuid, treinamento_id uuid)
language sql stable security definer set search_path = public as $$
  select c.id, m.treinamento_id from cargos c cross join lateral matriz_vigente_em(c.id, app.hoje()) m where app.eh_admin()
$$;
