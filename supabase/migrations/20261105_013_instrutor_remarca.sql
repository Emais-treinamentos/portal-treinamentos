-- O instrutor remarca direto, sem passar por Gente e Gestão, desde que ninguém fique indisponível e dentro do prazo.
-- Prazo: a janela de convocação, contada da admissão ou movimentação mais antiga entre os convocados.
-- Passou do prazo, só Gente e Gestão altera. Assim o treinamento não é empurrado para frente sem fim.

create function app.limite_remarcacao(p_turma uuid) returns date
language sql stable security definer set search_path = public as $$
  select min(app.data_referencia(p.colaborador_id)) + app.param_int('janela_convocacao_dias')
  from turma_participantes p where p.turma_id = p_turma and p.situacao = 'convocado'
$$;

-- Outras turmas perto da data, com o horário confirmado ou, se ainda sem resposta, com os horários sugeridos.
create function app.turmas_ocupadas(p_turma uuid, p_data date) returns table (id uuid, treinamento text, sala text, instrutor_email text, periodo tstzrange, inicio time, fim time, confirmada boolean)
language sql stable security definer set search_path = public as $$
  select o.id, tr.nome, o.sala, o.instrutor_email,
    tstzrange((o.data + h.hora) at time zone 'America/Sao_Paulo', ((o.data + h.hora) at time zone 'America/Sao_Paulo') + make_interval(mins => tr.carga_minutos)),
    h.hora, (h.hora + make_interval(mins => tr.carga_minutos))::time, o.status <> 'aguardando_instrutor'
  from turmas o join treinamentos tr on tr.id = o.treinamento_id
  cross join lateral (select o.hora_inicio as hora where o.status in ('agenda_confirmada', 'convite_enviado')
    union all select o.hora_opcao_1 where o.status = 'aguardando_instrutor'
    union all select o.hora_opcao_2 where o.status = 'aguardando_instrutor') h
  where o.id <> p_turma and h.hora is not null and o.data between p_data - 1 and p_data + 1
$$;

