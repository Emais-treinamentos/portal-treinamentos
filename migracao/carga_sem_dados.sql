-- Inclui a base no portal novo e tira os dados de teste. Tudo numa transação: se algo falhar, nada muda.
do $carga$
declare t text; v_tabelas text[];
begin
  select array_agg(c.relname::text) into v_tabelas from pg_trigger g join pg_class c on c.oid = g.tgrelid join pg_namespace n on n.oid = c.relnamespace
    where g.tgname = 'evento' and n.nspname = 'public' and c.relname not in ('parametros', 'modelos_email');
  foreach t in array v_tabelas loop execute format('alter table public.%I disable trigger evento', t); end loop;
  alter table public.colaboradores disable trigger sincroniza_turmas;

  -- Dados de teste
  delete from public.notificacoes; delete from public.avaliacao_pendentes; delete from public.avaliacao_respostas;
  alter table public.documentos_assinatura disable trigger documento_assinado;
  delete from public.documentos_assinatura; delete from public.avaliacoes_eficacia;
  alter table public.documentos_assinatura enable trigger documento_assinado;
  delete from public.turma_solicitacoes; delete from public.turma_participantes; delete from public.turma_cargos; delete from public.turmas;
  delete from public.reciclagem_decisoes; delete from public.matriz_vinculos; delete from public.matriz_revisoes;
  delete from public.movimentacoes; update public.usuarios set colaborador_id = null; delete from public.colaboradores;
  delete from public.usuarios_departamentos; delete from public.treinamentos; delete from public.cargos; delete from public.departamentos;
  delete from public.eventos;

  -- Leitura dos lotes
  create temp table lin on commit drop as
    select c.secao, l.i - 1 as idx, string_to_array(l.txt, '|') as f
    from (select secao, string_agg(txt, '' order by ordem) as tudo from carga.lotes group by secao) c
    cross join lateral string_to_table(c.tudo, E'\n') with ordinality as l(txt, i);
  create temp table mapa on commit drop as select secao, idx, gen_random_uuid() as id from lin where secao in ('dep','car','tre','col','rev','tur');
  create unique index on mapa (secao, idx);
  create temp table ref (k text) on commit drop;

  insert into public.departamentos (id, nome) select m.id, l.f[1] from lin l join mapa m using (secao, idx) where secao = 'dep';
  insert into public.departamentos (nome) select 'A DEFINIR' where exists (select 1 from lin where secao = 'car' and nullif(f[2], '') is null);
  insert into public.cargos (id, nome, departamento_id, ativo)
    select m.id, l.f[1], coalesce((select id from mapa where secao = 'dep' and idx = nullif(l.f[2], '')::int), (select id from public.departamentos where nome = 'A DEFINIR')), l.f[3] = '1'
    from lin l join mapa m using (secao, idx) where secao = 'car';
  insert into public.treinamentos (id, nome, carga_minutos, cargo_instrutor_id, cargo_backup_id, departamento_id, eh_politica, individual_por_colaborador, ativo, cargo_instrutor_legado, departamento_legado)
    select m.id, l.f[1], l.f[2]::int, (select id from mapa where secao = 'car' and idx = nullif(l.f[3], '')::int), (select id from mapa where secao = 'car' and idx = nullif(l.f[4], '')::int),
      (select id from mapa where secao = 'dep' and idx = nullif(l.f[5], '')::int), l.f[6] = '1', l.f[7] = '1', l.f[8] = '1', nullif(l.f[9], ''), nullif(l.f[10], '')
    from lin l join mapa m using (secao, idx) where secao = 'tre';
  insert into public.colaboradores (id, nome, email, cargo_id, departamento_id, data_admissao, ativo)
    select m.id, l.f[1], nullif(l.f[2], ''), (select id from mapa where secao = 'car' and idx = l.f[3]::int), (select id from mapa where secao = 'dep' and idx = l.f[4]::int), nullif(l.f[5], '')::date, l.f[6] = '1'
    from lin l join mapa m using (secao, idx) where secao = 'col';
  insert into public.movimentacoes (colaborador_id, cargo_id, departamento_id, data_inicio, data_fim, tipo)
    select (select id from mapa where secao = 'col' and idx = l.f[1]::int), (select id from mapa where secao = 'car' and idx = l.f[2]::int), (select id from mapa where secao = 'dep' and idx = nullif(l.f[3], '')::int),
      l.f[4]::date, nullif(l.f[5], '')::date, (case l.f[6] when 'a' then 'admissao' when 'p' then 'promocao' else 'transferencia' end)::public.tipo_movimentacao
    from lin l where secao = 'mov';
  insert into public.matriz_revisoes (id, numero, status, data_inicio_vigencia, descricao, criado_em, fechado_em)
    select m.id, l.f[1], (case l.f[2] when 'v' then 'vigente' else 'arquivada' end)::public.status_revisao, nullif(l.f[3], '')::date, nullif(l.f[4], ''), l.f[5]::timestamptz, nullif(l.f[6], '')::timestamptz
    from lin l join mapa m using (secao, idx) where secao = 'rev';
  insert into public.matriz_vinculos (cargo_id, treinamento_id, obrigatorio, revisao_criacao_id, revisao_remocao_id)
    select (select id from mapa where secao = 'car' and idx = l.f[4]::int), (select id from mapa where secao = 'tre' and idx = x.t::int), l.f[3] = '1',
      (select id from mapa where secao = 'rev' and idx = l.f[1]::int), (select id from mapa where secao = 'rev' and idx = nullif(l.f[2], '')::int)
    from lin l cross join lateral string_to_table(l.f[5], ' ') x(t) where secao = 'mat';

  insert into public.turmas (id, treinamento_id, status, tipo, data, hora_opcao_1, hora_opcao_2, hora_inicio, sala, instrutor_email, criado_em, convite_enviado_em, instrutor_respondeu_em, presenca_concluida_em)
    select m.id, (select id from mapa where secao = 'tre' and idx = l.f[1]::int),
      (case l.f[2] when 'r' then 'realizada' when 'e' then 'encerrada' when 'x' then 'cancelada' when 'c' then 'convite_enviado' when 'a' then 'agenda_confirmada' when 'g' then 'aguardando_instrutor' else 'precisa_replanejar' end)::public.status_turma,
      (case l.f[3] when 'c' then 'reciclagem' else 'normal' end)::public.tipo_turma,
      to_date(l.f[4], 'YYMMDD'), to_timestamp(nullif(l.f[5], ''), 'HH24MI')::time, to_timestamp(nullif(l.f[6], ''), 'HH24MI')::time,
      case l.f[7] when '=' then to_timestamp(l.f[5], 'HH24MI')::time else to_timestamp(nullif(l.f[7], ''), 'HH24MI')::time end,
      (select s.f[1] from lin s where s.secao = 'sal' and s.idx = nullif(l.f[8], '')::int), (select s.f[1] from lin s where s.secao = 'ins' and s.idx = l.f[9]::int),
      coalesce(to_date(nullif(l.f[10], ''), 'YYMMDD')::timestamptz, now()), to_date(nullif(l.f[11], ''), 'YYMMDD')::timestamptz, to_date(nullif(l.f[12], ''), 'YYMMDD')::timestamptz,
      case when l.f[2] in ('r', 'e') then coalesce(to_date(nullif(l.f[12], ''), 'YYMMDD'), to_date(l.f[4], 'YYMMDD'))::timestamptz end
    from lin l join mapa m using (secao, idx) where secao = 'tur';
  insert into public.turma_cargos (turma_id, cargo_id, incluir_no_convite)
    select (select id from mapa where secao = 'tur' and idx = l.f[1]::int), (select id from mapa where secao = 'car' and idx = x.c::int), l.f[2] = '1'
    from lin l cross join lateral string_to_table(l.f[3], ' ') x(c) where secao = 'tca'
    on conflict (turma_id, cargo_id) do update set incluir_no_convite = public.turma_cargos.incluir_no_convite or excluded.incluir_no_convite;
  insert into public.turma_participantes (turma_id, colaborador_id, cargo_na_data_id, situacao, origem, registrado_em)
    select tu.id, (select id from mapa where secao = 'col' and idx = l.f[2]::int), (select id from mapa where secao = 'car' and idx = nullif(l.f[3], '')::int),
      (case l.f[4] when 'p' then 'presente' when 'a' then 'ausente' else 'nao_aplicavel' end)::public.situacao_participante, 'legado_individual', tr.presenca_concluida_em
    from lin l join mapa tu on tu.secao = 'tur' and tu.idx = l.f[1]::int join public.turmas tr on tr.id = tu.id where l.secao = 'par';
  insert into public.reciclagem_decisoes (colaborador_id, cargo_anterior_id, cargo_atual_id, tipo_movimentacao, acao_sugerida, acao_final, treinamentos_parcial, decidido_em)
    select (select id from mapa where secao = 'col' and idx = l.f[1]::int), (select id from mapa where secao = 'car' and idx = nullif(l.f[2], '')::int), (select id from mapa where secao = 'car' and idx = nullif(l.f[3], '')::int),
      l.f[4]::public.reciclagem_tipo, nullif(l.f[5], '')::public.reciclagem_acao, l.f[6]::public.reciclagem_acao,
      coalesce((select array_agg((select id from mapa where secao = 'tre' and idx = x.t::int)) from string_to_table(nullif(l.f[7], ''), ' ') x(t)), '{}'), l.f[8]::timestamptz
    from lin l where secao = 'rec';

  update public.usuarios u set colaborador_id = (select c.id from public.colaboradores c where lower(c.email) = u.email order by c.ativo desc, c.nome limit 1);

  foreach t in array v_tabelas loop execute format('alter table public.%I enable trigger evento', t); end loop;
  alter table public.colaboradores enable trigger sincroniza_turmas;
end $carga$;
