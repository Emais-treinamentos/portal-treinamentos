-- Assinatura eletrônica no portal: Termo de Dispensa e Lista de Presença (F.109).
-- O documento é congelado na solicitação. A assinatura guarda quem, quando, de onde e não pode ser alterada.
create table public.documentos_assinatura (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores on delete restrict,
  tipo text not null check (tipo in ('termo_dispensa', 'lista_presenca')),
  conteudo jsonb not null,
  referencia text not null,
  hash text not null,
  status text not null default 'pendente' check (status in ('pendente', 'assinado', 'cancelado')),
  solicitado_por uuid,
  solicitado_em timestamptz not null default now(),
  assinado_em timestamptz,
  assinatura_imagem text,
  assinatura_nome text,
  assinatura_email text,
  assinatura_ip text,
  assinatura_navegador text,
  baixado_em timestamptz
);
create unique index on public.documentos_assinatura (colaborador_id, tipo) where status = 'pendente';
alter table public.documentos_assinatura enable row level security;
revoke all on public.documentos_assinatura from anon, authenticated;

create function app.gatilho_documento_assinado() returns trigger language plpgsql set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.status = 'assinado' then raise exception 'Documento assinado não pode ser apagado'; end if;
    return old;
  end if;
  if old.status = 'assinado' and (to_jsonb(new) - 'baixado_em') is distinct from (to_jsonb(old) - 'baixado_em') then
    raise exception 'Documento assinado não pode ser alterado';
  end if;
  return new;
end $$;
create trigger documento_assinado before update or delete on public.documentos_assinatura for each row execute function app.gatilho_documento_assinado();

-- Retrato do documento na data da solicitação.
create function app.retrato_colaborador(p_colaborador uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'colaborador', to_jsonb(c) || jsonb_build_object('cargo', cg.nome, 'departamento', d.nome, 'data_referencia', app.data_referencia(c.id)),
    'itens', (select coalesce(jsonb_agg(to_jsonb(s) order by s.treinamento), '[]') from app.situacao_base(c.id) s),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('turma_id', t.id, 'codigo', p.codigo_presenca, 'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'data', t.data, 'situacao', p.situacao, 'origem', p.origem, 'instrutor_email', t.instrutor_email, 'cargo', cp.nome) order by t.data desc nulls last), '[]')
                  from turma_participantes p join turmas t on t.id = p.turma_id join treinamentos tr on tr.id = t.treinamento_id left join cargos cp on cp.id = p.cargo_na_data_id
                  where p.colaborador_id = c.id and p.situacao = 'presente'),
    'movimentacoes', (select coalesce(jsonb_agg(jsonb_build_object('cargo', cm.nome, 'data_inicio', m.data_inicio, 'data_fim', m.data_fim, 'tipo', m.tipo) order by m.data_inicio desc), '[]')
                      from movimentacoes m join cargos cm on cm.id = m.cargo_id where m.colaborador_id = c.id),
    'decisao', (select to_jsonb(x) from (select (app.decisao_vigente(c.id)).*) x where x.id is not null))
  from colaboradores c left join cargos cg on cg.id = c.cargo_id left join departamentos d on d.id = c.departamento_id where c.id = p_colaborador
$$;

