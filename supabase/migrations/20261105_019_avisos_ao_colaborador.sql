-- Colaborador recebe convocação, lembrete, alteração e desmarcação. Quem não tem e-mail válido fica de fora.
insert into public.modelos_email (tipo, nome, quando, para, ordem, assunto, corpo) values
('convocacao_colaborador', 'Convocação do colaborador', 'Quando Gente e Gestão formaliza a turma, ou a pessoa entra em turma já formalizada', 'Colaborador', 12,
 'Convocação: {treinamento} em {data}',
 E'Olá,\n\nVocê está convocado para um treinamento.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\nSala: {sala}\n\nSe tiver algum impedimento, fale com seu gestor e com Gente e Gestão.\n\nAtenciosamente,\nGente e Gestão'),
('lembrete_1h_colaborador', 'Lembrete ao colaborador', 'Antes do início, no prazo definido em Regras', 'Colaborador', 22,
 'Lembrete: {treinamento} hoje às {inicio}',
 E'Olá,\n\nSeu treinamento começa em breve.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\nSala: {sala}\n\nAtenciosamente,\nGente e Gestão'),
('alteracao_colaborador', 'Alteração para o colaborador', 'Quando muda a data, o horário ou a sala de turma já formalizada', 'Colaborador', 62,
 'Treinamento alterado: {treinamento}',
 E'Olá,\n\nO treinamento para o qual você foi convocado mudou. Considere os dados abaixo.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\nSala: {sala}\n\nAtenciosamente,\nGente e Gestão'),
('desmarcado_colaborador', 'Desmarcação para o colaborador', 'Quando a turma formalizada é cancelada ou volta para reagendar, ou a pessoa sai da turma', 'Colaborador', 72,
 'Treinamento desmarcado: {treinamento}',
 E'Olá,\n\nO treinamento {treinamento}, para o qual você foi convocado, foi desmarcado para você. Desconsidere a data informada antes.\n\nSe houver nova data, você receberá uma nova convocação.\n\nAtenciosamente,\nGente e Gestão');

-- Um e-mail por endereço, mesmo que duas pessoas da turma dividam a mesma caixa.
create function app.emails_da_turma(p_turma uuid) returns setof text language sql stable security definer set search_path = public as $$
  select distinct lower(trim(c.email)) from turma_participantes p join colaboradores c on c.id = p.colaborador_id
  where p.turma_id = p_turma and p.situacao = 'convocado' and c.ativo and trim(c.email) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
$$;

create function app.ja_convocado(p_turma uuid, p_email text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from notificacoes n where n.turma_id = p_turma and n.tipo = 'convocacao_colaborador' and n.destinatario = p_email and n.status = 'enviada')
$$;

create function app.descartar_avisos_colaborador(p_turma uuid, p_tipos text[], p_email text default null) returns void language sql security definer set search_path = public as $$
  update notificacoes set status = 'cancelada', erro = 'A turma mudou antes do envio'
  where turma_id = p_turma and status in ('pendente', 'erro') and tipo = any (p_tipos) and (p_email is null or destinatario = p_email)
$$;

create function app.turma_vale_aviso(p_turma uuid) returns boolean language sql stable security definer set search_path = public as $$
  select t.data >= (select valor::date from parametros where chave = 'avisos_desde') and upper(app.periodo_turma(t.id)) > now() from turmas t where t.id = p_turma
$$;

