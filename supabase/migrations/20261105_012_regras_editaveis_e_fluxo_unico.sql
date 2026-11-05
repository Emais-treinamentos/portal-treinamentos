-- Avisos num único fluxo do n8n, regras e textos de e-mail editáveis por Gente e Gestão.
-- O banco gera os avisos por horário e monta assunto e corpo. O n8n só busca, envia e registra.

-- Regras: cada uma descreve como é mostrada e validada.
alter table public.parametros
  add column rotulo text,
  add column grupo text,
  add column tipo text not null default 'inteiro' check (tipo in ('inteiro', 'data', 'url', 'lista')),
  add column minimo integer,
  add column maximo integer,
  add column unidade text,
  add column ordem integer not null default 100;

insert into public.parametros (chave, valor, descricao) values
  ('ativos_lista_dias', '30', 'x'),
  ('lembrete_minutos_antes', '60', 'x'),
  ('url_portal', 'https://emais-treinamentos.github.io/portal-treinamentos/', 'x')
on conflict (chave) do nothing;

update public.parametros p set rotulo = v.rotulo, grupo = v.grupo, tipo = v.tipo, minimo = v.minimo, maximo = v.maximo, unidade = v.unidade, ordem = v.ordem, descricao = v.descricao
from (values
  ('janela_convocacao_dias', 'Janela de convocação', 'Planejamento', 'inteiro', 1, 365, 'dias', 10, 'Dias depois da admissão ou movimentação em que a pessoa aparece em Planejar Treinamentos e entra nas turmas abertas do cargo.'),
  ('prazo_resposta_instrutor_dias', 'Prazo para o instrutor responder', 'Planejamento', 'inteiro', 1, 60, 'dias', 20, 'Depois desse prazo, o instrutor recebe um lembrete para confirmar a agenda.'),
  ('prazo_presenca_dias', 'Prazo para registrar a presença', 'Planejamento', 'inteiro', 1, 60, 'dias', 30, 'Dias depois do fim do treinamento até o instrutor receber o lembrete de presença pendente.'),
  ('prazo_reciclagem_dias', 'Prazo da reciclagem', 'Reciclagem', 'inteiro', 1, 3650, 'dias', 10, 'Dias desde o último treinamento para cobrar de novo em caso de movimentação.'),
  ('meses_politicas', 'Tempo de empresa para cobrar políticas', 'Reciclagem', 'inteiro', 1, 240, 'meses', 20, 'Meses de empresa a partir dos quais as políticas são cobradas na reciclagem.'),
  ('meses_movimentacao', 'Movimentação recente', 'Reciclagem', 'inteiro', 1, 240, 'meses', 30, 'Meses que definem uma movimentação como recente na reciclagem.'),
  ('prazo_eficacia_dias', 'Prazo da Avaliação de Eficácia', 'Avaliação de Eficácia', 'inteiro', 1, 730, 'dias', 10, 'Dias depois da admissão em que a avaliação fica disponível.'),
  ('eficacia_admissao_desde', 'Avaliar admissões a partir de', 'Avaliação de Eficácia', 'data', null, null, null, 20, 'Quem foi admitido antes dessa data não entra na Avaliação de Eficácia.'),
  ('ativos_lista_dias', 'Ativos na Lista de Presença', 'Lista de Presença', 'inteiro', 1, 365, 'dias', 10, 'Dias depois da admissão ou movimentação em que o colaborador fica na aba Ativos. Depois vai para o Histórico.'),
  ('lembrete_minutos_antes', 'Lembrete antes do treinamento', 'E-mails', 'inteiro', 15, 1440, 'minutos', 10, 'Quanto tempo antes do início o instrutor recebe o lembrete.'),
  ('url_portal', 'Endereço do portal', 'E-mails', 'url', null, null, null, 20, 'Link que vai nos e-mails.'),
  ('salas', 'Salas', 'Cadastros', 'lista', null, null, null, 900, 'Salas disponíveis. Edite em Cadastros, na aba Salas.')
) as v(chave, rotulo, grupo, tipo, minimo, maximo, unidade, ordem, descricao)
where p.chave = v.chave;