create function app.grade_concluida(p_colaborador uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((app.decisao_vigente(p_colaborador)).acao_final, 'total') <> 'dispensa'
    and exists (select 1 from app.situacao_base(p_colaborador) s where s.situacao = 'realizado')
    and not exists (select 1 from app.situacao_base(p_colaborador) s where s.situacao in ('pendente', 'ausente', 'agendado', 'planejado'))
$$;

-- A referência identifica o que está sendo assinado: as presenças da lista ou a decisão do termo.
create function app.referencia_documento(p_colaborador uuid, p_tipo text) returns text language sql stable security definer set search_path = public as $$
  select case when p_tipo = 'termo_dispensa' then (app.decisao_vigente(p_colaborador)).id::text
    else (select string_agg(p.codigo_presenca, ',' order by p.codigo_presenca) from turma_participantes p where p.colaborador_id = p_colaborador and p.situacao = 'presente') end
$$;

create function app.criar_documento_assinatura(p_colaborador uuid, p_tipo text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_doc jsonb := app.retrato_colaborador(p_colaborador); v_ref text := app.referencia_documento(p_colaborador, p_tipo); v_email text;
begin
  update documentos_assinatura set status = 'cancelado' where colaborador_id = p_colaborador and tipo = p_tipo and status = 'pendente';
  insert into documentos_assinatura (colaborador_id, tipo, conteudo, referencia, hash, solicitado_por)
  values (p_colaborador, p_tipo, v_doc, coalesce(v_ref, ''), encode(sha256(convert_to(v_doc::text, 'UTF8')), 'hex'), auth.uid()) returning id into v_id;
  select email into v_email from colaboradores where id = p_colaborador;
  perform app.notificar('assinatura_solicitada', null, v_email);
  return v_id;
end $$;

create function app.documento_ja_tratado(p_colaborador uuid, p_tipo text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from documentos_assinatura d where d.colaborador_id = p_colaborador and d.tipo = p_tipo and d.status in ('pendente', 'assinado')
                 and d.referencia = coalesce(app.referencia_documento(p_colaborador, p_tipo), ''))
$$;

-- Concluiu toda a grade: a lista vai para assinatura sozinha.
create function app.solicitar_lista_se_concluida(p_colaborador uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if app.grade_concluida(p_colaborador) and not app.documento_ja_tratado(p_colaborador, 'lista_presenca') then
    perform app.criar_documento_assinatura(p_colaborador, 'lista_presenca');
  end if;
end $$;

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
  perform app.solicitar_lista_se_concluida(p.colaborador_id) from turma_participantes p where p.turma_id = p_turma and p.situacao = 'presente';
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
  from documentos_assinatura d join colaboradores c on c.id = d.colaborador_id where d.status = 'assinado' and d.baixado_em is null;
end $$;

create function public.solicitar_assinatura(p_colaborador uuid, p_tipo text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  if p_tipo not in ('termo_dispensa', 'lista_presenca') then raise exception 'Documento inválido'; end if;
  if p_tipo = 'termo_dispensa' and coalesce((app.decisao_vigente(p_colaborador)).acao_final::text, '') <> 'dispensa' then raise exception 'Este colaborador não tem dispensa confirmada'; end if;
  if p_tipo = 'lista_presenca' and not app.grade_concluida(p_colaborador) then raise exception 'A lista só vai para assinatura com todos os treinamentos concluídos'; end if;
  if app.documento_ja_tratado(p_colaborador, p_tipo) then raise exception 'Este documento já foi enviado para assinatura'; end if;
  return jsonb_build_object('id', app.criar_documento_assinatura(p_colaborador, p_tipo), 'tem_email', (select email is not null from colaboradores where id = p_colaborador));
end $$;

create function public.cancelar_assinatura(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  update documentos_assinatura set status = 'cancelado' where id = p_id and status = 'pendente';
  if not found then raise exception 'Só uma solicitação pendente pode ser cancelada'; end if;
end $$;

create function public.assinaturas_lista() returns table (id uuid, colaborador_id uuid, tipo text, status text, solicitado_em timestamptz, assinado_em timestamptz, baixado_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform app.exigir_admin();
  return query select d.id, d.colaborador_id, d.tipo, d.status, d.solicitado_em, d.assinado_em, d.baixado_em from documentos_assinatura d where d.status <> 'cancelado' order by d.solicitado_em desc;
end $$;

create function public.minhas_assinaturas() returns table (id uuid, tipo text, status text, solicitado_em timestamptz, assinado_em timestamptz)
language sql stable security definer set search_path = public as $$
  select d.id, d.tipo, d.status, d.solicitado_em, d.assinado_em from documentos_assinatura d
  where d.colaborador_id = app.meu_colaborador() and d.status <> 'cancelado' order by d.solicitado_em desc
$$;

create function public.documento_assinatura(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  select to_jsonb(d) into r from documentos_assinatura d where d.id = p_id and d.status <> 'cancelado' and (app.eh_admin() or d.colaborador_id = app.meu_colaborador());
  if r is null then raise exception 'Documento não disponível' using errcode = '42501'; end if;
  return r;
end $$;

create function public.assinar_documento(p_id uuid, p_imagem text) returns void
language plpgsql security definer set search_path = public as $$
declare d documentos_assinatura; v_cab jsonb := nullif(current_setting('request.headers', true), '')::jsonb; v_nome text; v_email text; v_admin text;
begin
  select * into d from documentos_assinatura where id = p_id and colaborador_id = app.meu_colaborador() for update;
  if not found then raise exception 'Este documento não está disponível para você' using errcode = '42501'; end if;
  if d.status <> 'pendente' then raise exception 'Este documento não está aguardando assinatura'; end if;
  if p_imagem is null or p_imagem not like 'data:image/png;base64,%' or length(p_imagem) > 400000 then raise exception 'Assinatura inválida. Assine novamente.'; end if;
  select c.nome, u.email into v_nome, v_email from usuarios u join colaboradores c on c.id = u.colaborador_id where u.id = auth.uid();
  update documentos_assinatura set status = 'assinado', assinado_em = now(), assinatura_imagem = p_imagem, assinatura_nome = v_nome, assinatura_email = v_email,
    assinatura_ip = trim(split_part(v_cab->>'x-forwarded-for', ',', 1)), assinatura_navegador = left(v_cab->>'user-agent', 300) where id = p_id;
  insert into eventos (tabela, registro_id, acao, depois, usuario) values ('documentos_assinatura', p_id::text, 'assinatura', jsonb_build_object('tipo', d.tipo, 'hash', d.hash), auth.uid());
  for v_admin in select email from usuarios where perfil = 'admin' and ativo loop
    perform app.notificar('assinatura_concluida', null, v_admin);
  end loop;
end $$;

create function public.marcar_documento_baixado(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  update documentos_assinatura set baixado_em = coalesce(baixado_em, now()) where id = p_id and status = 'assinado';
end $$;
