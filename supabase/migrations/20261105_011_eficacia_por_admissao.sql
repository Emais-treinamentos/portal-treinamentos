-- Avaliação de Eficácia só da admissão: 90 dias da data de admissão e uma por colaborador. Reciclagem não gera outra.
alter table public.avaliacoes_eficacia drop constraint avaliacoes_eficacia_colaborador_id_referencia_key;
alter table public.avaliacoes_eficacia add constraint uma_avaliacao_por_colaborador unique (colaborador_id);
insert into public.parametros (chave, valor, descricao) values
  ('eficacia_admissao_desde', '2026-01-01', 'A avaliação de eficácia vale para quem foi admitido a partir desta data')
on conflict (chave) do nothing;
update public.parametros set descricao = 'Dias depois da admissão para a avaliação de eficácia' where chave = 'prazo_eficacia_dias';

drop function public.eficacia_painel();
create function public.eficacia_painel() returns table (
  colaborador_id uuid, nome text, cargo text, departamento text, data_admissao date, data_prevista date, situacao text, realizados bigint, total bigint,
  avaliacao_id uuid, data_avaliacao date, avaliador text, resultado text, observacoes text)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_prazo integer := app.param_int('prazo_eficacia_dias'); v_desde date := (select valor::date from parametros where chave = 'eficacia_admissao_desde');
begin
  perform app.exigir_admin();
  return query
  select a.colaborador_id, c.nome, a.conteudo->'colaborador'->>'cargo', a.conteudo->'colaborador'->>'departamento', c.data_admissao, c.data_admissao + v_prazo, 'avaliada'::text,
    0::bigint, 0::bigint, a.id, a.data_avaliacao, a.avaliador, a.resultado, a.observacoes
  from avaliacoes_eficacia a join colaboradores c on c.id = a.colaborador_id
  union all
  select c.id, c.nome, cg.nome, d.nome, c.data_admissao, c.data_admissao + v_prazo, case when c.data_admissao + v_prazo <= app.hoje() then 'a_avaliar' else 'aguardando' end,
    x.feitos, x.todos, null::uuid, null::date, null::text, null::text, null::text
  from colaboradores c left join cargos cg on cg.id = c.cargo_id left join departamentos d on d.id = c.departamento_id
  cross join lateral (select count(*) filter (where s.situacao = 'realizado') as feitos, count(*) as todos from app.situacao_base(c.id) s) x
  where c.ativo and c.data_admissao >= v_desde and coalesce((app.decisao_vigente(c.id)).acao_final::text, '') <> 'dispensa'
    and not exists (select 1 from avaliacoes_eficacia a where a.colaborador_id = c.id);
end $$;