create function app.validar_parametro() returns trigger language plpgsql as $$
declare v_n bigint; v_d date;
begin
  if new.tipo = 'inteiro' then
    if new.valor !~ '^[0-9]{1,9}$' then raise exception '% precisa ser um número inteiro', coalesce(new.rotulo, new.chave) using errcode = '22023'; end if;
    v_n := new.valor::bigint;
    if v_n < coalesce(new.minimo, 0) or v_n > coalesce(new.maximo, 999999999) then
      raise exception '% precisa ficar entre % e %', coalesce(new.rotulo, new.chave), coalesce(new.minimo, 0), coalesce(new.maximo, 999999999) using errcode = '22023';
    end if;
  elsif new.tipo = 'data' then
    begin v_d := new.valor::date; exception when others then raise exception '% precisa ser uma data válida', coalesce(new.rotulo, new.chave) using errcode = '22023'; end;
  elsif new.tipo = 'url' then
    if new.valor !~ '^https://[^[:space:]<>"]+$' then raise exception '% precisa começar com https://', coalesce(new.rotulo, new.chave) using errcode = '22023'; end if;
  elsif new.tipo = 'lista' then
    begin
      if jsonb_typeof(new.valor::jsonb) <> 'array' then raise exception 'lista'; end if;
    exception when others then raise exception '% precisa ser uma lista', coalesce(new.rotulo, new.chave) using errcode = '22023'; end;
  end if;
  return new;
end $$;
create trigger valida before insert or update on public.parametros for each row execute function app.validar_parametro();

-- Textos dos e-mails.
create table public.modelos_email (
  tipo text primary key,
  nome text not null,
  quando text not null,
  para text not null,
  assunto text not null check (btrim(assunto) <> ''),
  corpo text not null check (btrim(corpo) <> ''),
  ativo boolean not null default true,
  ordem integer not null default 100,
  atualizado_em timestamptz not null default now()
);
alter table public.modelos_email enable row level security;
grant select, update on public.modelos_email to authenticated;
create policy leitura on public.modelos_email for select to authenticated using ((select app.eh_admin()));
create policy edicao on public.modelos_email for update to authenticated using ((select app.eh_admin()));
create trigger evento after insert or update or delete on public.modelos_email for each row execute function app.registrar_evento('tipo');

create function app.validar_modelo_email() returns trigger language plpgsql as $$
declare v_marca text;
begin
  for v_marca in select (regexp_matches(new.assunto || ' ' || new.corpo, '\{[^{}]*\}', 'g'))[1] loop
    if v_marca not in ('{treinamento}', '{data}', '{horario}', '{inicio}', '{sala}', '{participantes}', '{link}') then
      raise exception 'O campo % não existe. Use só os campos listados na tela.', v_marca using errcode = '22023';
    end if;
  end loop;
  new.atualizado_em := now();
  return new;
end $$;
create trigger valida before insert or update on public.modelos_email for each row execute function app.validar_modelo_email();

insert into public.modelos_email (tipo, nome, quando, para, ordem, assunto, corpo) values
('aviso_instrutor', 'Confirmar agenda', 'Quando Gente e Gestão envia a sugestão de agenda', 'Instrutor', 10,
 'Confirme sua agenda: {treinamento}',
 E'Olá,\n\nHá uma sugestão de agenda para um treinamento seu. Entre no portal com o seu usuário (o seu e-mail) para confirmar o horário.\n\nTreinamento: {treinamento}\nData: {data}\nHorário sugerido: {horario}\nSala: {sala}\n\nParticipantes:\n{participantes}\n\n{link}\n\nDepois de confirmar o horário, o convite do Outlook fica disponível no próprio portal.\n\nAtenciosamente,\nGente e Gestão'),
