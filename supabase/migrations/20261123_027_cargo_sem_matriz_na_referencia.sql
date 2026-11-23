-- Cargo que ainda não tinha matriz na data de referência (cargo novo): vale a primeira matriz publicada para o cargo.
create or replace function app.situacao_base(p_colaborador uuid default null) returns table (
  colaborador_id uuid, treinamento_id uuid, treinamento text, situacao text, turma_id uuid, data_turma date, ultima date)
language sql stable security definer set search_path = public as $$
  with base as (
    select b0.*, case when exists (select 1 from matriz_vigente_em(b0.cargo_id, coalesce(b0.ref0, app.hoje())))
      then b0.ref0 else coalesce((select min(r.data_inicio_vigencia) from matriz_vinculos v join matriz_revisoes r on r.id = v.revisao_criacao_id
        where v.cargo_id = b0.cargo_id and r.status = 'vigente' and r.data_inicio_vigencia > b0.ref0), b0.ref0) end as ref
    from (select c.id as colaborador_id, c.cargo_id, app.data_referencia(c.id) as ref0, app.decisao_vigente(c.id) as dec
      from colaboradores c where c.ativo and (p_colaborador is null or c.id = p_colaborador)) b0
  ), itens as (
    select b.colaborador_id, b.cargo_id, b.ref, b.dec, m.treinamento_id from base b cross join lateral matriz_vigente_em(b.cargo_id, coalesce(b.ref, app.hoje())) m where m.obrigatorio
    union
    select b.colaborador_id, b.cargo_id, b.ref, b.dec, x.t from base b cross join lateral unnest((b.dec).treinamentos_parcial) as x(t) where (b.dec).acao_final = 'parcial'
      and exists (select 1 from matriz_vigente_em(b.cargo_id, coalesce(b.ref, app.hoje())) m2 where m2.treinamento_id = x.t)
  )
  select i.colaborador_id, i.treinamento_id, tr.nome,
    case
      when (i.dec).acao_final = 'dispensa' then 'dispensado'
      when (i.dec).acao_final = 'parcial' and not (i.treinamento_id = any ((i.dec).treinamentos_parcial)) then case when u.ultima is null then 'dispensado' else 'realizado' end
      when (i.dec).acao_final is not null and not app.exigido_por_decisao(i.colaborador_id, i.treinamento_id) and u.ultima is not null then 'realizado'
      when (i.dec).acao_final is null and u.ultima is not null then 'realizado'
      when a.turma_id is not null then case when a.status = 'convite_enviado' then 'agendado' else 'planejado' end
      when app.ausente_sem_nova_turma(i.colaborador_id, i.treinamento_id) then 'ausente'
      else 'pendente' end,
    a.turma_id, a.data, u.ultima
  from itens i
  join treinamentos tr on tr.id = i.treinamento_id
  cross join lateral (select app.ultima_realizacao(i.colaborador_id, i.treinamento_id) as ultima) u
  left join lateral (
    select t.id as turma_id, t.status, t.data from turma_participantes p join turmas t on t.id = p.turma_id
    where p.colaborador_id = i.colaborador_id and t.treinamento_id = i.treinamento_id and p.situacao = 'convocado'
      and t.status in ('pendente', 'aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado')
    order by t.data limit 1) a on true
$$;

