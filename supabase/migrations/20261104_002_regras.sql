-- Portal de Treinamentos · regras do negócio
-- Uma fonte única para matriz, elegibilidade, situação por pessoa e ciclo da turma.

create function app.hoje() returns date language sql stable as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;
create function app.param_int(p_chave text) returns integer language sql stable security definer set search_path = public as $$
  select valor::integer from parametros where chave = p_chave $$;

-- Matriz: só revisão vigente cria ou remove. Revisão aberta ou arquivada não altera o que vale.
create function public.matriz_vigente_em(p_cargo uuid, p_data date)
returns table (treinamento_id uuid, obrigatorio boolean)
language sql stable security definer set search_path = public as $$
  select distinct on (v.treinamento_id) v.treinamento_id, v.obrigatorio
  from matriz_vinculos v
  join matriz_revisoes c on c.id = v.revisao_criacao_id
  join treinamentos t on t.id = v.treinamento_id
  left join matriz_revisoes r on r.id = v.revisao_remocao_id
  where v.cargo_id = p_cargo and t.ativo
    and c.status = 'vigente' and c.data_inicio_vigencia <= p_data
    and (r.id is null or r.status <> 'vigente' or r.data_inicio_vigencia > p_data)
  order by v.treinamento_id, c.data_inicio_vigencia desc
$$;

-- Data de referência: movimentação ativa, senão a mais recente, senão a admissão.
create function app.data_referencia(p_colaborador uuid) returns date
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select max(data_inicio) from movimentacoes where colaborador_id = p_colaborador and data_fim is null),
    (select max(data_inicio) from movimentacoes where colaborador_id = p_colaborador),
    (select data_admissao from colaboradores where id = p_colaborador))
$$;

create function app.ultima_realizacao(p_colaborador uuid, p_treinamento uuid) returns date
language sql stable security definer set search_path = public as $$
  select max(t.data) from turma_participantes p join turmas t on t.id = p.turma_id
  where p.colaborador_id = p_colaborador and t.treinamento_id = p_treinamento and p.situacao = 'presente'
$$;

create function app.decisao_vigente(p_colaborador uuid) returns public.reciclagem_decisoes
language sql stable security definer set search_path = public as $$
  select d.* from reciclagem_decisoes d join colaboradores c on c.id = d.colaborador_id
  where d.colaborador_id = p_colaborador and d.cargo_atual_id is not distinct from c.cargo_id
  order by d.decidido_em desc limit 1
$$;

-- A pessoa precisa fazer o treinamento por decisão de reciclagem ou por ausência anterior?
create function app.exigido_por_decisao(p_colaborador uuid, p_treinamento uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d reciclagem_decisoes; c uuid;
begin
  d := app.decisao_vigente(p_colaborador);
  if d.id is null or d.acao_final = 'dispensa' then return false; end if;
  if d.acao_final = 'parcial' and not (p_treinamento = any (d.treinamentos_parcial)) then return false; end if;
  if d.acao_final = 'total' then
    select cargo_id into c from colaboradores where id = p_colaborador;
    if not exists (select 1 from matriz_vigente_em(c, app.hoje()) m where m.treinamento_id = p_treinamento) then return false; end if;
  end if;
  return coalesce(app.ultima_realizacao(p_colaborador, p_treinamento) < (d.decidido_em at time zone 'America/Sao_Paulo')::date, true);
end $$;

create function app.ausente_sem_nova_turma(p_colaborador uuid, p_treinamento uuid, p_ignorar uuid default null) returns boolean
language sql stable security definer set search_path = public as $$
  with ultima as (
    select p.situacao from turma_participantes p join turmas t on t.id = p.turma_id
    where p.colaborador_id = p_colaborador and t.treinamento_id = p_treinamento
      and p.situacao in ('presente', 'ausente') and t.id is distinct from p_ignorar
    order by t.data desc nulls last, p.registrado_em desc nulls last limit 1)
  select coalesce((select situacao = 'ausente' from ultima), false)
$$;

-- Quem entra na turma. Única regra de elegibilidade do sistema.
create function app.elegiveis(p_turma uuid)
returns table (colaborador_id uuid, cargo_id uuid)
language sql stable security definer set search_path = public as $$
  with t as (select *, coalesce(data, app.hoje()) as data_ref from turmas where id = p_turma)
  select c.id, c.cargo_id
  from t
  join turma_cargos tc on tc.turma_id = t.id and tc.incluir_no_convite
  join colaboradores c on c.cargo_id = tc.cargo_id and c.ativo
  cross join lateral (select app.data_referencia(c.id) as ref, app.ultima_realizacao(c.id, t.treinamento_id) as ultima) x
  where app.ausente_sem_nova_turma(c.id, t.treinamento_id, t.id)
     or app.exigido_por_decisao(c.id, t.treinamento_id)
     or (
       exists (select 1 from matriz_vigente_em(c.cargo_id, x.ref) m where m.treinamento_id = t.treinamento_id)
       and coalesce((app.decisao_vigente(c.id)).acao_final, 'total') <> 'dispensa'
       and (
         (t.tipo = 'reciclagem' and x.ultima is not null and t.data_ref - x.ultima >= app.param_int('prazo_reciclagem_dias'))
         or (x.ultima is null and x.ref <= t.data_ref
             and x.ref >= least(t.criado_em::date, t.data_ref) - app.param_int('janela_convocacao_dias'))
       ))
$$;

-- A lista acompanha a realidade até a presença ser concluída. Quem já tem presença registrada não sai.
create function app.sincronizar_participantes(p_turma uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from turmas where id = p_turma
                 and status in ('pendente', 'aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado')) then
    return;
  end if;
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id)
  select p_turma, e.colaborador_id, e.cargo_id from app.elegiveis(p_turma) e
  on conflict (turma_id, colaborador_id) do nothing;
  delete from turma_participantes p
  where p.turma_id = p_turma and p.situacao = 'convocado' and p.origem = 'calculo'
    and not exists (select 1 from app.elegiveis(p_turma) e where e.colaborador_id = p.colaborador_id);
end $$;

