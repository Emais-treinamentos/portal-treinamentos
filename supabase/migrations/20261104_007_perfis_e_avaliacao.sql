-- Ajuste dos perfis: código único por presença, calendário do colaborador e avaliação confidencial.

-- Código único por participante, gerado no ok de presença do instrutor.
alter table public.turma_participantes add column codigo_presenca text unique;

create function app.novo_codigo_presenca() returns text language sql volatile set search_path = public as $$
  select upper(regexp_replace(substr(md5(gen_random_uuid()::text), 1, 16), '(.{4})(?=.)', '\1-', 'g'))
$$;

create function app.gatilho_codigo_presenca() returns trigger language plpgsql set search_path = public as $$
begin
  if new.situacao = 'presente' then
    new.codigo_presenca := coalesce(new.codigo_presenca, app.novo_codigo_presenca());
  else
    new.codigo_presenca := null;
  end if;
  return new;
end $$;
create trigger codigo_presenca before insert or update of situacao on public.turma_participantes for each row execute function app.gatilho_codigo_presenca();
update public.turma_participantes set codigo_presenca = app.novo_codigo_presenca() where situacao = 'presente' and codigo_presenca is null;

-- Avaliação confidencial. A pendência diz só quem ainda pode responder e some ao responder.
-- A resposta não guarda pessoa nem data e não entra no histórico de alterações.
create table public.avaliacao_pendentes (
  turma_id uuid not null references public.turmas on delete cascade,
  colaborador_id uuid not null references public.colaboradores on delete cascade,
  primary key (turma_id, colaborador_id)
);
create table public.avaliacao_respostas (
  id uuid primary key default gen_random_uuid(),
  turma_id uuid not null references public.turmas on delete cascade,
  nota integer not null check (nota between 1 and 5),
  pontualidade text not null check (pontualidade in ('horario', 'ate_15', 'mais_15')),
  conteudo text not null check (conteudo in ('sim', 'parte', 'nao')),
  instrutor text not null check (instrutor in ('sim', 'parte', 'nao')),
  tempo text not null check (tempo in ('sim', 'parte', 'nao')),
  local_material text not null check (local_material in ('sim', 'parte', 'nao')),
  melhorias text[] not null default '{}',
  comentario text
);
alter table public.avaliacao_pendentes enable row level security;
alter table public.avaliacao_respostas enable row level security;
revoke all on public.avaliacao_pendentes, public.avaliacao_respostas from anon, authenticated;

insert into public.avaliacao_pendentes (turma_id, colaborador_id)
select p.turma_id, p.colaborador_id from public.turma_participantes p join public.turmas t on t.id = p.turma_id
where p.situacao = 'presente' and t.status = 'realizada' and t.data >= (now() at time zone 'America/Sao_Paulo')::date - 30
on conflict do nothing;

-- Correção de presença depois de concluída acompanha a pendência.
create function app.gatilho_avaliacao_correcao() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from turmas where id = new.turma_id and presenca_concluida_em is not null) then return new; end if;
  if new.situacao = 'presente' and old.situacao <> 'presente' then
    insert into avaliacao_pendentes (turma_id, colaborador_id) values (new.turma_id, new.colaborador_id) on conflict do nothing;
  elsif old.situacao = 'presente' and new.situacao <> 'presente' then
    delete from avaliacao_pendentes where turma_id = new.turma_id and colaborador_id = new.colaborador_id;
  end if;
  return new;
end $$;
create trigger avaliacao_correcao after update of situacao on public.turma_participantes for each row execute function app.gatilho_avaliacao_correcao();

