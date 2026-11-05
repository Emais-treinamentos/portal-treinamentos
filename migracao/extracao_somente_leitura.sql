-- Extração do banco atual (Gestão de Treinamentos). Só leitura: um único SELECT, nada é gravado.
-- Fica de fora: profiles (os acessos são criados de novo), matriz_temp e os valores de codigo_assinatura_instrutor
-- (só vai a informação de que existia, porque o portal novo gera um código por pessoa presente).
select jsonb_build_object(
  'extraido_em', now(),
  'departamentos', (select coalesce(jsonb_agg(to_jsonb(x) order by x.nome), '[]') from (select id, nome, created_at from public.departamentos) x),
  'cargos', (select coalesce(jsonb_agg(to_jsonb(x) order by x.nome, x.id), '[]') from (select id, nome, departamento_id, ativo, created_at from public.cargos) x),
  'treinamentos', (select coalesce(jsonb_agg(to_jsonb(x) order by x.nome, x.id), '[]') from (select id, nome, carga_horaria, cargo_instrutor, cargo_backup_id, departamento, eh_politica, individual_por_colaborador, ativo, created_at from public.treinamentos) x),
  'colaboradores', (select coalesce(jsonb_agg(to_jsonb(x) order by x.nome, x.id), '[]') from (select id, nome, email, cargo_id, departamento_id, data_admissao, ativo, created_at from public.colaboradores) x),
  'historico_cargos', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from (select id, id_colaborador, cargo_id, departamento_id, data_inicio, data_fim, tipo_movimentacao, created_at from public.historico_cargos) x),
  'matriz_revisoes', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]') from (select id, numero, status, data_inicio_vigencia, descricao, created_at, closed_at from public.matriz_revisoes) x),
  'cargos_treinamentos', (select coalesce(jsonb_agg(jsonb_build_array(x.id, x.cargo_id, x.treinamento_id, x.obrigatorio, x.revisao_criacao_id, x.revisao_remocao_id) order by x.id), '[]') from public.cargos_treinamentos x),
  'planejamentos', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]') from (select id, treinamento_id, tipo_planejamento, status, status_instrutor, consolidado, grupo_consolidado_id, email_instrutor, data_sugerida, horario_opcao_1, horario_opcao_2, data_confirmada, hora_confirmada, sala, data_confirmacao_instrutor, data_envio_convite, codigo_assinatura_instrutor is not null as tinha_codigo, created_at from public.planejamentos) x),
  'planejamento_cargos', (select coalesce(jsonb_agg(jsonb_build_array(x.id, x.planejamento_id, x.cargo_id, x.incluir_no_convite) order by x.id), '[]') from public.planejamento_cargos x),
  'presenca_colaborador', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from (select id, id_planejamento, id_colaborador, cargo_id, status, data_vinculo, codigo_assinatura_instrutor is not null as tinha_codigo, created_at from public.presenca_colaborador) x),
  'confirmacao_treinamento', (select coalesce(jsonb_agg(to_jsonb(x) order by x.id), '[]') from (select id, id_planejamento, id_colaborador, cargo_id, status, origem, data_confirmacao, grupo_consolidado_id, codigo_assinatura_instrutor is not null as tinha_codigo, created_at from public.confirmacao_treinamento) x),
  'reciclagem_decisoes', (select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at, x.id), '[]') from (select id, colaborador_id, cargo_anterior_id, cargo_atual_id, tipo_movimentacao_flag, acao_sugerida, acao_final, treinamentos_parcial, status, decidido_por, decidido_em, created_at from public.reciclagem_decisoes) x)
) as extracao;