create function app.sincronizar_turmas_do_cargo(p_cargo uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in select distinct t.id from turmas t join turma_cargos tc on tc.turma_id = t.id
           where tc.cargo_id = p_cargo and t.status in ('pendente', 'aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado')
  loop perform app.sincronizar_participantes(r.id); end loop;
end $$;

create function app.gatilho_colaborador() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.cargo_id is not null then perform app.sincronizar_turmas_do_cargo(new.cargo_id); end if;
  if tg_op = 'UPDATE' and old.cargo_id is distinct from new.cargo_id and old.cargo_id is not null then
    perform app.sincronizar_turmas_do_cargo(old.cargo_id);
  end if;
  return new;
end $$;
create trigger sincroniza_turmas after insert or update of cargo_id, ativo, data_admissao on public.colaboradores
  for each row execute function app.gatilho_colaborador();

create function app.exigir_admin() returns void language plpgsql stable as $$
begin
  if not app.eh_admin() then raise exception 'Somente Gente e Gestão pode fazer esta ação' using errcode = '42501'; end if;
end $$;

create function app.notificar(p_tipo text, p_turma uuid, p_destinatario text) returns void
language sql security definer set search_path = public as $$
  insert into notificacoes (tipo, turma_id, destinatario) select p_tipo, p_turma, p_destinatario where p_destinatario is not null
$$;

create function app.periodo_turma(p_turma uuid) returns tstzrange
language sql stable security definer set search_path = public as $$
  select case when t.data is null or coalesce(t.hora_inicio, t.hora_opcao_1) is null then null
    else tstzrange(
      ((t.data + coalesce(t.hora_inicio, t.hora_opcao_1)) at time zone 'America/Sao_Paulo'),
      ((t.data + coalesce(t.hora_inicio, t.hora_opcao_1)) at time zone 'America/Sao_Paulo') + make_interval(mins => tr.carga_minutos))
    end
  from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.id = p_turma
$$;

create function public.conflitos_turma(p_turma uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  with a as (select *, app.periodo_turma(id) as periodo from turmas where id = p_turma)
  select coalesce(jsonb_agg(x), '[]') from (
    select 'sala' as tipo, o.id as turma_id, tr.nome as treinamento
    from a join turmas o on o.id <> a.id and o.sala = a.sala and a.sala <> 'Externo' join treinamentos tr on tr.id = o.treinamento_id
    where o.status in ('agenda_confirmada', 'convite_enviado') and app.periodo_turma(o.id) && a.periodo
    union all
    select 'instrutor', o.id, tr.nome
    from a join turmas o on o.id <> a.id and o.instrutor_email = a.instrutor_email join treinamentos tr on tr.id = o.treinamento_id
    where o.status in ('agenda_confirmada', 'convite_enviado') and app.periodo_turma(o.id) && a.periodo
    union all
    select distinct 'participante', o.id, tr.nome
    from a join turma_participantes pa on pa.turma_id = a.id
    join turma_participantes po on po.colaborador_id = pa.colaborador_id and po.turma_id <> a.id
    join turmas o on o.id = po.turma_id join treinamentos tr on tr.id = o.treinamento_id
    where o.status in ('agenda_confirmada', 'convite_enviado') and app.periodo_turma(o.id) && a.periodo
  ) x
$$;

-- Etapa que o usuário enxerga, derivada da situação real da turma.
create function app.etapa_turma(p_status public.status_turma, p_periodo tstzrange) returns text
language sql stable as $$
  select case
    when p_status = 'pendente' then 'a_planejar'
    when p_status = 'aguardando_instrutor' then 'aguardando_instrutor'
    when p_status in ('agenda_confirmada', 'precisa_replanejar') then 'formalizar'
    when p_status = 'convite_enviado' and (p_periodo is null or upper(p_periodo) > now()) then 'agendadas'
    when p_status = 'convite_enviado' then 'presenca'
    when p_status in ('realizada', 'encerrada') then 'realizadas'
    else 'canceladas' end
$$;

-- Ciclo da turma
create function public.criar_turma(p_treinamento uuid, p_tipo public.tipo_turma, p_data date, p_hora_1 time, p_hora_2 time, p_instrutor_email text, p_cargos uuid[], p_origem uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_email text := lower(trim(p_instrutor_email)); v_individual boolean; v_notifica boolean := true;
begin
  perform app.exigir_admin();
  if p_data is null or p_hora_1 is null then raise exception 'Informe a data e ao menos um horário'; end if;
  if v_email is null or v_email = '' then raise exception 'Informe o e-mail do instrutor'; end if;
  if p_hora_2 = p_hora_1 then p_hora_2 := null; end if;
  if coalesce(array_length(p_cargos, 1), 0) = 0 then raise exception 'Informe ao menos um cargo'; end if;
  select individual_por_colaborador into v_individual from treinamentos where id = p_treinamento and ativo;
  if not found then raise exception 'Treinamento inativo ou inexistente'; end if;

  -- Reaproveita turma aberta do mesmo treinamento, data e instrutor antes do convite.
  if not v_individual then
    select id into v_id from turmas
    where treinamento_id = p_treinamento and data = p_data and instrutor_email = v_email
      and status in ('pendente', 'aguardando_instrutor', 'agenda_confirmada') limit 1;
  end if;
  if v_id is not null then
    v_notifica := false;
    if p_tipo = 'reciclagem' then update turmas set tipo = 'reciclagem' where id = v_id; end if;
  else
    insert into turmas (treinamento_id, tipo, data, hora_opcao_1, hora_opcao_2, instrutor_email, turma_origem_id, criado_por)
    values (p_treinamento, p_tipo, p_data, p_hora_1, p_hora_2, v_email, p_origem, auth.uid()) returning id into v_id;
  end if;
  insert into turma_cargos (turma_id, cargo_id) select v_id, unnest(p_cargos)
  on conflict (turma_id, cargo_id) do update set incluir_no_convite = true;
  perform app.sincronizar_participantes(v_id);
  if v_notifica then perform app.notificar('aviso_instrutor', v_id, v_email); end if;
  return v_id;
end $$;

-- Instrutor responde no portal: aceitar, propor outro horário ou recusar.
create function public.responder_agenda(p_turma uuid, p_acao text, p_hora time default null, p_nova_data date default null, p_motivo text default null)
returns void language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  select * into t from turmas where id = p_turma for update;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not (app.eh_instrutor_da_turma(p_turma) or app.eh_admin()) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  if t.status <> 'aguardando_instrutor' then raise exception 'Esta turma não está mais aguardando resposta. Atualize a página para ver a situação atual.'; end if;
  if p_acao = 'aceitar' then
    if p_hora is null or p_hora not in (t.hora_opcao_1, t.hora_opcao_2) then raise exception 'Escolha um dos horários sugeridos'; end if;
    update turmas set status = 'agenda_confirmada', hora_inicio = p_hora, instrutor_respondeu_em = now() where id = p_turma;
  elsif p_acao = 'propor' then
    if p_hora is null and p_nova_data is null then raise exception 'Informe a nova data ou o novo horário'; end if;
    if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo'; end if;
    insert into turma_solicitacoes (turma_id, tipo, motivo, proposta, solicitado_por)
    values (p_turma, 'nova_agenda', p_motivo, jsonb_strip_nulls(jsonb_build_object('data', p_nova_data, 'hora', p_hora)), auth.uid());
    update turmas set instrutor_respondeu_em = now() where id = p_turma;
  elsif p_acao = 'recusar' then
    if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo da recusa'; end if;
    update turmas set status = 'precisa_replanejar', motivo_replanejamento = 'Recusada pelo instrutor: ' || p_motivo, instrutor_respondeu_em = now() where id = p_turma;
  else
    raise exception 'Ação inválida';
  end if;
end $$;

create function public.definir_sala(p_turma uuid, p_sala text) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  perform app.exigir_admin();
  select * into t from turmas where id = p_turma for update;
  if t.status not in ('aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado') then raise exception 'A sala desta turma não pode mais ser alterada'; end if;
  update turmas set sala = p_sala where id = p_turma;
  if t.status = 'convite_enviado' and t.sala is distinct from p_sala then perform app.notificar('calendario_atualizar', p_turma, t.instrutor_email); end if;
end $$;

create function public.alternar_cargo_turma(p_turma uuid, p_cargo uuid, p_incluir boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  if not exists (select 1 from turmas where id = p_turma and status in ('aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado')) then
    raise exception 'Os cargos desta turma não podem mais ser alterados';
  end if;
  insert into turma_cargos (turma_id, cargo_id, incluir_no_convite) values (p_turma, p_cargo, p_incluir)
  on conflict (turma_id, cargo_id) do update set incluir_no_convite = p_incluir;
  perform app.sincronizar_participantes(p_turma);
end $$;

create function public.ajustar_participante(p_turma uuid, p_colaborador uuid, p_incluir boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  if not exists (select 1 from turmas where id = p_turma and status in ('aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado')) then
    raise exception 'Os participantes desta turma não podem mais ser alterados';
  end if;
  if p_incluir then
    insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id, origem, registrado_por)
    select p_turma, c.id, c.cargo_id, 'manual', auth.uid() from colaboradores c where c.id = p_colaborador and c.ativo
    on conflict (turma_id, colaborador_id) do update set situacao = 'convocado', origem = 'manual' where turma_participantes.situacao = 'nao_aplicavel';
  else
    update turma_participantes set situacao = 'nao_aplicavel', origem = 'manual', registrado_por = auth.uid(), registrado_em = now()
    where turma_id = p_turma and colaborador_id = p_colaborador and situacao in ('convocado', 'a_validar');
  end if;
end $$;

create function public.formalizar_turma(p_turma uuid) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  perform app.exigir_admin();
  select * into t from turmas where id = p_turma for update;
  if t.status <> 'agenda_confirmada' then raise exception 'Só turma com a agenda aceita pelo instrutor pode ser formalizada'; end if;
  if t.sala is null then raise exception 'Escolha a sala'; end if;
  if t.hora_inicio is null then raise exception 'A turma está sem horário confirmado'; end if;
  if exists (select 1 from turma_solicitacoes where turma_id = p_turma and status = 'aberta') then raise exception 'Há uma solicitação aberta nesta turma. Decida-a antes de formalizar.'; end if;
  if jsonb_array_length(conflitos_turma(p_turma)) > 0 then raise exception 'Há conflito de agenda nesta turma'; end if;
  perform app.sincronizar_participantes(p_turma);
  if not exists (select 1 from turma_participantes where turma_id = p_turma and situacao = 'convocado') then
    raise exception 'A turma não tem nenhum participante elegível';
  end if;
  update turmas set status = 'convite_enviado', convite_enviado_em = now() where id = p_turma;
  perform app.notificar('calendario_criar', p_turma, t.instrutor_email);
end $$;

-- Altera a mesma turma. Evento e notificações acompanham; nada antigo continua valendo.
create function app.aplicar_alteracao(p_turma uuid, p_data date, p_hora time, p_sala text, p_instrutor_email text, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas; v_email text := nullif(lower(trim(p_instrutor_email)), ''); v_troca boolean;
begin
  select * into t from turmas where id = p_turma for update;
  if t.status not in ('aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado') then
    raise exception 'Esta turma não pode mais ser alterada';
  end if;
  v_troca := v_email is not null and v_email <> t.instrutor_email;
  update notificacoes set status = 'cancelada' where turma_id = p_turma and status = 'pendente' and tipo in ('aviso_instrutor', 'lembrete_agenda', 'lembrete_presenca');
  if v_troca then
    update turmas set data = coalesce(p_data, data), hora_opcao_1 = coalesce(p_hora, coalesce(hora_inicio, hora_opcao_1)), hora_opcao_2 = null, hora_inicio = null,
      sala = coalesce(p_sala, sala), instrutor_email = v_email, status = 'aguardando_instrutor', motivo_replanejamento = null, instrutor_respondeu_em = null where id = p_turma;
    perform app.notificar('aviso_cancelamento', p_turma, t.instrutor_email);
    if t.status = 'convite_enviado' then
      perform app.notificar('calendario_cancelar', p_turma, t.instrutor_email);
      update turmas set convite_enviado_em = null where id = p_turma;
    end if;
    perform app.notificar('aviso_instrutor', p_turma, v_email);
  elsif t.status = 'convite_enviado' then
    update turmas set data = coalesce(p_data, data), hora_inicio = coalesce(p_hora, hora_inicio), sala = coalesce(p_sala, sala) where id = p_turma;
    perform app.notificar('calendario_atualizar', p_turma, t.instrutor_email);
    perform app.notificar('aviso_decisao', p_turma, t.instrutor_email);
  elsif t.status = 'precisa_replanejar' then
    update turmas set data = coalesce(p_data, data), hora_opcao_1 = coalesce(p_hora, hora_opcao_1), hora_opcao_2 = case when p_hora is null then hora_opcao_2 end, hora_inicio = null,
      sala = coalesce(p_sala, sala), status = 'aguardando_instrutor', motivo_replanejamento = null, instrutor_respondeu_em = null where id = p_turma;
    perform app.notificar('aviso_instrutor', p_turma, t.instrutor_email);
  else
    update turmas set data = coalesce(p_data, data), hora_inicio = coalesce(p_hora, hora_inicio),
      hora_opcao_1 = coalesce(p_hora, hora_opcao_1), sala = coalesce(p_sala, sala), status = 'agenda_confirmada', instrutor_respondeu_em = coalesce(instrutor_respondeu_em, now()) where id = p_turma;
    perform app.notificar('aviso_decisao', p_turma, t.instrutor_email);
  end if;
  perform app.sincronizar_participantes(p_turma);
end $$;

create function public.alterar_turma(p_turma uuid, p_data date, p_hora time, p_sala text, p_instrutor_email text, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo da alteração'; end if;
  perform app.aplicar_alteracao(p_turma, p_data, p_hora, p_sala, p_instrutor_email, p_motivo);
end $$;

create function public.cancelar_turma(p_turma uuid, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  perform app.exigir_admin();
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo do cancelamento'; end if;
  select * into t from turmas where id = p_turma for update;
  if t.status in ('realizada', 'encerrada', 'cancelada') then raise exception 'Esta turma não pode mais ser cancelada'; end if;
  update turmas set status = 'cancelada', motivo_replanejamento = p_motivo where id = p_turma;
  update notificacoes set status = 'cancelada' where turma_id = p_turma and status = 'pendente';
  update turma_solicitacoes set status = 'recusada', resposta = 'Turma cancelada', decidido_por = auth.uid(), decidido_em = now() where turma_id = p_turma and status = 'aberta';
  delete from turma_participantes where turma_id = p_turma and situacao = 'convocado';
  perform app.notificar('aviso_cancelamento', p_turma, t.instrutor_email);
  if t.status = 'convite_enviado' then perform app.notificar('calendario_cancelar', p_turma, t.instrutor_email); end if;
end $$;

create function public.solicitar_alteracao(p_turma uuid, p_tipo public.tipo_solicitacao, p_motivo text, p_proposta jsonb default '{}') returns uuid
language plpgsql security definer set search_path = public as $$
declare t turmas; v_id uuid;
begin
  select * into t from turmas where id = p_turma;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not (app.eh_instrutor_da_turma(p_turma) or app.eh_admin()) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo'; end if;
  if t.status = 'cancelada' then raise exception 'Esta turma foi cancelada'; end if;
  if p_tipo = 'correcao_presenca' and t.presenca_concluida_em is null then raise exception 'A presença ainda pode ser corrigida direto na tela'; end if;
  if p_tipo <> 'correcao_presenca' and t.status in ('realizada', 'encerrada') then raise exception 'Esta turma já foi concluída'; end if;
  if exists (select 1 from turma_solicitacoes where turma_id = p_turma and status = 'aberta') then raise exception 'Já existe uma solicitação aberta nesta turma'; end if;
  insert into turma_solicitacoes (turma_id, tipo, motivo, proposta, solicitado_por) values (p_turma, p_tipo, p_motivo, coalesce(p_proposta, '{}'), auth.uid()) returning id into v_id;
  return v_id;
end $$;

create function public.decidir_solicitacao(p_solicitacao uuid, p_aprovar boolean, p_resposta text default null) returns void
language plpgsql security definer set search_path = public as $$
declare s turma_solicitacoes; t turmas;
begin
  perform app.exigir_admin();
  select * into s from turma_solicitacoes where id = p_solicitacao for update;
  if not found or s.status <> 'aberta' then raise exception 'Esta solicitação não está mais aberta'; end if;
  select * into t from turmas where id = s.turma_id;
  update turma_solicitacoes set status = case when p_aprovar then 'aprovada'::status_solicitacao else 'recusada'::status_solicitacao end, resposta = p_resposta, decidido_por = auth.uid(), decidido_em = now() where id = s.id;
  if p_aprovar and s.tipo in ('nova_agenda', 'alteracao') then
    perform app.aplicar_alteracao(s.turma_id, (s.proposta ->> 'data')::date, (s.proposta ->> 'hora')::time, s.proposta ->> 'sala', s.proposta ->> 'instrutor_email', s.motivo);
  elsif p_aprovar and s.tipo = 'cancelamento' then
    perform cancelar_turma(s.turma_id, s.motivo);
  elsif not p_aprovar then
    perform app.notificar('aviso_decisao', s.turma_id, t.instrutor_email);
  end if;
end $$;

-- Presença: uma tela, pessoa por pessoa, corrigível até concluir. Nenhuma marcação é descartada.
create function public.marcar_presenca(p_turma uuid, p_colaborador uuid, p_situacao public.situacao_participante) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  select * into t from turmas where id = p_turma for update;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not (app.eh_instrutor_da_turma(p_turma) or app.eh_admin()) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  if t.status <> 'convite_enviado' then raise exception 'A presença só pode ser registrada em turma agendada e não concluída. Atualize a página.'; end if;
  if lower(app.periodo_turma(p_turma)) > now() then raise exception 'A presença só abre no horário da turma'; end if;
  if p_situacao not in ('presente', 'ausente', 'convocado') then raise exception 'Situação inválida'; end if;
  update turma_participantes set situacao = p_situacao, registrado_por = auth.uid(), registrado_em = now()
  where turma_id = p_turma and colaborador_id = p_colaborador and situacao <> 'nao_aplicavel';
  if not found then raise exception 'Esta pessoa não está na lista da turma'; end if;
end $$;

create function public.concluir_presenca(p_turma uuid) returns void
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
end $$;

create function public.corrigir_presenca(p_turma uuid, p_colaborador uuid, p_situacao public.situacao_participante, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo da correção'; end if;
  if p_situacao not in ('presente', 'ausente') then raise exception 'Situação inválida'; end if;
  update turma_participantes set situacao = p_situacao, registrado_por = auth.uid(), registrado_em = now() where turma_id = p_turma and colaborador_id = p_colaborador;
  if not found then raise exception 'Esta pessoa não está na lista da turma'; end if;
  insert into eventos (tabela, registro_id, acao, depois, usuario) values ('turma_participantes', p_turma::text, 'correcao', jsonb_build_object('colaborador_id', p_colaborador, 'situacao', p_situacao, 'motivo', p_motivo), auth.uid());
  update turmas set status = case when exists (select 1 from turma_participantes where turma_id = p_turma and situacao = 'presente') then 'realizada'::status_turma else 'encerrada'::status_turma end where id = p_turma and status in ('realizada', 'encerrada');
end $$;

-- Leituras
create function public.turma_detalhe(p_turma uuid) returns jsonb
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
    'participantes', (select coalesce(jsonb_agg(jsonb_build_object('colaborador_id', c.id, 'nome', c.nome, 'cargo', cg.nome, 'situacao', p.situacao, 'origem', p.origem) order by c.nome), '[]')
               from turma_participantes p join colaboradores c on c.id = p.colaborador_id left join cargos cg on cg.id = p.cargo_na_data_id
               where p.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email() or app.pode_ver_colaborador(c.id))),
    'solicitacoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.solicitado_em desc), '[]') from turma_solicitacoes s where s.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email())),
    'conflitos', conflitos_turma(t.id))
  into r from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.id = p_turma;
  return r;
end $$;

create function public.listar_turmas() returns table (
  id uuid, treinamento text, tipo public.tipo_turma, status public.status_turma, etapa text, data date, hora time, sala text, instrutor_email text,
  participantes bigint, presentes bigint, ausentes bigint, solicitacao_aberta boolean, conflito boolean, motivo text)
language sql stable security definer set search_path = public as $$
  select t.id, tr.nome, t.tipo, t.status, app.etapa_turma(t.status, app.periodo_turma(t.id)), t.data, coalesce(t.hora_inicio, t.hora_opcao_1), t.sala, t.instrutor_email,
    (select count(*) from turma_participantes p where p.turma_id = t.id and p.situacao <> 'nao_aplicavel'),
    (select count(*) from turma_participantes p where p.turma_id = t.id and p.situacao = 'presente'),
    (select count(*) from turma_participantes p where p.turma_id = t.id and p.situacao = 'ausente'),
    exists (select 1 from turma_solicitacoes s where s.turma_id = t.id and s.status = 'aberta'),
    t.status in ('agenda_confirmada', 'precisa_replanejar') and jsonb_array_length(conflitos_turma(t.id)) > 0,
    t.motivo_replanejamento
  from turmas t join treinamentos tr on tr.id = t.treinamento_id
  where app.pode_ver_turma(t.id)
  order by t.data desc nulls last, t.criado_em desc
$$;

create function public.minhas_turmas() returns table (
  id uuid, treinamento text, status public.status_turma, etapa text, data date, hora time, hora_opcao_1 time, hora_opcao_2 time, sala text, participantes bigint, pendentes bigint, solicitacao_aberta boolean)
language sql stable security definer set search_path = public as $$
  select t.id, tr.nome, t.status, app.etapa_turma(t.status, app.periodo_turma(t.id)), t.data, coalesce(t.hora_inicio, t.hora_opcao_1), t.hora_opcao_1, t.hora_opcao_2, t.sala,
    (select count(*) from turma_participantes p where p.turma_id = t.id and p.situacao <> 'nao_aplicavel'),
    (select count(*) from turma_participantes p where p.turma_id = t.id and p.situacao = 'convocado'),
    exists (select 1 from turma_solicitacoes s where s.turma_id = t.id and s.status = 'aberta')
  from turmas t join treinamentos tr on tr.id = t.treinamento_id
  where t.instrutor_email = app.meu_email() and t.status not in ('cancelada')
  order by t.data desc nulls last
$$;

-- Situação de cada obrigatório por pessoa. Regra única para prontuário, faróis e indicadores.
create function app.situacao_base(p_colaborador uuid default null) returns table (
  colaborador_id uuid, treinamento_id uuid, treinamento text, situacao text, turma_id uuid, data_turma date, ultima date)
language sql stable security definer set search_path = public as $$
  with base as (
    select c.id as colaborador_id, c.cargo_id, app.data_referencia(c.id) as ref, app.decisao_vigente(c.id) as dec
    from colaboradores c where c.ativo and (p_colaborador is null or c.id = p_colaborador)
  ), itens as (
    select b.*, m.treinamento_id from base b cross join lateral matriz_vigente_em(b.cargo_id, coalesce(b.ref, app.hoje())) m where m.obrigatorio
    union
    select b.*, x.t from base b cross join lateral unnest((b.dec).treinamentos_parcial) as x(t) where (b.dec).acao_final = 'parcial'
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

create function public.situacao_colaborador(p_colaborador uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.pode_ver_colaborador(p_colaborador) then raise exception 'Sem acesso' using errcode = '42501'; end if;
  select jsonb_build_object(
    'colaborador', to_jsonb(c) || jsonb_build_object('cargo', cg.nome, 'departamento', d.nome, 'data_referencia', app.data_referencia(c.id)),
    'itens', (select coalesce(jsonb_agg(to_jsonb(s) order by s.treinamento), '[]') from app.situacao_base(c.id) s),
    'historico', (select coalesce(jsonb_agg(jsonb_build_object('turma_id', t.id, 'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'data', t.data, 'situacao', p.situacao, 'origem', p.origem, 'instrutor_email', t.instrutor_email, 'cargo', cp.nome) order by t.data desc nulls last), '[]')
                  from turma_participantes p join turmas t on t.id = p.turma_id join treinamentos tr on tr.id = t.treinamento_id left join cargos cp on cp.id = p.cargo_na_data_id
                  where p.colaborador_id = c.id and p.situacao in ('presente', 'ausente', 'a_validar', 'convocado')),
    'movimentacoes', (select coalesce(jsonb_agg(jsonb_build_object('cargo', cm.nome, 'data_inicio', m.data_inicio, 'data_fim', m.data_fim, 'tipo', m.tipo) order by m.data_inicio desc), '[]')
                      from movimentacoes m join cargos cm on cm.id = m.cargo_id where m.colaborador_id = c.id),
    'decisao', (select to_jsonb(x) from (select (app.decisao_vigente(c.id)).*) x where x.id is not null and (app.eh_admin() or c.id = app.meu_colaborador())))
  into r from colaboradores c left join cargos cg on cg.id = c.cargo_id left join departamentos d on d.id = c.departamento_id where c.id = p_colaborador;
  return r;
end $$;

create function app.precisa_classificar(p_colaborador uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select (select count(*) from movimentacoes m where m.colaborador_id = p_colaborador) >= 2
     and (app.decisao_vigente(p_colaborador)).id is null
$$;

create function public.painel_colaboradores() returns table (
  id uuid, nome text, cargo text, departamento_id uuid, departamento text, ativo boolean, data_referencia date,
  total bigint, realizados bigint, agendados bigint, pendentes bigint, dispensados bigint, classificar boolean, farol text, motivo text)
language sql stable security definer set search_path = public as $$
  with s as (select * from app.situacao_base()),
  a as (select colaborador_id,
    count(*) as total,
    count(*) filter (where situacao = 'realizado') as realizados,
    count(*) filter (where situacao in ('agendado', 'planejado')) as agendados,
    count(*) filter (where situacao in ('pendente', 'ausente')) as pendentes,
    count(*) filter (where situacao = 'dispensado') as dispensados
    from s group by 1)
  select c.id, c.nome, cg.nome, c.departamento_id, d.nome, c.ativo, r.ref,
    coalesce(a.total, 0), coalesce(a.realizados, 0), coalesce(a.agendados, 0), coalesce(a.pendentes, 0), coalesce(a.dispensados, 0), k.classificar,
    case when not c.ativo then 'inativo'
      when coalesce(a.pendentes, 0) > 0 and (r.ref is null or r.ref + app.param_int('janela_convocacao_dias') < app.hoje()) then 'vermelho'
      when coalesce(a.pendentes, 0) > 0 or coalesce(a.agendados, 0) > 0 or k.classificar then 'amarelo'
      else 'verde' end,
    case when not c.ativo then 'Inativo'
      when coalesce(a.pendentes, 0) > 0 and (r.ref is null or r.ref + app.param_int('janela_convocacao_dias') < app.hoje()) then a.pendentes || ' pendente(s) sem turma, fora da janela'
      when k.classificar then 'Movimentação a classificar'
      when coalesce(a.pendentes, 0) > 0 then a.pendentes || ' pendente(s) a planejar'
      when coalesce(a.agendados, 0) > 0 then a.agendados || ' com turma'
      when coalesce(a.dispensados, 0) > 0 and coalesce(a.realizados, 0) = 0 then 'Termo de Dispensa emitido'
      else 'Em dia' end
  from colaboradores c
  left join cargos cg on cg.id = c.cargo_id left join departamentos d on d.id = c.departamento_id
  left join a on a.colaborador_id = c.id
  cross join lateral (select app.data_referencia(c.id) as ref, app.precisa_classificar(c.id) as classificar) r
  cross join lateral (select r.classificar) k
  where app.pode_ver_colaborador(c.id)
  order by c.nome
$$;

-- O que precisa de turma: pessoas na janela, com decisão de reciclagem ou ausentes.
create function public.a_planejar() returns table (treinamento_id uuid, treinamento text, tipo public.tipo_turma, pessoas jsonb, cargos jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  return query
  with s as (
    select b.*, c.nome, c.cargo_id, cg.nome as cargo, app.data_referencia(c.id) as ref,
      app.exigido_por_decisao(c.id, b.treinamento_id) as por_decisao
    from app.situacao_base() b join colaboradores c on c.id = b.colaborador_id join cargos cg on cg.id = c.cargo_id
    where b.situacao in ('pendente', 'ausente')
  ), f as (
    select * from s where por_decisao or situacao = 'ausente' or ref >= app.hoje() - app.param_int('janela_convocacao_dias')
  )
  select f.treinamento_id, f.treinamento,
    case when bool_or(f.por_decisao) then 'reciclagem'::tipo_turma else 'normal'::tipo_turma end,
    jsonb_agg(jsonb_build_object('colaborador_id', f.colaborador_id, 'nome', f.nome, 'cargo', f.cargo, 'motivo', case when f.situacao = 'ausente' then 'Ausente em turma anterior' when f.por_decisao then 'Reciclagem' else 'Admissão ou movimentação na janela' end) order by f.nome),
    (select jsonb_agg(x) from (select distinct f2.cargo_id, f2.cargo as nome from f f2 where f2.treinamento_id = f.treinamento_id) x)
  from f group by f.treinamento_id, f.treinamento order by f.treinamento;
end $$;

-- Fila do dia de Gente e Gestão: o que está parado, com a ação em cada linha.
create function public.fila_inicio() returns table (grupo text, urgente boolean, titulo text, detalhe text, turma_id uuid, colaborador_id uuid, solicitacao_id uuid)
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
  from notificacoes n where n.status = 'erro';
end $$;

-- Matriz por revisão
create function public.iniciar_revisao(p_descricao text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_ano text := to_char(app.hoje(), 'YYYY'); v_seq integer;
begin
  perform app.exigir_admin();
  if length(coalesce(trim(p_descricao), '')) < 10 then raise exception 'Descreva a revisão com ao menos 10 caracteres'; end if;
  select coalesce(max(substring(numero from 7)::integer), 0) + 1 into v_seq from matriz_revisoes where numero like 'R' || v_ano || '-%';
  insert into matriz_revisoes (numero, descricao, criado_por) values ('R' || v_ano || '-' || lpad(v_seq::text, 3, '0'), p_descricao, auth.uid()) returning id into v_id;
  return v_id;
end $$;

create function public.alternar_vinculo(p_cargo uuid, p_treinamento uuid, p_marcar boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_rev uuid;
begin
  perform app.exigir_admin();
  select id into v_rev from matriz_revisoes where status = 'aberta';
  if v_rev is null then raise exception 'Inicie uma revisão para alterar a matriz'; end if;
  if p_marcar then
    update matriz_vinculos set revisao_remocao_id = null where cargo_id = p_cargo and treinamento_id = p_treinamento and revisao_remocao_id = v_rev;
    if not found and not exists (select 1 from matriz_vinculos where cargo_id = p_cargo and treinamento_id = p_treinamento and revisao_remocao_id is null) then
      insert into matriz_vinculos (cargo_id, treinamento_id, revisao_criacao_id) values (p_cargo, p_treinamento, v_rev);
    end if;
  else
    delete from matriz_vinculos where cargo_id = p_cargo and treinamento_id = p_treinamento and revisao_criacao_id = v_rev and revisao_remocao_id is null;
    update matriz_vinculos set revisao_remocao_id = v_rev where cargo_id = p_cargo and treinamento_id = p_treinamento and revisao_remocao_id is null;
  end if;
end $$;

create function public.publicar_revisao(p_vigencia date default null) returns void
language plpgsql security definer set search_path = public as $$
declare v_rev uuid; r record;
begin
  perform app.exigir_admin();
  select id into v_rev from matriz_revisoes where status = 'aberta';
  if v_rev is null then raise exception 'Não há revisão aberta'; end if;
  update matriz_revisoes set status = 'vigente', data_inicio_vigencia = coalesce(p_vigencia, app.hoje()), fechado_em = now() where id = v_rev;
  for r in select distinct cargo_id from matriz_vinculos where v_rev in (revisao_criacao_id, revisao_remocao_id) loop
    perform app.sincronizar_turmas_do_cargo(r.cargo_id);
  end loop;
end $$;

create function public.cancelar_revisao() returns void
language plpgsql security definer set search_path = public as $$
declare v_rev uuid;
begin
  perform app.exigir_admin();
  select id into v_rev from matriz_revisoes where status = 'aberta';
  if v_rev is null then raise exception 'Não há revisão aberta'; end if;
  update matriz_vinculos set revisao_remocao_id = null where revisao_remocao_id = v_rev;
  delete from matriz_vinculos where revisao_criacao_id = v_rev;
  update matriz_revisoes set status = 'arquivada', fechado_em = now() where id = v_rev;
end $$;

-- Quadro da matriz de um cargo: o que vale agora e o que está na revisão aberta.
create function public.matriz_do_cargo(p_cargo uuid) returns table (treinamento_id uuid, treinamento text, marcado boolean, vigente boolean)
language sql stable security definer set search_path = public as $$
  select t.id, t.nome,
    exists (select 1 from matriz_vinculos v left join matriz_revisoes c on c.id = v.revisao_criacao_id
            where v.cargo_id = p_cargo and v.treinamento_id = t.id and v.revisao_remocao_id is null and c.status in ('vigente', 'aberta')),
    exists (select 1 from matriz_vigente_em(p_cargo, app.hoje()) m where m.treinamento_id = t.id)
  from treinamentos t where t.ativo and app.le_tudo() order by t.nome
$$;

-- Colaborador e movimentação em uma transação
create function public.salvar_colaborador(p_id uuid, p_nome text, p_email text, p_cargo uuid, p_data_admissao date, p_ativo boolean default true) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid := p_id; v_dep uuid;
begin
  perform app.exigir_admin();
  if coalesce(trim(p_nome), '') = '' then raise exception 'Informe o nome'; end if;
  select departamento_id into v_dep from cargos where id = p_cargo and ativo;
  if not found then raise exception 'Escolha um cargo ativo'; end if;
  if v_id is null then
    if p_data_admissao is null then raise exception 'Informe a data de admissão'; end if;
    insert into colaboradores (nome, email, cargo_id, departamento_id, data_admissao) values (trim(p_nome), lower(nullif(trim(p_email), '')), null, v_dep, p_data_admissao) returning id into v_id;
    insert into movimentacoes (colaborador_id, cargo_id, departamento_id, data_inicio, tipo) values (v_id, p_cargo, v_dep, p_data_admissao, 'admissao');
    update colaboradores set cargo_id = p_cargo where id = v_id;
  else
    update colaboradores set nome = trim(p_nome), email = lower(nullif(trim(p_email), '')), data_admissao = coalesce(p_data_admissao, data_admissao), ativo = p_ativo where id = v_id;
    if not p_ativo then update movimentacoes set data_fim = app.hoje() where colaborador_id = v_id and data_fim is null; end if;
  end if;
  return v_id;
end $$;

create function public.registrar_movimentacao(p_colaborador uuid, p_cargo uuid, p_data date, p_tipo public.tipo_movimentacao) returns void
language plpgsql security definer set search_path = public as $$
declare v_dep uuid;
begin
  perform app.exigir_admin();
  if p_data is null then raise exception 'Informe a data da movimentação'; end if;
  select departamento_id into v_dep from cargos where id = p_cargo and ativo;
  if not found then raise exception 'Escolha um cargo ativo'; end if;
  if exists (select 1 from colaboradores where id = p_colaborador and cargo_id = p_cargo) then raise exception 'A pessoa já está neste cargo'; end if;
  update movimentacoes set data_fim = p_data where colaborador_id = p_colaborador and data_fim is null;
  insert into movimentacoes (colaborador_id, cargo_id, departamento_id, data_inicio, tipo) values (p_colaborador, p_cargo, v_dep, p_data, p_tipo);
  update colaboradores set cargo_id = p_cargo, departamento_id = v_dep where id = p_colaborador;
end $$;

-- Reciclagem: mesma regra da função sugerirReciclagem do sistema atual.
create function public.sugerir_reciclagem(p_colaborador uuid, p_tipo public.reciclagem_tipo) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  c colaboradores; v_ant movimentacoes; v_atual_inicio date; v_tempo integer; v_recente boolean; v_aplica boolean;
  v_atuais uuid[]; v_anteriores uuid[]; v_tec uuid[]; v_pol uuid[]; v_acao reciclagem_acao; v_parcial uuid[] := '{}';
begin
  perform app.exigir_admin();
  select * into c from colaboradores where id = p_colaborador;
  select * into v_ant from movimentacoes where colaborador_id = p_colaborador order by data_inicio desc offset 1 limit 1;
  if v_ant.id is null then return null; end if;
  select max(data_inicio) into v_atual_inicio from movimentacoes where colaborador_id = p_colaborador;
  v_tempo := coalesce((extract(year from age(app.hoje(), c.data_admissao)) * 12 + extract(month from age(app.hoje(), c.data_admissao)))::integer, 0);
  v_recente := (extract(year from age(v_atual_inicio, v_ant.data_inicio)) * 12 + extract(month from age(v_atual_inicio, v_ant.data_inicio))) < app.param_int('meses_movimentacao');
  v_aplica := v_tempo >= app.param_int('meses_politicas') and not v_recente;
  select coalesce(array_agg(treinamento_id), '{}') into v_atuais from matriz_vigente_em(c.cargo_id, app.hoje());
  select coalesce(array_agg(treinamento_id), '{}') into v_anteriores from matriz_vigente_em(v_ant.cargo_id, app.hoje());
  select coalesce(array_agg(t.id), '{}') into v_tec from treinamentos t where t.id = any (v_atuais) and not (t.id = any (v_anteriores)) and not t.eh_politica;
  select coalesce(array_agg(t.id), '{}') into v_pol from treinamentos t where v_aplica and t.id = any (v_atuais) and t.eh_politica;
  if cardinality(v_tec) = 0 and cardinality(v_pol) = 0 then v_acao := 'dispensa';
  elsif p_tipo = 'step_horizontal' then
    if cardinality(v_pol) = 0 then v_acao := 'dispensa'; else v_acao := 'parcial'; v_parcial := v_pol; end if;
  elsif not v_aplica then v_acao := 'parcial'; v_parcial := v_tec;
  elsif cardinality(v_atuais) > 0 and cardinality(v_tec) = cardinality(v_atuais) then v_acao := 'total';
  else v_acao := 'parcial'; v_parcial := v_tec || v_pol;
  end if;
  return jsonb_build_object('acao_sugerida', v_acao, 'treinamentos_parcial', to_jsonb(v_parcial), 'tempo_empresa_meses', v_tempo, 'movimentacao_recente', v_recente,
    'cargo_anterior_id', v_ant.cargo_id, 'cargo_anterior', (select nome from cargos where id = v_ant.cargo_id), 'cargo_atual_id', c.cargo_id, 'cargo_atual', (select nome from cargos where id = c.cargo_id),
    'data_anterior', v_ant.data_inicio, 'data_atual', v_atual_inicio,
    'matriz_atual', (select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'nome', t.nome, 'eh_politica', t.eh_politica) order by t.nome), '[]') from treinamentos t where t.id = any (v_atuais)));
end $$;

create function public.confirmar_reciclagem(p_colaborador uuid, p_tipo public.reciclagem_tipo, p_acao public.reciclagem_acao, p_treinamentos uuid[] default '{}') returns uuid
language plpgsql security definer set search_path = public as $$
declare v_sug jsonb; v_id uuid; c colaboradores;
begin
  perform app.exigir_admin();
  v_sug := sugerir_reciclagem(p_colaborador, p_tipo);
  if v_sug is null then raise exception 'Esta pessoa não tem movimentação para classificar'; end if;
  if p_acao = 'parcial' and coalesce(cardinality(p_treinamentos), 0) = 0 then raise exception 'Escolha ao menos um treinamento para a reciclagem parcial'; end if;
  select * into c from colaboradores where id = p_colaborador;
  insert into reciclagem_decisoes (colaborador_id, cargo_anterior_id, cargo_atual_id, tipo_movimentacao, acao_sugerida, acao_final, treinamentos_parcial, decidido_por)
  values (p_colaborador, (v_sug ->> 'cargo_anterior_id')::uuid, c.cargo_id, p_tipo, (v_sug ->> 'acao_sugerida')::reciclagem_acao, p_acao,
          case when p_acao = 'parcial' then p_treinamentos else '{}' end, auth.uid()) returning id into v_id;
  perform app.sincronizar_turmas_do_cargo(c.cargo_id);
  return v_id;
end $$;

create function public.movimentacoes_pendentes() returns table (colaborador_id uuid, nome text, cargo_atual text, cargo_anterior text, data_movimentacao date, decisao public.reciclagem_acao, decidido_em timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  return query
  select c.id, c.nome, cg.nome, ca.nome, m.data_inicio, (app.decisao_vigente(c.id)).acao_final, (app.decisao_vigente(c.id)).decidido_em
  from colaboradores c join cargos cg on cg.id = c.cargo_id
  join lateral (select x.* from movimentacoes x where x.colaborador_id = c.id order by x.data_inicio desc limit 1) m on true
  join lateral (select x.* from movimentacoes x where x.colaborador_id = c.id order by x.data_inicio desc offset 1 limit 1) a on true
  join cargos ca on ca.id = a.cargo_id
  where c.ativo order by (app.decisao_vigente(c.id)).id is not null, m.data_inicio desc;
end $$;

create function public.indicadores() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.le_tudo() then raise exception 'Sem acesso' using errcode = '42501'; end if;
  with s as (select b.*, c.departamento_id from app.situacao_base() b join colaboradores c on c.id = b.colaborador_id),
  p as (select * from painel_colaboradores() where ativo)
  select jsonb_build_object(
    'colaboradores', (select count(*) from p),
    'verde', (select count(*) from p where farol = 'verde'), 'amarelo', (select count(*) from p where farol = 'amarelo'), 'vermelho', (select count(*) from p where farol = 'vermelho'),
    'obrigatorios', (select count(*) from s where situacao <> 'dispensado'), 'realizados', (select count(*) from s where situacao = 'realizado'),
    'agendados', (select count(*) from s where situacao in ('agendado', 'planejado')), 'pendentes', (select count(*) from s where situacao in ('pendente', 'ausente')),
    'dispensados', (select count(*) from s where situacao = 'dispensado'),
    'horas_homem', (select coalesce(sum(tr.carga_minutos), 0) / 60.0 from turma_participantes tp join turmas t on t.id = tp.turma_id join treinamentos tr on tr.id = t.treinamento_id where tp.situacao = 'presente'),
    'turmas_abertas', (select count(*) from turmas where status in ('aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado')),
    'turmas_realizadas', (select count(*) from turmas where status = 'realizada'),
    'por_departamento', (select coalesce(jsonb_agg(x order by x.departamento), '[]') from (
        select d.nome as departamento, count(*) filter (where s.situacao <> 'dispensado') as obrigatorios, count(*) filter (where s.situacao = 'realizado') as realizados
        from s join departamentos d on d.id = s.departamento_id group by d.nome) x),
    'por_mes', (select coalesce(jsonb_agg(x order by x.mes), '[]') from (
        select to_char(t.data, 'YYYY-MM') as mes, count(distinct t.id) as turmas, count(*) filter (where tp.situacao = 'presente') as presentes
        from turmas t join turma_participantes tp on tp.turma_id = t.id where t.status in ('realizada', 'encerrada') and t.data >= app.hoje() - 365 group by 1) x)
  ) into r;
  return r;
end $$;

-- Rotina diária e fila de envio: só para o n8n (service_role).
create function public.rotina_diaria() returns integer
language plpgsql security definer set search_path = public as $$
declare v integer := 0; n integer;
begin
  insert into notificacoes (tipo, turma_id, destinatario)
  select 'lembrete_agenda', t.id, t.instrutor_email from turmas t
  where t.status = 'aguardando_instrutor' and t.criado_em + make_interval(days => app.param_int('prazo_resposta_instrutor_dias')) < now()
    and not exists (select 1 from turma_solicitacoes s where s.turma_id = t.id and s.status = 'aberta')
    and not exists (select 1 from notificacoes n where n.turma_id = t.id and n.tipo = 'lembrete_agenda' and n.criado_em > now() - interval '2 days');
  get diagnostics n = row_count; v := v + n;
  insert into notificacoes (tipo, turma_id, destinatario)
  select 'lembrete_presenca', t.id, t.instrutor_email from turmas t
  where t.status = 'convite_enviado' and upper(app.periodo_turma(t.id)) + make_interval(days => app.param_int('prazo_presenca_dias')) < now()
    and not exists (select 1 from notificacoes n where n.turma_id = t.id and n.tipo = 'lembrete_presenca' and n.criado_em > now() - interval '2 days');
  get diagnostics n = row_count;
  return v + n;
end $$;

create function public.notificacoes_para_envio(p_limite integer default 50) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x), '[]') from (
    select n.id, n.tipo, n.destinatario, n.turma_id, n.tentativas, t.outlook_evento_id,
      tr.nome as treinamento, t.data, t.hora_inicio, tr.carga_minutos, t.sala, t.status as turma_status
    from notificacoes n left join turmas t on t.id = n.turma_id left join treinamentos tr on tr.id = t.treinamento_id
    where n.status = 'pendente' or (n.status = 'erro' and n.tentativas < 3)
    order by n.criado_em limit p_limite) x
$$;

create function public.registrar_envio(p_notificacao uuid, p_ok boolean, p_erro text default null, p_evento_id text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  update notificacoes set status = case when p_ok then 'enviada'::status_notificacao else 'erro'::status_notificacao end, tentativas = tentativas + 1, erro = p_erro, enviado_em = case when p_ok then now() end where id = p_notificacao;
  if p_evento_id is not null then update turmas set outlook_evento_id = p_evento_id where id = (select turma_id from notificacoes where id = p_notificacao); end if;
end $$;

create function public.reenviar_notificacao(p_notificacao uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  update notificacoes set status = 'pendente', tentativas = 0, erro = null where id = p_notificacao and status = 'erro';
end $$;

-- Permissões: nada para anon; funções do site só para logados; envio só para service_role.
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura, n.nspname, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname in ('public', 'app') and p.prokind = 'f' and p.proname not in ('unaccent') loop
    execute format('revoke all on function %s from public, anon', f.assinatura);
    if f.proname in ('rotina_diaria', 'notificacoes_para_envio', 'registrar_envio') then
      execute format('revoke all on function %s from authenticated', f.assinatura);
      execute format('grant execute on function %s to service_role', f.assinatura);
    elsif f.proname in ('registrar_evento', 'gatilho_colaborador', 'notificar', 'sincronizar_participantes', 'sincronizar_turmas_do_cargo', 'aplicar_alteracao') then
      execute format('revoke all on function %s from authenticated', f.assinatura);
    else
      execute format('grant execute on function %s to authenticated', f.assinatura);
    end if;
  end loop;
end $$;