('lembrete_1h', 'Lembrete antes do treinamento', 'Antes do início, no prazo definido em Regras', 'Instrutor', 20,
 'Lembrete: {treinamento} hoje às {inicio}',
 E'Olá,\n\nSeu treinamento começa em breve.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\nSala: {sala}\n\nParticipantes:\n{participantes}\n\nAtenciosamente,\nGente e Gestão'),
('aviso_presenca', 'Confirmar presença', 'Quando o treinamento termina', 'Instrutor', 30,
 'Confirme a presença: {treinamento}',
 E'Olá,\n\nO treinamento terminou. Entre no portal com o seu usuário e confirme quem participou.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\nSala: {sala}\n\nParticipantes:\n{participantes}\n\n{link}\n\nAtenciosamente,\nGente e Gestão'),
('lembrete_agenda', 'Agenda sem resposta', 'Quando o prazo para responder a agenda acaba', 'Instrutor', 40,
 'Pendente: confirme sua agenda de {treinamento}',
 E'Olá,\n\nA agenda deste treinamento ainda não foi confirmada.\n\nTreinamento: {treinamento}\nData: {data}\nHorário sugerido: {horario}\n\nParticipantes:\n{participantes}\n\n{link}\n\nAtenciosamente,\nGente e Gestão'),
('lembrete_presenca', 'Presença pendente', 'Quando o prazo para registrar a presença acaba', 'Instrutor', 50,
 'Pendente: presença de {treinamento}',
 E'Olá,\n\nA presença deste treinamento ainda não foi registrada.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\n\nParticipantes:\n{participantes}\n\n{link}\n\nAtenciosamente,\nGente e Gestão'),
('aviso_decisao', 'Treinamento atualizado', 'Quando data, horário, sala ou uma solicitação muda', 'Instrutor', 60,
 'Atualização no treinamento: {treinamento}',
 E'Olá,\n\nHouve uma atualização neste treinamento. Se ele já está no seu Outlook, confira se o evento continua certo.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\nSala: {sala}\n\nParticipantes:\n{participantes}\n\n{link}\n\nAtenciosamente,\nGente e Gestão'),
('aviso_cancelamento', 'Treinamento cancelado', 'Quando a turma é cancelada', 'Instrutor', 70,
 'Treinamento cancelado: {treinamento}',
 E'Olá,\n\nEste treinamento foi cancelado. Se ele está no seu Outlook, exclua o evento da sua agenda.\n\nTreinamento: {treinamento}\nData: {data}\nHorário: {horario}\n\nAtenciosamente,\nGente e Gestão'),
('avaliacao_treinamento', 'Avaliar o treinamento', 'Quando a presença é registrada', 'Colaborador', 80,
 'Como foi o treinamento {treinamento}?',
 E'Olá,\n\nConte como foi o treinamento {treinamento}, realizado em {data}. Leva menos de 1 minuto e a sua resposta é confidencial.\n\n{link}\n\nAtenciosamente,\nGente e Gestão'),
('assinatura_solicitada', 'Assinar documento', 'Quando Gente e Gestão pede uma assinatura', 'Colaborador', 90,
 'Você tem um documento de treinamento para assinar',
 E'Olá,\n\nVocê tem um documento de treinamento para assinar. Entre no portal, em Meu Perfil.\n\n{link}\n\nAtenciosamente,\nGente e Gestão'),
('assinatura_concluida', 'Documento assinado', 'Quando o colaborador assina', 'Gente e Gestão', 100,
 'Documento assinado disponível para arquivar',
 E'Olá,\n\nUm colaborador assinou um documento. Baixe o arquivo em Lista de Presença para guardar no prontuário.\n\n{link}');

