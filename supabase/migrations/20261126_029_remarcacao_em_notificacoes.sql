-- Remarcação feita pelo instrutor dentro do prazo não espera decisão, mas precisa chegar a Gente e Gestão:
-- vira aviso em Notificações e conta no sino até cada pessoa dar ciência.

create or replace function public.painel_notificacoes(p_dias integer default 60) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_desde date := app.hoje() - greatest(coalesce(p_dias, 60), 1);
begin
  perform app.exigir_admin();
  return jsonb_build_object(
    'pedidos', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'tipo', s.tipo, 'motivo', s.motivo, 'proposta', s.proposta, 'solicitado_em', s.solicitado_em,
        'solicitante', coalesce(u.nome, u.email, 'Não identificado'),
        'turma_id', t.id, 'treinamento', tr.nome, 'data', t.data, 'hora', coalesce(t.hora_inicio, t.hora_opcao_1), 'sala', t.sala,
        'instrutor_email', t.instrutor_email, 'status_turma', t.status,
        'participantes', case when s.tipo = 'correcao_presenca' then (select coalesce(jsonb_agg(jsonb_build_object('colaborador_id', c.id, 'nome', c.nome, 'situacao', p.situacao) order by c.nome), '[]')
                            from turma_participantes p join colaboradores c on c.id = p.colaborador_id where p.turma_id = t.id and p.situacao in ('presente', 'ausente')) end
      ) order by s.solicitado_em), '[]')
      from turma_solicitacoes s join turmas t on t.id = s.turma_id join treinamentos tr on tr.id = t.treinamento_id left join usuarios u on u.id = s.solicitado_por
      where s.status = 'aberta'),
    'comentarios', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', a.id, 'treinamento', tr.nome, 'data', t.data, 'instrutor_email', t.instrutor_email, 'nota', a.nota,
        'melhorias', a.melhorias, 'comentario', a.comentario, 'respondido_em', a.respondido_em,
        'lido', exists (select 1 from avisos_lidos l where l.usuario_id = auth.uid() and l.chave = 'avaliacao:' || a.id)
      ) order by coalesce(a.respondido_em, t.data) desc, tr.nome), '[]')
      from avaliacao_respostas a join turmas t on t.id = a.turma_id join treinamentos tr on tr.id = t.treinamento_id
      where (a.comentario is not null or cardinality(a.melhorias) > 0) and coalesce(a.respondido_em, t.data) >= v_desde),
    'remarcacoes', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'motivo', s.motivo, 'proposta', s.proposta, 'decidido_em', s.decidido_em,
        'solicitante', coalesce(u.nome, u.email, 'Não identificado'),
        'turma_id', t.id, 'treinamento', tr.nome, 'data', t.data, 'hora', coalesce(t.hora_inicio, t.hora_opcao_1), 'status_turma', t.status, 'instrutor_email', t.instrutor_email,
        'lido', exists (select 1 from avisos_lidos l where l.usuario_id = auth.uid() and l.chave = 'remarcacao:' || s.id)
      ) order by s.decidido_em desc), '[]')
      from turma_solicitacoes s join turmas t on t.id = s.turma_id join treinamentos tr on tr.id = t.treinamento_id left join usuarios u on u.id = s.solicitado_por
      where s.status = 'aprovada' and s.tipo = 'alteracao' and s.resposta like 'Remarcado pelo instrutor%' and s.decidido_em >= v_desde),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', s.id, 'tipo', s.tipo, 'status', s.status, 'motivo', s.motivo, 'resposta', s.resposta, 'proposta', s.proposta,
        'solicitado_em', s.solicitado_em, 'decidido_em', s.decidido_em,
        'solicitante', coalesce(u.nome, u.email, 'Não identificado'), 'decidido_por', coalesce(d.nome, d.email),
        'automatico', s.decidido_por is not distinct from s.solicitado_por,
        'turma_id', t.id, 'treinamento', tr.nome, 'data', t.data
      ) order by s.decidido_em desc), '[]')
      from turma_solicitacoes s join turmas t on t.id = s.turma_id join treinamentos tr on tr.id = t.treinamento_id
      left join usuarios u on u.id = s.solicitado_por left join usuarios d on d.id = s.decidido_por
      where s.status <> 'aberta' and s.decidido_em >= v_desde)
  );
end $$;

create or replace function public.contar_notificacoes() returns integer
language sql stable security definer set search_path = public as $$
  select case when app.eh_admin() then
    (select count(*) from turma_solicitacoes where status = 'aberta')::integer
    + (select count(*) from avaliacao_respostas a join turmas t on t.id = a.turma_id
       where (a.comentario is not null or cardinality(a.melhorias) > 0) and coalesce(a.respondido_em, t.data) >= app.hoje() - 60
         and not exists (select 1 from avisos_lidos l where l.usuario_id = auth.uid() and l.chave = 'avaliacao:' || a.id))::integer
    + (select count(*) from turma_solicitacoes s
       where s.status = 'aprovada' and s.tipo = 'alteracao' and s.resposta like 'Remarcado pelo instrutor%' and s.decidido_em >= now() - interval '60 days'
         and not exists (select 1 from avisos_lidos l where l.usuario_id = auth.uid() and l.chave = 'remarcacao:' || s.id))::integer
  else 0 end
$$;
