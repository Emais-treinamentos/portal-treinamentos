-- Planejar treinamentos como no sistema anterior: primeiro os cargos, depois os treinamentos
-- consolidados, cada um com data, horários e instrutor, e um único envio.

-- Quem já está convocado em outra turma aberta do mesmo treinamento não entra de novo.
create or replace function app.elegiveis(p_turma uuid)
returns table (colaborador_id uuid, cargo_id uuid)
language sql stable security definer set search_path = public as $$
  with t as (select *, coalesce(data, app.hoje()) as data_ref from turmas where id = p_turma)
  select c.id, c.cargo_id
  from t
  join turma_cargos tc on tc.turma_id = t.id and tc.incluir_no_convite
  join colaboradores c on c.cargo_id = tc.cargo_id and c.ativo
  cross join lateral (select app.data_referencia(c.id) as ref, app.ultima_realizacao(c.id, t.treinamento_id) as ultima) x
  where (
    app.ausente_sem_nova_turma(c.id, t.treinamento_id, t.id)
     or app.exigido_por_decisao(c.id, t.treinamento_id)
     or (
       exists (select 1 from matriz_vigente_em(c.cargo_id, x.ref) m where m.treinamento_id = t.treinamento_id)
       and coalesce((app.decisao_vigente(c.id)).acao_final, 'total') <> 'dispensa'
       and (
         (t.tipo = 'reciclagem' and x.ultima is not null and t.data_ref - x.ultima >= app.param_int('prazo_reciclagem_dias'))
         or (x.ultima is null and x.ref <= t.data_ref
             and x.ref >= least(t.criado_em::date, t.data_ref) - app.param_int('janela_convocacao_dias'))
       )))
    and not exists (
      select 1 from turma_participantes p join turmas o on o.id = p.turma_id
      where p.colaborador_id = c.id and p.situacao = 'convocado' and o.treinamento_id = t.treinamento_id and o.id <> t.id
        and o.status in ('pendente', 'aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado'))
$$;