create or replace function public.concluir_presenca(p_turma uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas; v_presentes integer;
begin
  select * into t from turmas where id = p_turma for update;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not (app.eh_instrutor_da_turma(p_turma) or app.eh_admin()) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  if t.status <> 'convite_enviado' then raise exception 'Esta turma não está aberta para presença'; end if;
  if exists (select 1 from turma_participantes where turma_id = p_turma and situacao = 'convocado') then raise exception 'Marque presente ou ausente para todas as pessoas'; end if;
  select count(*) into v_presentes from turma_participantes where turma_id = p_turma and situacao = 'presente';
  update turmas set status = case when v_presentes > 0 then 'realizada'::status_turma else 'encerrada'::status_turma end, presenca_concluida_em = now() where id = p_turma;
  update notificacoes set status = 'cancelada' where turma_id = p_turma and status = 'pendente' and tipo = 'lembrete_presenca';
  insert into avaliacao_pendentes (turma_id, colaborador_id) select p_turma, p.colaborador_id from turma_participantes p where p.turma_id = p_turma and p.situacao = 'presente' on conflict do nothing;
  perform app.notificar('avaliacao_treinamento', p_turma, c.email) from turma_participantes p join colaboradores c on c.id = p.colaborador_id where p.turma_id = p_turma and p.situacao = 'presente' and c.email is not null;
end $$;

create or replace function public.situacao_colaborador(p_colaborador uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.pode_ver_colaborador(p_colaborador) then raise exception 'Sem acesso' using errcode = '42501'; end if;
  select jsonb_build_object(
    'colaborador', to_jsonb(c) || jsonb_build_object('cargo', cg.nome, 'departamento', d.nome, 'data_referencia', app.data_referencia(c.id)),
    'itens', (select coalesce(jsonb_agg(to_jsonb(s) order by s.treinamento), '[]') from app.situacao_base(c.id) s),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('turma_id', t.id, 'codigo', p.codigo_presenca, 'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'data', t.data, 'situacao', p.situacao, 'origem', p.origem, 'instrutor_email', t.instrutor_email, 'cargo', cp.nome) order by t.data desc nulls last), '[]')
                  from turma_participantes p join turmas t on t.id = p.turma_id join treinamentos tr on tr.id = t.treinamento_id left join cargos cp on cp.id = p.cargo_na_data_id
                  where p.colaborador_id = c.id and p.situacao in ('presente', 'ausente', 'a_validar', 'convocado')),
    'movimentacoes', (select coalesce(jsonb_agg(jsonb_build_object('cargo', cm.nome, 'data_inicio', m.data_inicio, 'data_fim', m.data_fim, 'tipo', m.tipo) order by m.data_inicio desc), '[]')
                      from movimentacoes m join cargos cm on cm.id = m.cargo_id where m.colaborador_id = c.id),
    'decisao', (select to_jsonb(x) from (select (app.decisao_vigente(c.id)).*) x where x.id is not null and (app.eh_admin() or c.id = app.meu_colaborador())))
  into r from colaboradores c left join cargos cg on cg.id = c.cargo_id left join departamentos d on d.id = c.departamento_id where c.id = p_colaborador;
  return r;
end $$;

create or replace function public.turma_detalhe(p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.pode_ver_turma(p_turma) then raise exception 'Sem acesso a esta turma' using errcode = '42501'; end if;
  select to_jsonb(t) || jsonb_build_object(
    'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'etapa', app.etapa_turma(t.status, app.periodo_turma(t.id)),
    'inicio', lower(app.periodo_turma(t.id)), 'fim', upper(app.periodo_turma(t.id)),
    'sou_instrutor', t.instrutor_email = app.meu_email(),
    'instrutor_tem_acesso', exists (select 1 from usuarios u where u.email = t.instrutor_email and u.ativo),
    'cargos', (select coalesce(jsonb_agg(jsonb_build_object('cargo_id', c.id, 'nome', c.nome, 'incluir', tc.incluir_no_convite,
                 'elegiveis', (select count(*) from app.elegiveis(t.id) e where e.cargo_id = c.id)) order by c.nome), '[]')
               from turma_cargos tc join cargos c on c.id = tc.cargo_id where tc.turma_id = t.id),
    'participantes', (select coalesce(jsonb_agg(jsonb_build_object('colaborador_id', c.id, 'nome', c.nome, 'cargo', cg.nome, 'situacao', p.situacao, 'origem', p.origem, 'codigo', p.codigo_presenca) order by c.nome), '[]')
               from turma_participantes p join colaboradores c on c.id = p.colaborador_id left join cargos cg on cg.id = p.cargo_na_data_id
               where p.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email() or app.pode_ver_colaborador(c.id))),
    'solicitacoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.solicitado_em desc), '[]') from turma_solicitacoes s where s.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email())),
    'conflitos', conflitos_turma(t.id))
  into r from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.id = p_turma;
  return r;
end $$;

create function public.minhas_avaliacoes() returns table (turma_id uuid, treinamento text, data date)
language sql stable security definer set search_path = public as $$
  select t.id, tr.nome, t.data from avaliacao_pendentes a join turmas t on t.id = a.turma_id join treinamentos tr on tr.id = t.treinamento_id
  where a.colaborador_id = app.meu_colaborador() order by t.data desc
$$;

create function public.enviar_avaliacao(p_turma uuid, p_nota integer, p_pontualidade text, p_conteudo text, p_instrutor text, p_tempo text, p_local text, p_melhorias text[] default '{}', p_comentario text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from avaliacao_pendentes where turma_id = p_turma and colaborador_id = app.meu_colaborador();
  if not found then raise exception 'Esta avaliação não está disponível para você'; end if;
  insert into avaliacao_respostas (turma_id, nota, pontualidade, conteudo, instrutor, tempo, local_material, melhorias, comentario)
  values (p_turma, p_nota, p_pontualidade, p_conteudo, p_instrutor, p_tempo, p_local, coalesce(p_melhorias, '{}'), nullif(trim(p_comentario), ''));
end $$;

-- Só o conjunto: com menos de 3 respostas o resultado fica oculto.
create function public.satisfacao(p_meses integer default 12, p_instrutor text default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb; v_inicio date := app.hoje() - make_interval(months => p_meses); v_instrutor text := nullif(lower(trim(p_instrutor)), '');
begin
  perform app.exigir_admin();
  with turmas_f as (
    select t.* from turmas t where t.data >= v_inicio and (v_instrutor is null or t.instrutor_email = v_instrutor)
  ), base as (
    select a.*, t.treinamento_id from avaliacao_respostas a join turmas_f t on t.id = a.turma_id
  ), presentes as (
    select t.treinamento_id, count(*) as n from turma_participantes p join turmas_f t on t.id = p.turma_id where p.situacao = 'presente' group by 1
  ), por as (
    select b.treinamento_id, count(*) as respostas,
      count(*) filter (where nota >= 4) as satisfeitos, round(avg(nota), 1) as media,
      count(*) filter (where pontualidade = 'horario') as horario, count(*) filter (where pontualidade = 'ate_15') as ate_15, count(*) filter (where pontualidade = 'mais_15') as mais_15,
      count(*) filter (where conteudo = 'sim') as conteudo, count(*) filter (where instrutor = 'sim') as instrutor,
      count(*) filter (where tempo = 'sim') as tempo, count(*) filter (where local_material = 'sim') as local_material
    from base b group by 1
  )
  select jsonb_build_object(
    'instrutores', (select coalesce(jsonb_agg(distinct t.instrutor_email), '[]') from avaliacao_respostas a join turmas t on t.id = a.turma_id where t.data >= v_inicio),
    'respostas', (select count(*) from base),
    'participantes', (select coalesce(sum(n), 0) from presentes),
    'satisfeitos', (select count(*) filter (where nota >= 4) from base),
    'no_horario', (select count(*) filter (where pontualidade = 'horario') from base),
    'treinamentos', (select coalesce(jsonb_agg(
        case when p.respostas < 3 then jsonb_build_object('id', p.treinamento_id, 'nome', tr.nome, 'respostas', p.respostas, 'participantes', coalesce(q.n, 0), 'oculto', true)
        else to_jsonb(p) || jsonb_build_object('id', p.treinamento_id, 'nome', tr.nome, 'participantes', coalesce(q.n, 0), 'oculto', false,
          'melhorias', (select coalesce(jsonb_agg(jsonb_build_object('nome', m.nome, 'n', m.n) order by m.n desc), '[]') from (select x.nome, count(*) as n from base b cross join lateral unnest(b.melhorias) x(nome) where b.treinamento_id = p.treinamento_id group by 1) m),
          'comentarios', (select coalesce(jsonb_agg(c.comentario), '[]') from (select b.comentario from base b where b.treinamento_id = p.treinamento_id and b.comentario is not null order by random()) c)) end
        order by tr.nome), '[]')
      from por p join treinamentos tr on tr.id = p.treinamento_id left join presentes q on q.treinamento_id = p.treinamento_id))
  into r;
  return r;
end $$;

-- Calendário do colaborador: turmas confirmadas em que ele está, com instrutor, sala e colegas.
create function public.meu_calendario() returns table (
  id uuid, treinamento text, status public.status_turma, etapa text, data date, hora time, carga_minutos integer, sala text, instrutor text, minha_situacao public.situacao_participante, participantes jsonb)
language sql stable security definer set search_path = public as $$
  select t.id, tr.nome, t.status, app.etapa_turma(t.status, app.periodo_turma(t.id)), t.data, coalesce(t.hora_inicio, t.hora_opcao_1), tr.carga_minutos, t.sala,
    coalesce((select u.nome from usuarios u where u.email = t.instrutor_email limit 1), (select c.nome from colaboradores c where lower(c.email) = t.instrutor_email limit 1), t.instrutor_email),
    eu.situacao,
    (select coalesce(jsonb_agg(c.nome order by c.nome), '[]') from turma_participantes p join colaboradores c on c.id = p.colaborador_id where p.turma_id = t.id and p.situacao <> 'nao_aplicavel')
  from turma_participantes eu join turmas t on t.id = eu.turma_id join treinamentos tr on tr.id = t.treinamento_id
  where eu.colaborador_id = app.meu_colaborador() and eu.situacao <> 'nao_aplicavel' and t.status in ('convite_enviado', 'realizada', 'encerrada')
  order by t.data
$$;
