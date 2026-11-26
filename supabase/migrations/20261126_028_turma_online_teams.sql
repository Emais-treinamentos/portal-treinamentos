-- Turma online pelo Teams: a sala "Online (Teams)" dispensa conflito de sala e gera evento no calendário do Outlook.
-- O evento sai por um fluxo próprio do n8n, a partir da fila calendario_eventos, que se ajusta sozinha a cada mudança na turma.

update parametros set valor = (select jsonb_agg(x)::text from (select jsonb_array_elements_text(valor::jsonb) x union select 'Online (Teams)') s)
  where chave = 'salas' and not valor::jsonb ? 'Online (Teams)';

alter table turmas add column if not exists link_reuniao text;

create or replace function app.eh_online(p_sala text) returns boolean language sql immutable as $$
  select coalesce(p_sala ilike 'online%' or p_sala ilike '%teams%', false)
$$;
-- Salas que comportam mais de uma turma ao mesmo tempo.
create or replace function app.sala_sem_conflito(p_sala text) returns boolean language sql immutable as $$
  select p_sala is null or p_sala = 'Externo' or app.eh_online(p_sala)
$$;

create or replace function public.conflitos_turma(p_turma uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with a as (select *, app.periodo_turma(id) as periodo from turmas where id = p_turma)
  select coalesce(jsonb_agg(x), '[]') from (
    select 'sala' as tipo, o.id as turma_id, tr.nome as treinamento
    from a join turmas o on o.id <> a.id and o.sala = a.sala and not app.sala_sem_conflito(a.sala) join treinamentos tr on tr.id = o.treinamento_id
    where o.status in ('agenda_confirmada', 'convite_enviado') and app.periodo_turma(o.id) && a.periodo
    union all
    select 'instrutor', o.id, tr.nome
    from a join turmas o on o.id <> a.id and o.instrutor_email = a.instrutor_email join treinamentos tr on tr.id = o.treinamento_id
    where o.status in ('agenda_confirmada', 'convite_enviado') and app.periodo_turma(o.id) && a.periodo
    union all
    select distinct 'participante', o.id, tr.nome
    from a join turma_participantes pa on pa.turma_id = a.id
    join turma_participantes po on po.colaborador_id = pa.colaborador_id and po.turma_id <> a.id
    join turmas o on o.id = po.turma_id join treinamentos tr on tr.id = o.treinamento_id
    where o.status in ('agenda_confirmada', 'convite_enviado') and app.periodo_turma(o.id) && a.periodo
  ) x
$$;

create or replace function public.verificar_novo_horario(p_turma uuid, p_data date default null, p_hora time default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t turmas; v_carga integer; v_limite date := app.limite_remarcacao(p_turma); v_aberto boolean; v_per tstzrange;
  v_pessoas jsonb; v_instrutor jsonb; v_sala jsonb; v_passado boolean; v_fora boolean; v_igual boolean; v_antes text;
begin
  select * into t from turmas where id = p_turma;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not (app.eh_instrutor_da_turma(p_turma) or app.eh_admin()) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  v_aberto := v_limite is null or v_limite >= app.hoje();
  if p_data is null or p_hora is null then
    return jsonb_build_object('ok', false, 'limite', v_limite, 'prazo_aberto', v_aberto, 'indisponiveis', '[]'::jsonb, 'instrutor', '[]'::jsonb, 'sala', '[]'::jsonb);
  end if;
  select carga_minutos into v_carga from treinamentos where id = t.treinamento_id;
  v_per := tstzrange((p_data + p_hora) at time zone 'America/Sao_Paulo', ((p_data + p_hora) at time zone 'America/Sao_Paulo') + make_interval(mins => v_carga));
  v_passado := lower(v_per) <= now();
  v_fora := v_limite is not null and p_data > v_limite;
  v_igual := t.data = p_data and t.hora_inicio = p_hora;
  -- Antes da admissão a pessoa sairia da turma sem ninguém perceber.
  select string_agg(c.nome, ', ' order by c.nome) into v_antes from turma_participantes p join colaboradores c on c.id = p.colaborador_id
    where p.turma_id = p_turma and p.situacao = 'convocado' and app.data_referencia(p.colaborador_id) > p_data;

  select coalesce(jsonb_agg(x order by x.nome, x.inicio), '[]') into v_pessoas from (
    select distinct c.nome, oc.treinamento, to_char(oc.inicio, 'HH24:MI') as inicio, to_char(oc.fim, 'HH24:MI') as fim, oc.confirmada
    from turma_participantes pa join colaboradores c on c.id = pa.colaborador_id
    join turma_participantes po on po.colaborador_id = pa.colaborador_id and po.situacao <> 'nao_aplicavel'
    join app.turmas_ocupadas(p_turma, p_data) oc on oc.id = po.turma_id and oc.periodo && v_per
    where pa.turma_id = p_turma and pa.situacao = 'convocado') x;
  select coalesce(jsonb_agg(x order by x.inicio), '[]') into v_instrutor from (
    select distinct oc.treinamento, to_char(oc.inicio, 'HH24:MI') as inicio, to_char(oc.fim, 'HH24:MI') as fim
    from app.turmas_ocupadas(p_turma, p_data) oc where oc.instrutor_email = t.instrutor_email and oc.periodo && v_per) x;
  select coalesce(jsonb_agg(x order by x.inicio), '[]') into v_sala from (
    select distinct oc.treinamento, to_char(oc.inicio, 'HH24:MI') as inicio, to_char(oc.fim, 'HH24:MI') as fim
    from app.turmas_ocupadas(p_turma, p_data) oc where not app.sala_sem_conflito(t.sala) and oc.sala = t.sala and oc.confirmada and oc.periodo && v_per) x;

  return jsonb_build_object(
    'ok', v_aberto and not v_passado and not v_fora and not v_igual and v_antes is null and jsonb_array_length(v_pessoas) = 0 and jsonb_array_length(v_instrutor) = 0 and jsonb_array_length(v_sala) = 0,
    'limite', v_limite, 'prazo_aberto', v_aberto, 'passado', v_passado, 'fora_do_prazo', v_fora, 'igual', v_igual, 'antes_da_admissao', v_antes,
    'indisponiveis', v_pessoas, 'instrutor', v_instrutor, 'sala', v_sala);
end $$;

create or replace function app.montar_email(p_tipo text, p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m modelos_email; t turmas; v_trein text; v_carga integer; v_ini time; v_hor text; v_part text; v_url text;
  v_assunto text; v_corpo text; c record; v_vars jsonb;
begin
  select * into m from modelos_email where tipo = p_tipo;
  select valor into v_url from parametros where chave = 'url_portal';
  if p_turma is not null then
    select * into t from turmas where id = p_turma;
    select nome, carga_minutos into v_trein, v_carga from treinamentos where id = t.treinamento_id;
    v_ini := t.hora_inicio;
    v_hor := case
      when t.hora_inicio is not null then to_char(t.hora_inicio, 'HH24:MI') || ' às ' || to_char(t.hora_inicio + make_interval(mins => v_carga), 'HH24:MI')
      when t.hora_opcao_1 is not null and t.hora_opcao_2 is not null then to_char(t.hora_opcao_1, 'HH24:MI') || ' ou ' || to_char(t.hora_opcao_2, 'HH24:MI')
      when t.hora_opcao_1 is not null then to_char(t.hora_opcao_1, 'HH24:MI')
      else 'A definir' end;
    select string_agg(concat_ws(' - ', cg.nome, co.nome), E'\n' order by co.nome) into v_part
    from turma_participantes p join colaboradores co on co.id = p.colaborador_id
    left join cargos cg on cg.id = coalesce(p.cargo_na_data_id, co.cargo_id)
    where p.turma_id = p_turma and p.situacao <> 'nao_aplicavel';
  end if;
  v_vars := jsonb_build_object(
    'treinamento', coalesce(v_trein, ''),
    'data', coalesce(to_char(t.data, 'DD/MM/YYYY'), 'A definir'),
    'horario', coalesce(v_hor, 'A definir'),
    'inicio', coalesce(to_char(coalesce(v_ini, t.hora_opcao_1), 'HH24:MI'), 'A definir'),
    'sala', case when app.eh_online(t.sala) then 'Online pelo Microsoft Teams (o link está no convite do Outlook)' else coalesce(t.sala, 'A definir') end,
    'participantes', coalesce(v_part, 'A definir'));
  v_assunto := m.assunto;
  v_corpo := app.escapar_html(m.corpo);
  for c in select * from jsonb_each_text(v_vars) loop
    v_assunto := replace(v_assunto, '{' || c.key || '}', c.value);
    v_corpo := replace(v_corpo, '{' || c.key || '}', app.escapar_html(c.value));
  end loop;
  v_assunto := regexp_replace(replace(v_assunto, '{link}', v_url), '[\r\n]+', ' ', 'g');
  v_corpo := replace(v_corpo, E'\n', '<br>');
  v_corpo := replace(v_corpo, '{link}', '<a href="' || app.escapar_html(v_url) || '" style="display:inline-block;background:#006666;color:#ffffff;padding:10px 18px;border-radius:6px;text-decoration:none;font-weight:600">Acessar o portal</a>');
  return jsonb_build_object('assunto', v_assunto, 'corpo_html', '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1d2f2c">' || v_corpo || '</div>');
end $$;

create table calendario_eventos (
  id bigserial primary key,
  turma_id uuid not null references turmas(id) on delete cascade,
  acao text not null check (acao in ('criar', 'atualizar', 'cancelar')),
  status text not null default 'pendente' check (status in ('pendente', 'processando', 'feito', 'erro', 'descartado')),
  tentativas integer not null default 0,
  erro text,
  criado_em timestamptz not null default now(),
  processado_em timestamptz
);
create index on calendario_eventos (turma_id, status);
alter table calendario_eventos enable row level security;
create policy calendario_admin on calendario_eventos for select to authenticated using (app.eh_admin());
grant select on calendario_eventos to authenticated;

-- Compara o que a turma pede (online e convocada) com o que já existe no Outlook e deixa na fila só a ação que falta.
create or replace function app.sincronizar_calendario(p_turma uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas; v_quer boolean; v_tem boolean;
begin
  select * into t from turmas where id = p_turma;
  if not found then return; end if;
  v_quer := t.status = 'convite_enviado' and app.eh_online(t.sala);
  v_tem := t.outlook_evento_id is not null
    or exists (select 1 from calendario_eventos where turma_id = p_turma and acao = 'criar' and status = 'processando');
  if v_quer then
    update calendario_eventos set status = 'descartado', processado_em = now() where turma_id = p_turma and status = 'pendente' and acao = 'cancelar';
    if not exists (select 1 from calendario_eventos where turma_id = p_turma and status = 'pendente') then
      insert into calendario_eventos (turma_id, acao) values (p_turma, case when v_tem then 'atualizar' else 'criar' end);
    end if;
  else
    update calendario_eventos set status = 'descartado', processado_em = now() where turma_id = p_turma and status = 'pendente' and acao in ('criar', 'atualizar');
    if v_tem and not exists (select 1 from calendario_eventos where turma_id = p_turma and status = 'pendente' and acao = 'cancelar') then
      insert into calendario_eventos (turma_id, acao) values (p_turma, 'cancelar');
    end if;
  end if;
end $$;

create or replace function app.gatilho_calendario_turma() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'convite_enviado' or old.status = 'convite_enviado' or new.outlook_evento_id is not null then
    perform app.sincronizar_calendario(new.id);
  end if;
  return null;
end $$;
create trigger calendario_turma after update of status, data, hora_inicio, sala, instrutor_email on turmas
  for each row when (old.status is distinct from new.status or old.data is distinct from new.data or old.hora_inicio is distinct from new.hora_inicio
    or old.sala is distinct from new.sala or old.instrutor_email is distinct from new.instrutor_email)
  execute function app.gatilho_calendario_turma();

create or replace function app.gatilho_calendario_participante() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_turma uuid := coalesce(new.turma_id, old.turma_id);
begin
  if tg_op = 'UPDATE' and old.situacao is not distinct from new.situacao then return null; end if;
  if exists (select 1 from turmas where id = v_turma and status = 'convite_enviado' and (app.eh_online(sala) or outlook_evento_id is not null)) then
    perform app.sincronizar_calendario(v_turma);
  end if;
  return null;
end $$;
create trigger calendario_participante after insert or update of situacao or delete on turma_participantes
  for each row execute function app.gatilho_calendario_participante();

-- Detalhe da turma com a situação do convite do Teams, para Gente e Gestão.
create or replace function public.turma_detalhe(p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.pode_ver_turma(p_turma) then raise exception 'Sem acesso a esta turma' using errcode = '42501'; end if;
  select to_jsonb(t) || jsonb_build_object(
    'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'etapa', app.etapa_turma(t.status, app.periodo_turma(t.id)),
    'inicio', lower(app.periodo_turma(t.id)), 'fim', upper(app.periodo_turma(t.id)),
    'sou_instrutor', t.instrutor_email = app.meu_email(),
    'instrutor_tem_acesso', exists (select 1 from usuarios u where u.email = t.instrutor_email and u.ativo and u.perfil in ('instrutor', 'admin', 'gestor')),
    'cargos', (select coalesce(jsonb_agg(jsonb_build_object('cargo_id', c.id, 'nome', c.nome, 'incluir', tc.incluir_no_convite,
                 'elegiveis', (select count(*) from app.elegiveis(t.id) e where e.cargo_id = c.id)) order by c.nome), '[]')
               from turma_cargos tc join cargos c on c.id = tc.cargo_id where tc.turma_id = t.id),
    'participantes', (select coalesce(jsonb_agg(jsonb_build_object('colaborador_id', c.id, 'nome', c.nome, 'cargo', cg.nome, 'situacao', p.situacao, 'origem', p.origem, 'codigo', p.codigo_presenca) order by c.nome), '[]')
               from turma_participantes p join colaboradores c on c.id = p.colaborador_id left join cargos cg on cg.id = p.cargo_na_data_id
               where p.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email() or app.pode_ver_colaborador(c.id))),
    'solicitacoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.solicitado_em desc), '[]') from turma_solicitacoes s where s.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email())),
    'calendario', case when app.le_tudo() then (select jsonb_build_object('acao', e.acao, 'status', e.status, 'erro', e.erro, 'quando', coalesce(e.processado_em, e.criado_em)) from calendario_eventos e where e.turma_id = t.id order by e.id desc limit 1) end,
    'conflitos', conflitos_turma(t.id))
  into r from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.id = p_turma;
  return r;
end $$;

-- Para o n8n: entrega os eventos a processar, um por turma, já com tudo o que o Outlook precisa.
create or replace function public.calendario_para_processar(p_limite integer default 20) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  update calendario_eventos set status = 'pendente' where status = 'processando' and processado_em < now() - interval '15 minutes';
  -- Cancelar o que nunca chegou ao Outlook não tem o que fazer.
  update calendario_eventos e set status = 'descartado', processado_em = now() where e.status = 'pendente' and e.acao = 'cancelar'
    and not exists (select 1 from turmas t where t.id = e.turma_id and t.outlook_evento_id is not null)
    and not exists (select 1 from calendario_eventos o where o.turma_id = e.turma_id and o.status = 'processando');
  with fila as (
    select distinct on (e.turma_id) e.id from calendario_eventos e join turmas t on t.id = e.turma_id
    where e.status = 'pendente'
      and not exists (select 1 from calendario_eventos o where o.turma_id = e.turma_id and o.status = 'processando')
      and (e.acao = 'criar' or t.outlook_evento_id is not null)
    order by e.turma_id, e.criado_em
  ), escolhidos as (
    update calendario_eventos e set status = 'processando', processado_em = now()
    where e.id in (select id from fila order by id limit p_limite) returning e.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id, 'acao', e.acao, 'evento_id', t.outlook_evento_id,
      'assunto', 'Treinamento: ' || tr.nome,
      'inicio', to_char(lower(app.periodo_turma(t.id)) at time zone 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS'),
      'fim', to_char(upper(app.periodo_turma(t.id)) at time zone 'America/Sao_Paulo', 'YYYY-MM-DD"T"HH24:MI:SS'),
      'fuso', 'America/Sao_Paulo',
      'corpo_html', '<p>Treinamento <b>' || app.escapar_html(tr.nome) || '</b>, online pelo Microsoft Teams.</p><p>Instrutor: '
        || app.escapar_html(coalesce((select nome from usuarios u where lower(u.email) = lower(t.instrutor_email)), t.instrutor_email, ''))
        || '<br>Carga horária: ' || tr.carga_minutos || ' minutos</p><p>Use o link do Teams deste convite para entrar no horário marcado.</p>',
      'participantes', (
        select coalesce(jsonb_agg(jsonb_build_object('email', x.email, 'nome', x.nome, 'tipo', x.tipo) order by x.tipo, x.nome), '[]') from (
          select lower(t.instrutor_email) email, coalesce((select nome from usuarios u where lower(u.email) = lower(t.instrutor_email)), t.instrutor_email) nome, 'required' tipo
          where t.instrutor_email is not null
          union
          select lower(c.email), c.nome, 'required' from turma_participantes p join colaboradores c on c.id = p.colaborador_id
          where p.turma_id = t.id and p.situacao = 'convocado' and c.email ~ '@' and lower(c.email) <> lower(coalesce(t.instrutor_email, ''))
        ) x)
    ) order by e.id), '[]') into v
  from escolhidos e join turmas t on t.id = e.turma_id join treinamentos tr on tr.id = t.treinamento_id;
  return v;
end $$;

-- Para o n8n: devolve o resultado de cada evento.
create or replace function public.registrar_calendario(p_id bigint, p_ok boolean, p_erro text default null, p_evento_id text default null, p_link text default null) returns void
language plpgsql security definer set search_path = public as $$
declare e calendario_eventos;
begin
  select * into e from calendario_eventos where id = p_id for update;
  if not found then return; end if;
  if p_ok then
    if e.acao = 'criar' then update turmas set outlook_evento_id = p_evento_id, link_reuniao = p_link where id = e.turma_id;
    elsif e.acao = 'atualizar' then update turmas set link_reuniao = coalesce(p_link, link_reuniao) where id = e.turma_id;
    else update turmas set outlook_evento_id = null, link_reuniao = null where id = e.turma_id; end if;
    -- O que mudou durante o processamento já entrou na fila pelos gatilhos.
    update calendario_eventos set status = 'feito', erro = null, processado_em = now() where id = p_id;
  else
    update calendario_eventos set tentativas = tentativas + 1, erro = left(p_erro, 500), processado_em = now(),
      status = case when tentativas + 1 >= 3 then 'erro' else 'pendente' end where id = p_id;
  end if;
end $$;

revoke all on function public.calendario_para_processar(integer), public.registrar_calendario(bigint, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.calendario_para_processar(integer), public.registrar_calendario(bigint, boolean, text, text, text) to service_role;
