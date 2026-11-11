-- Aba Notificações de Gente e Gestão: pedidos dos instrutores, comentários das avaliações e histórico.

-- Dia da resposta, sem hora, para não ajudar a descobrir quem respondeu.
alter table public.avaliacao_respostas add column respondido_em date default (now() at time zone 'America/Sao_Paulo')::date;

-- O que cada pessoa de Gente e Gestão já leu.
create table public.avisos_lidos (
  usuario_id uuid not null references public.usuarios on delete cascade,
  chave text not null,
  lido_em timestamptz not null default now(),
  primary key (usuario_id, chave)
);
alter table public.avisos_lidos enable row level security;
revoke all on public.avisos_lidos from anon, authenticated;

create function public.painel_notificacoes(p_dias integer default 60) returns jsonb
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

create function public.contar_notificacoes() returns integer
language sql stable security definer set search_path = public as $$
  select case when app.eh_admin() then
    (select count(*) from turma_solicitacoes where status = 'aberta')::integer
    + (select count(*) from avaliacao_respostas a join turmas t on t.id = a.turma_id
       where (a.comentario is not null or cardinality(a.melhorias) > 0) and coalesce(a.respondido_em, t.data) >= app.hoje() - 60
         and not exists (select 1 from avisos_lidos l where l.usuario_id = auth.uid() and l.chave = 'avaliacao:' || a.id))::integer
  else 0 end
$$;

create function public.marcar_lido(p_chaves text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  insert into avisos_lidos (usuario_id, chave) select auth.uid(), c from unnest(p_chaves) c on conflict do nothing;
end $$;

-- Correção de presença pedida pelo instrutor: Gente e Gestão ajusta as pessoas e decide em um passo só.
create function public.decidir_correcao_presenca(p_solicitacao uuid, p_aprovar boolean, p_resposta text, p_correcoes jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare s turma_solicitacoes; t turmas; c jsonb; v_n integer := 0; v_atual situacao_participante;
begin
  perform app.exigir_admin();
  select * into s from turma_solicitacoes where id = p_solicitacao for update;
  if not found or s.status <> 'aberta' then raise exception 'Esta solicitação não está mais aberta'; end if;
  if s.tipo <> 'correcao_presenca' then raise exception 'Esta solicitação não é de correção de presença'; end if;
  select * into t from turmas where id = s.turma_id;
  if p_aprovar then
    for c in select * from jsonb_array_elements(coalesce(p_correcoes, '[]')) loop
      select situacao into v_atual from turma_participantes where turma_id = s.turma_id and colaborador_id = (c->>'colaborador_id')::uuid;
      if v_atual is distinct from (c->>'situacao')::situacao_participante then
        perform corrigir_presenca(s.turma_id, (c->>'colaborador_id')::uuid, (c->>'situacao')::situacao_participante, 'Pedido do instrutor: ' || s.motivo);
        if c->>'situacao' = 'presente' then perform app.solicitar_lista_se_concluida((c->>'colaborador_id')::uuid); end if;
        v_n := v_n + 1;
      end if;
    end loop;
    if v_n = 0 then raise exception 'Nenhuma presença foi alterada. Para manter como está, recuse o pedido.'; end if;
  end if;
  update turma_solicitacoes set status = case when p_aprovar then 'aprovada'::status_solicitacao else 'recusada'::status_solicitacao end,
    resposta = nullif(trim(p_resposta), ''), decidido_por = auth.uid(), decidido_em = now() where id = s.id;
  perform app.notificar('aviso_decisao', s.turma_id, t.instrutor_email);
  return v_n;
end $$;

revoke all on function public.painel_notificacoes(integer), public.contar_notificacoes(), public.marcar_lido(text[]), public.decidir_correcao_presenca(uuid, boolean, text, jsonb) from public, anon;
grant execute on function public.painel_notificacoes(integer), public.contar_notificacoes(), public.marcar_lido(text[]), public.decidir_correcao_presenca(uuid, boolean, text, jsonb) to authenticated;