create function public.verificar_novo_horario(p_turma uuid, p_data date default null, p_hora time default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  t turmas; v_carga integer; v_limite date := app.limite_remarcacao(p_turma); v_aberto boolean; v_per tstzrange;
  v_pessoas jsonb; v_instrutor jsonb; v_sala jsonb; v_passado boolean; v_fora boolean; v_igual boolean; v_antes text;
begin
  select * into t from turmas where id = p_turma;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not (app.eh_instrutor_da_turma(p_turma) or app.eh_admin()) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  v_aberto := v_limite is null or v_limite >= app.hoje();
  if p_data is null or p_hora is null then
    return jsonb_build_object('ok', false, 'limite', v_limite, 'prazo_aberto', v_aberto, 'indisponiveis', '[]'::jsonb, 'instrutor', '[]'::jsonb, 'sala', '[]'::jsonb);
  end if;
  select carga_minutos into v_carga from treinamentos where id = t.treinamento_id;
  v_per := tstzrange((p_data + p_hora) at time zone 'America/Sao_Paulo', ((p_data + p_hora) at time zone 'America/Sao_Paulo') + make_interval(mins => v_carga));
  v_passado := lower(v_per) <= now();
  v_fora := v_limite is not null and p_data > v_limite;
  v_igual := t.data = p_data and t.hora_inicio = p_hora;
  -- Antes da admissão a pessoa sairia da turma sem ninguém perceber.
  select string_agg(c.nome, ', ' order by c.nome) into v_antes from turma_participantes p join colaboradores c on c.id = p.colaborador_id
    where p.turma_id = p_turma and p.situacao = 'convocado' and app.data_referencia(p.colaborador_id) > p_data;

  select coalesce(jsonb_agg(x order by x.nome, x.inicio), '[]') into v_pessoas from (
    select distinct c.nome, oc.treinamento, to_char(oc.inicio, 'HH24:MI') as inicio, to_char(oc.fim, 'HH24:MI') as fim, oc.confirmada
    from turma_participantes pa join colaboradores c on c.id = pa.colaborador_id
    join turma_participantes po on po.colaborador_id = pa.colaborador_id and po.situacao <> 'nao_aplicavel'
    join app.turmas_ocupadas(p_turma, p_data) oc on oc.id = po.turma_id and oc.periodo && v_per
    where pa.turma_id = p_turma and pa.situacao = 'convocado') x;
  select coalesce(jsonb_agg(x order by x.inicio), '[]') into v_instrutor from (
    select distinct oc.treinamento, to_char(oc.inicio, 'HH24:MI') as inicio, to_char(oc.fim, 'HH24:MI') as fim
    from app.turmas_ocupadas(p_turma, p_data) oc where oc.instrutor_email = t.instrutor_email and oc.periodo && v_per) x;
  select coalesce(jsonb_agg(x order by x.inicio), '[]') into v_sala from (
    select distinct oc.treinamento, to_char(oc.inicio, 'HH24:MI') as inicio, to_char(oc.fim, 'HH24:MI') as fim
    from app.turmas_ocupadas(p_turma, p_data) oc where t.sala is not null and t.sala <> 'Externo' and oc.sala = t.sala and oc.confirmada and oc.periodo && v_per) x;

  return jsonb_build_object(
    'ok', v_aberto and not v_passado and not v_fora and not v_igual and v_antes is null and jsonb_array_length(v_pessoas) = 0 and jsonb_array_length(v_instrutor) = 0 and jsonb_array_length(v_sala) = 0,
    'limite', v_limite, 'prazo_aberto', v_aberto, 'passado', v_passado, 'fora_do_prazo', v_fora, 'igual', v_igual, 'antes_da_admissao', v_antes,
    'indisponiveis', v_pessoas, 'instrutor', v_instrutor, 'sala', v_sala);
end $$;

create function public.instrutor_remarcar(p_turma uuid, p_data date, p_hora time, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas; v jsonb; v_admin text; v_nomes text;
begin
  select * into t from turmas where id = p_turma for update;
  if not found then raise exception 'Turma não encontrada'; end if;
  if not app.eh_instrutor_da_turma(p_turma) then raise exception 'Esta turma não é sua' using errcode = '42501'; end if;
  if p_data is null or p_hora is null then raise exception 'Informe a nova data e o novo horário'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo'; end if;
  if t.status not in ('aguardando_instrutor', 'agenda_confirmada', 'convite_enviado') then raise exception 'Esta turma não pode mais ser remarcada'; end if;
  if t.status = 'convite_enviado' and upper(app.periodo_turma(p_turma)) <= now() then raise exception 'Este treinamento já aconteceu. Registre a presença ou fale com Gente e Gestão.'; end if;
  if exists (select 1 from turma_solicitacoes where turma_id = p_turma and status = 'aberta') then raise exception 'Há uma solicitação aberta nesta turma'; end if;
  v := verificar_novo_horario(p_turma, p_data, p_hora);
  if not (v ->> 'ok')::boolean then
    if not (v ->> 'prazo_aberto')::boolean then raise exception 'O prazo para remarcar terminou em %. Só Gente e Gestão pode alterar.', to_char((v ->> 'limite')::date, 'DD/MM/YYYY'); end if;
    if (v ->> 'fora_do_prazo')::boolean then raise exception 'A data limite para este treinamento é %.', to_char((v ->> 'limite')::date, 'DD/MM/YYYY'); end if;
    if (v ->> 'passado')::boolean then raise exception 'Escolha uma data e um horário futuros.'; end if;
    if (v ->> 'igual')::boolean then raise exception 'Este já é o horário do treinamento.'; end if;
    if v ->> 'antes_da_admissao' is not null then raise exception 'A data é anterior à admissão de %.', v ->> 'antes_da_admissao'; end if;
    select string_agg(distinct x ->> 'nome', ', ') into v_nomes from jsonb_array_elements(v -> 'indisponiveis') x;
    if v_nomes is not null then raise exception 'Horário indisponível para: %.', v_nomes; end if;
    if jsonb_array_length(v -> 'instrutor') > 0 then raise exception 'Você já tem outro treinamento neste horário.'; end if;
    raise exception 'A sala já está ocupada neste horário.';
  end if;

  update notificacoes set status = 'cancelada' where turma_id = p_turma and status = 'pendente' and tipo in ('aviso_instrutor', 'lembrete_agenda', 'lembrete_1h');
  update turmas set data = p_data, hora_inicio = p_hora, hora_opcao_1 = p_hora, hora_opcao_2 = null,
    status = case when status = 'aguardando_instrutor' then 'agenda_confirmada'::status_turma else status end,
    instrutor_respondeu_em = now() where id = p_turma;
  perform app.sincronizar_participantes(p_turma);
  -- Fica no histórico da turma, já resolvido. Gente e Gestão é informada, não precisa aprovar.
  insert into turma_solicitacoes (turma_id, tipo, motivo, proposta, status, resposta, solicitado_por, decidido_por, decidido_em)
  values (p_turma, 'alteracao', p_motivo, jsonb_build_object('data', p_data, 'hora', p_hora, 'data_anterior', t.data, 'hora_anterior', coalesce(t.hora_inicio, t.hora_opcao_1)), 'aprovada', 'Remarcado pelo instrutor dentro das regras', auth.uid(), auth.uid(), now());
  for v_admin in select email from usuarios where perfil = 'admin' and ativo loop
    perform app.notificar('alteracao_instrutor', p_turma, v_admin);
  end loop;
end $$;

insert into public.modelos_email (tipo, nome, quando, para, ordem, assunto, corpo) values
('alteracao_instrutor', 'Instrutor remarcou', 'Quando o instrutor muda a data ou o horário', 'Gente e Gestão', 65,
 'Treinamento remarcado pelo instrutor: {treinamento}',
 E'Olá,\n\nO instrutor remarcou este treinamento. Nenhum participante ficou com conflito de horário.\n\nTreinamento: {treinamento}\nNova data: {data}\nNovo horário: {horario}\nSala: {sala}\n\nParticipantes:\n{participantes}\n\n{link}');

update public.parametros set descricao = 'Dias depois da admissão ou movimentação em que a pessoa aparece em Planejar Treinamentos e entra nas turmas abertas do cargo. Também é o prazo máximo para o instrutor remarcar: depois dele, só Gente e Gestão altera.'
  where chave = 'janela_convocacao_dias';

revoke all on function app.limite_remarcacao(uuid), app.turmas_ocupadas(uuid, date) from public, anon, authenticated;
revoke all on function public.verificar_novo_horario(uuid, date, time), public.instrutor_remarcar(uuid, date, time, text) from public, anon;
grant execute on function public.verificar_novo_horario(uuid, date, time), public.instrutor_remarcar(uuid, date, time, text) to authenticated;