-- Consolidação: turma ainda sem resposta do mesmo treinamento recebe os cargos e a agenda nova.
-- Turma já confirmada só é reaproveitada se a agenda for a mesma, e aí não há novo aviso.
create or replace function public.criar_turma(p_treinamento uuid, p_tipo public.tipo_turma, p_data date, p_hora_1 time, p_hora_2 time, p_instrutor_email text, p_cargos uuid[], p_origem uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text := lower(trim(p_instrutor_email)); v_individual boolean; v_notifica boolean := true; a turmas;
begin
  perform app.exigir_admin();
  if p_data is null or p_hora_1 is null then raise exception 'Informe a data e ao menos um horário'; end if;
  if v_email is null or v_email = '' then raise exception 'Informe o e-mail do instrutor'; end if;
  if p_hora_2 = p_hora_1 then p_hora_2 := null; end if;
  if coalesce(array_length(p_cargos, 1), 0) = 0 then raise exception 'Informe ao menos um cargo'; end if;
  select individual_por_colaborador into v_individual from treinamentos where id = p_treinamento and ativo;
  if not found then raise exception 'Treinamento inativo ou inexistente'; end if;

  if not v_individual then
    select * into a from turmas where treinamento_id = p_treinamento and status in ('pendente', 'aguardando_instrutor') order by criado_em limit 1 for update;
    if found then
      v_id := a.id;
      v_notifica := false;
      if a.data is distinct from p_data or a.hora_opcao_1 is distinct from p_hora_1 or a.hora_opcao_2 is distinct from p_hora_2 or a.instrutor_email is distinct from v_email then
        update turmas set data = p_data, hora_opcao_1 = p_hora_1, hora_opcao_2 = p_hora_2, instrutor_email = v_email, status = 'aguardando_instrutor' where id = v_id;
        update notificacoes set status = 'cancelada' where turma_id = v_id and status = 'pendente' and tipo in ('aviso_instrutor', 'lembrete_agenda');
        if a.instrutor_email is distinct from v_email and a.instrutor_email is not null then perform app.notificar('aviso_cancelamento', v_id, a.instrutor_email); end if;
        v_notifica := true;
      end if;
    else
      select id into v_id from turmas
      where treinamento_id = p_treinamento and data = p_data
        and ((status = 'agenda_confirmada' and instrutor_email = v_email)
          or (status = 'convite_enviado' and sala is not null and coalesce(hora_inicio, hora_opcao_1) = p_hora_1))
      order by criado_em limit 1;
      if v_id is not null then v_notifica := false; end if;
    end if;
  end if;

  if v_id is null then
    insert into turmas (treinamento_id, tipo, data, hora_opcao_1, hora_opcao_2, instrutor_email, turma_origem_id, criado_por)
    values (p_treinamento, p_tipo, p_data, p_hora_1, p_hora_2, v_email, p_origem, auth.uid()) returning id into v_id;
  elsif p_tipo = 'reciclagem' then
    update turmas set tipo = 'reciclagem' where id = v_id;
  end if;
  insert into turma_cargos (turma_id, cargo_id) select v_id, unnest(p_cargos)
  on conflict (turma_id, cargo_id) do update set incluir_no_convite = true;
  perform app.sincronizar_participantes(v_id);
  if v_notifica then perform app.notificar('aviso_instrutor', v_id, v_email); end if;
  return v_id;
end $$;

-- Treinamentos dos cargos escolhidos: matriz na data de referência de quem está na janela
-- (sem ninguém na janela, a matriz de hoje), mais a reciclagem pendente.
create function public.planejar_treinamentos(p_cargos uuid[])
returns table (chave text, treinamento_id uuid, treinamento text, tipo public.tipo_turma, individual boolean, cargos jsonb, pessoas jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_hoje date := app.hoje(); v_janela integer := app.param_int('janela_convocacao_dias');
begin
  perform app.exigir_admin();
  return query
  with fila as (select * from a_planejar()),
  pess as (
    select f.treinamento_id, e.p as pessoa, c.cargo_id
    from fila f cross join lateral jsonb_array_elements(f.pessoas) e(p)
    join colaboradores c on c.id = (e.p->>'colaborador_id')::uuid
    where c.cargo_id = any(p_cargos) or f.tipo = 'reciclagem'
  ),
  datas as (
    select cg.id as cargo_id, unnest(coalesce(
      (select array_agg(distinct r.ref) from (select app.data_referencia(c.id) as ref from colaboradores c where c.ativo and c.cargo_id = cg.id) r
       where r.ref between v_hoje - v_janela and v_hoje),
      array[v_hoje])) as dia
    from unnest(p_cargos) cg(id)
  ),
  par as (
    select d.cargo_id, m.treinamento_id from datas d cross join lateral matriz_vigente_em(d.cargo_id, d.dia) m
    union select p.cargo_id, p.treinamento_id from pess p
    union select (x.c->>'cargo_id')::uuid, f.treinamento_id from fila f cross join lateral jsonb_array_elements(f.cargos) x(c) where f.tipo = 'reciclagem'
  ),
  grupos as (
    select par.treinamento_id, case when tr.individual_por_colaborador then par.cargo_id end as cargo_grupo, array_agg(distinct par.cargo_id) as ids
    from par join treinamentos tr on tr.id = par.treinamento_id and tr.ativo
    group by 1, 2
  )
  select g.treinamento_id::text || coalesce('::' || g.cargo_grupo::text, ''), g.treinamento_id, tr.nome,
    coalesce((select f.tipo from fila f where f.treinamento_id = g.treinamento_id), 'normal'::public.tipo_turma),
    tr.individual_por_colaborador,
    (select jsonb_agg(jsonb_build_object('cargo_id', c.id, 'nome', c.nome) order by c.nome) from public.cargos c where c.id = any(g.ids)),
    coalesce((select jsonb_agg(p.pessoa order by p.pessoa->>'nome') from pess p where p.treinamento_id = g.treinamento_id and (g.cargo_grupo is null or p.cargo_id = g.cargo_grupo)), '[]'::jsonb)
  from grupos g join treinamentos tr on tr.id = g.treinamento_id
  order by tr.nome, 1;
end $$;

-- Envio único: ou todas as turmas saem, ou nenhuma.
create function public.enviar_planejamento(p_itens jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare i jsonb; v_id uuid; v_nome text; v_h1 time; v_h2 time; v_criadas integer := 0; v_consolidadas integer := 0; v_novo boolean;
begin
  perform app.exigir_admin();
  if coalesce(jsonb_array_length(p_itens), 0) = 0 then raise exception 'Escolha ao menos um treinamento'; end if;
  for i in select * from jsonb_array_elements(p_itens) loop
    select nome into v_nome from treinamentos where id = (i->>'treinamento_id')::uuid;
    if coalesce(i->>'data', '') = '' then raise exception 'Informe a data sugerida de %', v_nome; end if;
    if coalesce(i->>'hora_1', '') = '' and coalesce(i->>'hora_2', '') = '' then raise exception 'Informe ao menos um horário de %', v_nome; end if;
    if coalesce(trim(i->>'email'), '') = '' then raise exception 'Informe o e-mail do instrutor de %', v_nome; end if;
    v_h1 := coalesce(nullif(i->>'hora_1', ''), i->>'hora_2')::time;
    v_h2 := case when coalesce(i->>'hora_1', '') = '' then null else nullif(i->>'hora_2', '')::time end;
    v_id := criar_turma((i->>'treinamento_id')::uuid, coalesce(i->>'tipo', 'normal')::public.tipo_turma, (i->>'data')::date, v_h1, v_h2, i->>'email',
      array(select jsonb_array_elements_text(i->'cargos'))::uuid[]);
    select criado_em = now() into v_novo from turmas where id = v_id;
    if v_novo then v_criadas := v_criadas + 1; else v_consolidadas := v_consolidadas + 1; end if;
  end loop;
  return jsonb_build_object('criadas', v_criadas, 'consolidadas', v_consolidadas);
end $$;