create function app.avisar_colaboradores_turma() returns trigger language plpgsql security definer set search_path = public as $$
declare v_todos text[] := array['convocacao_colaborador', 'lembrete_1h_colaborador', 'alteracao_colaborador', 'desmarcado_colaborador'];
begin
  if old.status <> 'convite_enviado' and new.status = 'convite_enviado' then
    if app.turma_vale_aviso(new.id) then
      perform app.descartar_avisos_colaborador(new.id, v_todos);
      perform app.notificar('convocacao_colaborador', new.id, e) from app.emails_da_turma(new.id) e;
    end if;
  elsif old.status = 'convite_enviado' and new.status = 'convite_enviado' then
    if (old.data, old.hora_inicio, old.sala) is distinct from (new.data, new.hora_inicio, new.sala) then
      perform app.descartar_avisos_colaborador(new.id, array['lembrete_1h_colaborador', 'alteracao_colaborador']);
      if app.turma_vale_aviso(new.id) then
        perform app.notificar('alteracao_colaborador', new.id, e) from app.emails_da_turma(new.id) e where app.ja_convocado(new.id, e);
      end if;
    end if;
  elsif old.status = 'convite_enviado' and new.status in ('cancelada', 'aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar') then
    -- Só avisa quem já tinha recebido a convocação; para os outros, o aviso pendente é descartado.
    perform app.descartar_avisos_colaborador(new.id, v_todos);
    perform app.notificar('desmarcado_colaborador', new.id, e) from app.emails_da_turma(new.id) e where app.ja_convocado(new.id, e);
  end if;
  return null;
end $$;
create trigger avisa_colaboradores after update of status, data, hora_inicio, sala on public.turmas for each row execute function app.avisar_colaboradores_turma();

-- Pessoa que entra ou sai de turma já formalizada.
create function app.avisar_colaborador_participante() returns trigger language plpgsql security definer set search_path = public as $$
declare v_turma uuid := coalesce(new.turma_id, old.turma_id); v_colab uuid := coalesce(new.colaborador_id, old.colaborador_id); v_email text; v_inicio timestamptz;
begin
  select lower(trim(c.email)) into v_email from colaboradores c where c.id = v_colab and c.ativo and trim(c.email) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
  if v_email is null then return null; end if;
  select convite_enviado_em into v_inicio from turmas where id = v_turma and status = 'convite_enviado';
  if not found or not app.turma_vale_aviso(v_turma) then return null; end if;
  if (tg_op = 'INSERT' and new.situacao = 'convocado') or (tg_op = 'UPDATE' and old.situacao = 'nao_aplicavel' and new.situacao = 'convocado') then
    if not exists (select 1 from notificacoes n where n.turma_id = v_turma and n.tipo = 'convocacao_colaborador' and n.destinatario = v_email and n.status <> 'cancelada' and n.criado_em >= coalesce(v_inicio, '-infinity')) then
      perform app.notificar('convocacao_colaborador', v_turma, v_email);
    end if;
  elsif (tg_op = 'DELETE' and old.situacao = 'convocado') or (tg_op = 'UPDATE' and old.situacao = 'convocado' and new.situacao = 'nao_aplicavel') then
    if v_email not in (select app.emails_da_turma(v_turma)) then
      perform app.descartar_avisos_colaborador(v_turma, array['convocacao_colaborador', 'lembrete_1h_colaborador', 'alteracao_colaborador'], v_email);
      if app.ja_convocado(v_turma, v_email) then perform app.notificar('desmarcado_colaborador', v_turma, v_email); end if;
    end if;
  end if;
  return null;
end $$;
create trigger avisa_colaborador after insert or update of situacao or delete on public.turma_participantes for each row execute function app.avisar_colaborador_participante();

