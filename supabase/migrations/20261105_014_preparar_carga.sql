-- Preparação para receber a base do sistema anterior.
-- Guarda o texto original de cargo do instrutor e departamento, que nem sempre bate com um cadastro.
alter table public.treinamentos add column cargo_instrutor_legado text, add column departamento_legado text;

-- Turmas antigas não geram lembrete ao ligar o n8n. Continuam visíveis no Dashboard.
insert into public.parametros (chave, valor, descricao, rotulo, grupo, tipo, ordem) values
  ('avisos_desde', '2026-11-05', 'Turmas com data anterior não geram lembrete automático. Continuam no Dashboard.', 'Lembretes para turmas a partir de', 'E-mails', 'data', 30);

create or replace function public.rotina_diaria() returns integer
language plpgsql security definer set search_path = public as $$
declare v integer := 0; n integer; v_desde date := (select valor::date from parametros where chave = 'avisos_desde');
begin
  insert into notificacoes (tipo, turma_id, destinatario)
  select 'lembrete_agenda', t.id, t.instrutor_email from turmas t
  where t.status = 'aguardando_instrutor' and t.data >= v_desde and t.criado_em + make_interval(days => app.param_int('prazo_resposta_instrutor_dias')) < now()
    and exists (select 1 from modelos_email m where m.tipo = 'lembrete_agenda' and m.ativo)
    and not exists (select 1 from turma_solicitacoes s where s.turma_id = t.id and s.status = 'aberta')
    and not exists (select 1 from notificacoes n where n.turma_id = t.id and n.tipo = 'lembrete_agenda' and n.criado_em > now() - interval '2 days');
  get diagnostics n = row_count; v := v + n;
  insert into notificacoes (tipo, turma_id, destinatario)
  select 'lembrete_presenca', t.id, t.instrutor_email from turmas t
  where t.status = 'convite_enviado' and t.data >= v_desde and upper(app.periodo_turma(t.id)) + make_interval(days => app.param_int('prazo_presenca_dias')) < now()
    and exists (select 1 from modelos_email m where m.tipo = 'lembrete_presenca' and m.ativo)
    and not exists (select 1 from notificacoes n where n.turma_id = t.id and n.tipo = 'lembrete_presenca' and n.criado_em > now() - interval '2 days');
  get diagnostics n = row_count;
  return v + n;
end $$;