-- Quem pode ser instrutor agora inclui o gestor, que escolhe o perfil ao entrar.
create or replace function public.turma_detalhe(p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.pode_ver_turma(p_turma) then raise exception 'Sem acesso a esta turma' using errcode = '42501'; end if;
  select to_jsonb(t) || jsonb_build_object(
    'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'etapa', app.etapa_turma(t.status, app.periodo_turma(t.id)),
    'inicio', lower(app.periodo_turma(t.id)), 'fim', upper(app.periodo_turma(t.id)),
    'sou_instrutor', t.instrutor_email = app.meu_email(),
    'instrutor_tem_acesso', exists (select 1 from usuarios u where u.email = t.instrutor_email and u.ativo and u.perfil in ('instrutor', 'admin', 'gestor')),
    'cargos', (select coalesce(jsonb_agg(jsonb_build_object('cargo_id', c.id, 'nome', c.nome, 'incluir', tc.incluir_no_convite,
                 'elegiveis', (select count(*) from app.elegiveis(t.id) e where e.cargo_id = c.id)) order by c.nome), '[]')
               from turma_cargos tc join cargos c on c.id = tc.cargo_id where tc.turma_id = t.id),
    'participantes', (select coalesce(jsonb_agg(jsonb_build_object('colaborador_id', c.id, 'nome', c.nome, 'cargo', cg.nome, 'situacao', p.situacao, 'origem', p.origem, 'codigo', p.codigo_presenca) order by c.nome), '[]')
               from turma_participantes p join colaboradores c on c.id = p.colaborador_id left join cargos cg on cg.id = p.cargo_na_data_id
               where p.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email() or app.pode_ver_colaborador(c.id))),
    'solicitacoes', (select coalesce(jsonb_agg(to_jsonb(s) order by s.solicitado_em desc), '[]') from turma_solicitacoes s where s.turma_id = t.id and (app.le_tudo() or t.instrutor_email = app.meu_email())),
    'conflitos', conflitos_turma(t.id))
  into r from turmas t join treinamentos tr on tr.id = t.treinamento_id where t.id = p_turma;
  return r;
end $$;

create or replace function public.definir_sala(p_turma uuid, p_sala text) returns void
language plpgsql security definer set search_path = public as $$
declare t turmas;
begin
  perform app.exigir_admin();
  select * into t from turmas where id = p_turma for update;
  if t.status not in ('aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado') then raise exception 'A sala desta turma não pode mais ser alterada'; end if;
  update turmas set sala = p_sala where id = p_turma;
  if t.status = 'convite_enviado' and t.sala is distinct from p_sala then perform app.notificar('aviso_decisao', p_turma, t.instrutor_email); end if;
end $$;

-- Só entra na fila o que tem modelo ativo. O convite do Outlook sai do portal, então não há mais e-mail de calendário.
create or replace function app.notificar(p_tipo text, p_turma uuid, p_destinatario text) returns void
language sql security definer set search_path = public as $$
  insert into notificacoes (tipo, turma_id, destinatario)
  select p_tipo, p_turma, p_destinatario
  where p_destinatario is not null and exists (select 1 from modelos_email m where m.tipo = p_tipo and m.ativo)
$$;

-- Avisos que dependem do horário. A chave evita repetir; se a turma muda de horário, a chave muda e o aviso sai de novo.
alter table public.notificacoes add column chave text;
create unique index notificacoes_chave on public.notificacoes (chave) where chave is not null;
update public.notificacoes set status = 'cancelada', erro = 'Sem e-mail de calendário no fluxo único'
  where tipo like 'calendario_%' and status in ('pendente', 'erro');

create function app.gerar_avisos_por_horario() returns integer
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