create or replace function public.fila_inicio() returns table (grupo text, urgente boolean, titulo text, detalhe text, turma_id uuid, colaborador_id uuid, solicitacao_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  return query
  select 'solicitacao', true, 'Solicitação de ' || tr.nome, s.motivo, t.id, null::uuid, s.id
  from turma_solicitacoes s join turmas t on t.id = s.turma_id join treinamentos tr on tr.id = t.treinamento_id where s.status = 'aberta'
  union all
  select 'replanejar', true, tr.nome || ': replanejar', t.motivo_replanejamento, t.id, null, null
  from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.status = 'precisa_replanejar'
  union all
  select 'presenca', upper(app.periodo_turma(t.id)) + make_interval(days => app.param_int('prazo_presenca_dias')) < now(), tr.nome || ': presença não registrada', 'Instrutor ' || t.instrutor_email, t.id, null, null
  from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.status = 'convite_enviado' and upper(app.periodo_turma(t.id)) < now()
  union all
  select 'formalizar', false, tr.nome || ': pronto para formalizar', case when t.sala is null then 'Falta escolher a sala' else 'Sala ' || t.sala end, t.id, null, null
  from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.status = 'agenda_confirmada'
  union all
  select 'sem_resposta', t.criado_em + make_interval(days => app.param_int('prazo_resposta_instrutor_dias')) < now(), tr.nome || ': aguardando instrutor', t.instrutor_email, t.id, null, null
  from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.status = 'aguardando_instrutor'
  union all
  select 'movimentacao', false, c.nome || ': classificar movimentação', cg.nome, null, c.id, null
  from colaboradores c left join cargos cg on cg.id = c.cargo_id where c.ativo and app.precisa_classificar(c.id)
  union all
  select 'a_planejar', false, p.treinamento || ': a planejar', jsonb_array_length(p.pessoas) || ' pessoa(s)', null, null, null
  from a_planejar() p
  union all
  select 'envio', true, 'Falha ao enviar notificação', n.tipo || ' para ' || n.destinatario, n.turma_id, null, null
  from notificacoes n where n.status = 'erro'
  union all
  select 'assinatura', false, c.nome || ': assinou ' || case d.tipo when 'termo_dispensa' then 'o Termo de Dispensa' else 'a Lista de Presença' end,
    'Assinado em ' || to_char(d.assinado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'), null, c.id, null
  from documentos_assinatura d join colaboradores c on c.id = d.colaborador_id where d.status = 'assinado' and d.baixado_em is null
  union all
  select 'eficacia', false, e.nome || ': avaliação de eficácia', 'Admitido em ' || to_char(e.data_admissao, 'DD/MM/YYYY'), null, e.colaborador_id, null
  from eficacia_painel() e where e.situacao = 'a_avaliar' and e.realizados > 0;
end $$;

create or replace function public.salvar_eficacia(p_colaborador uuid, p_data date, p_avaliador text, p_resultado text, p_observacoes text default null, p_id uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := p_id; v_fim date; v_adm date; v_prazo integer := app.param_int('prazo_eficacia_dias'); v_ref text; v_obs text := nullif(trim(p_observacoes), ''); v_avaliador text := nullif(trim(p_avaliador), '');
begin
  perform app.exigir_admin();
  if p_data is null or v_avaliador is null then raise exception 'Informe a data e o avaliador'; end if;
  if p_data > app.hoje() then raise exception 'A data da avaliação não pode estar no futuro'; end if;
  if p_resultado not in ('eficaz', 'parcial', 'nao_eficaz') then raise exception 'Informe o resultado'; end if;
  if p_resultado <> 'eficaz' and v_obs is null then raise exception 'Explique o resultado nas observações'; end if;
  select data_admissao into v_adm from colaboradores where id = p_colaborador;
  if v_adm is null then raise exception 'Este colaborador não tem data de admissão'; end if;
  if p_data < v_adm + v_prazo then raise exception 'A avaliação só abre em %', to_char(v_adm + v_prazo, 'DD/MM/YYYY'); end if;
  if p_id is not null then
    update avaliacoes_eficacia set data_avaliacao = p_data, avaliador = v_avaliador, resultado = p_resultado, observacoes = v_obs where id = p_id and colaborador_id = p_colaborador;
    if not found then raise exception 'Avaliação não encontrada'; end if;
  else
    if exists (select 1 from avaliacoes_eficacia where colaborador_id = p_colaborador) then raise exception 'Este colaborador já foi avaliado'; end if;
    v_fim := app.conclusao_grade(p_colaborador);
    if v_fim is null then raise exception 'Este colaborador ainda não tem treinamento concluído'; end if;
    v_ref := app.referencia_documento(p_colaborador, 'lista_presenca');
    insert into avaliacoes_eficacia (colaborador_id, referencia, data_conclusao, conteudo, data_avaliacao, avaliador, resultado, observacoes, registrado_por)
    values (p_colaborador, v_ref, v_fim, app.retrato_colaborador(p_colaborador), p_data, v_avaliador, p_resultado, v_obs, auth.uid()) returning id into v_id;
  end if;
  insert into eventos (tabela, registro_id, acao, depois, usuario) values ('avaliacoes_eficacia', v_id::text, case when p_id is null then 'criacao' else 'correcao' end,
    jsonb_build_object('data_avaliacao', p_data, 'avaliador', v_avaliador, 'resultado', p_resultado, 'observacoes', v_obs), auth.uid());
  return v_id;
end $$;

create or replace function public.eficacia_documento(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform app.exigir_admin();
  select to_jsonb(a) || jsonb_build_object('assinatura', (select to_jsonb(d) from documentos_assinatura d where d.colaborador_id = a.colaborador_id and d.tipo = 'lista_presenca' and d.status = 'assinado' order by (d.referencia = a.referencia) desc, d.assinado_em limit 1))
  into r from avaliacoes_eficacia a where a.id = p_id;
  if r is null then raise exception 'Avaliação não encontrada'; end if;
  return r;
end $$;

create or replace function public.eficacia_do_colaborador(p_colaborador uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  perform app.exigir_admin();
  select to_jsonb(a) - 'conteudo' into r from avaliacoes_eficacia a where a.colaborador_id = p_colaborador;
  return r;
end $$;