-- O cancelamento limpa os avisos pendentes, menos a desmarcação que acabou de nascer.
create or replace function public.cancelar_turma(p_turma uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  perform app.exigir_admin();
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo do cancelamento'; end if;
  select * into t from turmas where id = p_turma for update;
  if t.status in ('realizada', 'encerrada', 'cancelada') then raise exception 'Esta turma não pode mais ser cancelada'; end if;
  update turmas set status = 'cancelada', motivo_replanejamento = p_motivo where id = p_turma;
  update notificacoes set status = 'cancelada' where turma_id = p_turma and status = 'pendente' and tipo <> 'desmarcado_colaborador';
  update turma_solicitacoes set status = 'recusada', resposta = 'Turma cancelada', decidido_por = auth.uid(), decidido_em = now() where turma_id = p_turma and status = 'aberta';
  delete from turma_participantes where turma_id = p_turma and situacao = 'convocado';
  perform app.notificar('aviso_cancelamento', p_turma, t.instrutor_email);
  if t.status = 'convite_enviado' then perform app.notificar('calendario_cancelar', p_turma, t.instrutor_email); end if;
end $$;

create or replace function app.gerar_avisos_por_horario() returns integer
language plpgsql security definer set search_path = public as $$
declare v integer := 0; n integer;
begin
  with c as (
    select t.id, t.instrutor_email, app.periodo_turma(t.id) as p from turmas t
    where t.status in ('agenda_confirmada', 'convite_enviado') and t.instrutor_email is not null and t.hora_inicio is not null
      and t.data between app.hoje() - 1 and app.hoje() + 2
  )
  insert into notificacoes (tipo, turma_id, destinatario, chave)
  select 'lembrete_1h', c.id, c.instrutor_email, 'lembrete_1h:' || c.id || ':' || lower(c.p) from c
  where now() < lower(c.p) and now() >= lower(c.p) - make_interval(mins => app.param_int('lembrete_minutos_antes'))
    and exists (select 1 from modelos_email m where m.tipo = 'lembrete_1h' and m.ativo)
  on conflict (chave) where chave is not null do nothing;
  get diagnostics n = row_count; v := v + n;

  with c as (
    select t.id, app.periodo_turma(t.id) as p from turmas t
    where t.status = 'convite_enviado' and t.hora_inicio is not null and t.data between app.hoje() - 1 and app.hoje() + 2
  )
  insert into notificacoes (tipo, turma_id, destinatario, chave)
  select 'lembrete_1h_colaborador', c.id, e, 'lembrete_1h_colaborador:' || c.id || ':' || e || ':' || lower(c.p)
  from c cross join lateral app.emails_da_turma(c.id) e
  where now() < lower(c.p) and now() >= lower(c.p) - make_interval(mins => app.param_int('lembrete_minutos_antes'))
    and exists (select 1 from modelos_email m where m.tipo = 'lembrete_1h_colaborador' and m.ativo)
  on conflict (chave) where chave is not null do nothing;
  get diagnostics n = row_count; v := v + n;

  with c as (
    select t.id, t.instrutor_email, app.periodo_turma(t.id) as p from turmas t
    where t.status = 'convite_enviado' and t.instrutor_email is not null and t.presenca_concluida_em is null
      and t.data between app.hoje() - 2 and app.hoje()
  )
  insert into notificacoes (tipo, turma_id, destinatario, chave)
  select 'aviso_presenca', c.id, c.instrutor_email, 'aviso_presenca:' || c.id || ':' || upper(c.p) from c
  where now() >= upper(c.p) and now() < upper(c.p) + interval '1 day'
    and exists (select 1 from modelos_email m where m.tipo = 'aviso_presenca' and m.ativo)
  on conflict (chave) where chave is not null do nothing;
  get diagnostics n = row_count;
  return v + n;
end $$;

create or replace function public.notificacoes_para_envio(p_limite integer default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  perform rotina_diaria();
  perform app.gerar_avisos_por_horario();
  update notificacoes n set status = 'cancelada', erro = 'Modelo de e-mail desligado'
    where n.status in ('pendente', 'erro') and not exists (select 1 from modelos_email m where m.tipo = n.tipo and m.ativo);
  update notificacoes n set status = 'cancelada', erro = 'O treinamento já começou'
    where n.tipo in ('lembrete_1h', 'lembrete_1h_colaborador', 'convocacao_colaborador', 'alteracao_colaborador') and n.status in ('pendente', 'erro') and lower(app.periodo_turma(n.turma_id)) <= now();
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'destinatario', x.destinatario, 'tentativas', x.tentativas) || app.montar_email(x.tipo, x.turma_id)), '[]') into v
  from (
    select n.id, n.tipo, n.destinatario, n.turma_id, n.tentativas from notificacoes n
    where n.status = 'pendente' or (n.status = 'erro' and n.tentativas < 3)
    order by n.criado_em limit p_limite) x;
  return v;
end $$;

revoke all on function app.emails_da_turma(uuid), app.ja_convocado(uuid, text), app.descartar_avisos_colaborador(uuid, text[], text), app.turma_vale_aviso(uuid), app.avisar_colaboradores_turma(), app.avisar_colaborador_participante() from public, anon, authenticated;
revoke all on function public.notificacoes_para_envio(integer) from public, anon, authenticated;
grant execute on function public.notificacoes_para_envio(integer) to service_role;