create function app.escapar_html(p text) returns text language sql immutable as $$
  select replace(replace(replace(replace(coalesce(p, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;')
$$;

-- Monta assunto e corpo com os dados atuais da turma, no momento do envio.
create function app.montar_email(p_tipo text, p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  m modelos_email; t turmas; v_trein text; v_carga integer; v_ini time; v_hor text; v_part text; v_url text;
  v_assunto text; v_corpo text; c record; v_vars jsonb;
begin
  select * into m from modelos_email where tipo = p_tipo;
  select valor into v_url from parametros where chave = 'url_portal';
  if p_turma is not null then
    select * into t from turmas where id = p_turma;
    select nome, carga_minutos into v_trein, v_carga from treinamentos where id = t.treinamento_id;
    v_ini := t.hora_inicio;
    v_hor := case
      when t.hora_inicio is not null then to_char(t.hora_inicio, 'HH24:MI') || ' às ' || to_char(t.hora_inicio + make_interval(mins => v_carga), 'HH24:MI')
      when t.hora_opcao_1 is not null and t.hora_opcao_2 is not null then to_char(t.hora_opcao_1, 'HH24:MI') || ' ou ' || to_char(t.hora_opcao_2, 'HH24:MI')
      when t.hora_opcao_1 is not null then to_char(t.hora_opcao_1, 'HH24:MI')
      else 'A definir' end;
    select string_agg(concat_ws(' - ', cg.nome, co.nome), E'\n' order by co.nome) into v_part
    from turma_participantes p join colaboradores co on co.id = p.colaborador_id
    left join cargos cg on cg.id = coalesce(p.cargo_na_data_id, co.cargo_id)
    where p.turma_id = p_turma and p.situacao <> 'nao_aplicavel';
  end if;
  v_vars := jsonb_build_object(
    'treinamento', coalesce(v_trein, ''),
    'data', coalesce(to_char(t.data, 'DD/MM/YYYY'), 'A definir'),
    'horario', coalesce(v_hor, 'A definir'),
    'inicio', coalesce(to_char(coalesce(v_ini, t.hora_opcao_1), 'HH24:MI'), 'A definir'),
    'sala', coalesce(t.sala, 'A definir'),
    'participantes', coalesce(v_part, 'A definir'));
  v_assunto := m.assunto;
  v_corpo := app.escapar_html(m.corpo);
  for c in select * from jsonb_each_text(v_vars) loop
    v_assunto := replace(v_assunto, '{' || c.key || '}', c.value);
    v_corpo := replace(v_corpo, '{' || c.key || '}', app.escapar_html(c.value));
  end loop;
  v_assunto := regexp_replace(replace(v_assunto, '{link}', v_url), '[\r\n]+', ' ', 'g');
  v_corpo := replace(v_corpo, E'\n', '<br>');
  v_corpo := replace(v_corpo, '{link}', '<a href="' || app.escapar_html(v_url) || '" style="display:inline-block;background:#006666;color:#ffffff;padding:10px 18px;border-radius:6px;text-decoration:none;font-weight:600">Acessar o portal</a>');
  return jsonb_build_object('assunto', v_assunto, 'corpo_html', '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1d2f2c">' || v_corpo || '</div>');
end $$;

-- Único ponto de contato do n8n: gera o que venceu, descarta o que não vale e devolve os e-mails prontos.
create or replace function public.notificacoes_para_envio(p_limite integer default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  perform rotina_diaria();
  perform app.gerar_avisos_por_horario();
  update notificacoes n set status = 'cancelada', erro = 'Modelo de e-mail desligado'
    where n.status in ('pendente', 'erro') and not exists (select 1 from modelos_email m where m.tipo = n.tipo and m.ativo);
  update notificacoes n set status = 'cancelada', erro = 'O treinamento já começou'
    where n.tipo = 'lembrete_1h' and n.status in ('pendente', 'erro') and lower(app.periodo_turma(n.turma_id)) <= now();
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'destinatario', x.destinatario, 'tentativas', x.tentativas) || app.montar_email(x.tipo, x.turma_id)), '[]') into v
  from (
    select n.id, n.tipo, n.destinatario, n.turma_id, n.tentativas from notificacoes n
    where n.status = 'pendente' or (n.status = 'erro' and n.tentativas < 3)
    order by n.criado_em limit p_limite) x;
  return v;
end $$;

revoke all on function app.validar_parametro(), app.validar_modelo_email(), app.gerar_avisos_por_horario(), app.escapar_html(text), app.montar_email(text, uuid) from public, anon, authenticated;
revoke all on function public.notificacoes_para_envio(integer) from public, anon, authenticated;
grant execute on function public.notificacoes_para_envio(integer) to service_role;
revoke all on function app.notificar(text, uuid, text) from public, anon, authenticated;
