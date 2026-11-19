-- E-mail de acesso ao portal: substitui o link individual. Sai pela fila do n8n, com limite por rodada.

insert into public.parametros (chave, valor, rotulo, descricao, grupo, tipo, minimo, maximo, unidade, ordem) values
('acessos_por_rodada', '20', 'E-mails de acesso por rodada do n8n',
 'Quantos e-mails de acesso saem a cada rodada do n8n (a cada 10 minutos). Evita mandar tudo de uma vez no go-live. Os avisos de treinamento saem antes.',
 'E-mails', 'inteiro', 1, 30, 'e-mails', 40)
on conflict (chave) do nothing;

-- Campos próprios do e-mail de acesso.
create or replace function app.validar_modelo_email() returns trigger language plpgsql as $$
declare v_marca text; v_permitidas text[];
begin
  v_permitidas := case when new.tipo = 'acesso_portal'
    then array['{nome}', '{perfil}', '{email}', '{link}', '{o_que_voce_faz}']
    else array['{treinamento}', '{data}', '{horario}', '{inicio}', '{sala}', '{participantes}', '{link}'] end;
  for v_marca in select (regexp_matches(new.assunto || ' ' || new.corpo, '\{[^{}]*\}', 'g'))[1] loop
    if not v_marca = any (v_permitidas) then
      raise exception 'O campo % não existe. Use só os campos listados na tela.', v_marca using errcode = '22023';
    end if;
  end loop;
  new.atualizado_em := now();
  return new;
end $$;

insert into public.modelos_email (tipo, nome, quando, para, ordem, assunto, corpo) values
('acesso_portal', 'Acesso ao portal', 'Quando Gente e Gestão clica em Enviar e-mail de acesso, em Acessos', 'Pessoa cadastrada', 5,
 'Seu acesso ao Portal de Treinamentos Emais',
 E'Olá, {nome}.\n\nVocê foi cadastrado no Portal de Treinamentos da Emais com o perfil {perfil}.\n\n{o_que_voce_faz}\n\nComo criar a sua senha (primeiro acesso)\n1. Acesse o portal: {link}\n2. Clique em "Primeiro acesso ou esqueci a senha".\n3. Digite o seu e-mail: {email}\n4. Você vai receber em instantes um e-mail com um código de acesso. Se não aparecer, confira a caixa de spam.\n5. Digite o código no portal e crie a sua senha, com pelo menos 8 caracteres.\n\nPronto. Nos próximos acessos, entre com o seu e-mail e a senha criada. Se esquecer a senha, é só repetir os passos acima.\n\nEm caso de dúvida, fale com Gente e Gestão.\n\nAtenciosamente,\nGente e Gestão')
on conflict (tipo) do nothing;

create function app.montar_email_acesso(p_email text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m modelos_email; u usuarios; v_url text; v_perfil text; v_faz text; v_assunto text; v_corpo text; c record;
begin
  select * into m from modelos_email where tipo = 'acesso_portal';
  select * into u from usuarios where lower(email) = lower(p_email);
  select valor into v_url from parametros where chave = 'url_portal';
  v_perfil := case
    when u.perfil = 'colaborador' then 'Colaborador'
    when u.perfil = 'instrutor' then 'Instrutor'
    when u.perfil = 'gestor' then 'Gestor / Instrutor'
    when u.perfil = 'admin' and u.tambem_instrutor then 'Gente e Gestão / Instrutor'
    else 'Gente e Gestão' end;
  v_faz := case
    when u.perfil = 'colaborador' then 'No portal, você acompanha o seu calendário de treinamentos, responde às avaliações de satisfação e assina a sua lista de presença.'
    when u.perfil = 'instrutor' then 'No portal, você confirma a agenda dos treinamentos que aplica, registra a presença dos participantes e acompanha o seu calendário.'
    when u.perfil = 'gestor' then 'No portal, você acompanha os treinamentos da sua equipe e, quando for instrutor, confirma a agenda e registra a presença das turmas que aplica.'
    when u.perfil = 'admin' and u.tambem_instrutor then 'No portal, você planeja e acompanha todos os treinamentos e, quando for instrutor, confirma a agenda e registra a presença das turmas que aplica.'
    else 'No portal, você planeja e acompanha todos os treinamentos, os cadastros e os acessos.' end;
  v_assunto := m.assunto;
  v_corpo := app.escapar_html(m.corpo);
  for c in select * from jsonb_each_text(jsonb_build_object('nome', split_part(coalesce(u.nome, ''), ' ', 1), 'perfil', v_perfil, 'email', lower(p_email), 'o_que_voce_faz', v_faz)) loop
    v_assunto := replace(v_assunto, '{' || c.key || '}', c.value);
    v_corpo := replace(v_corpo, '{' || c.key || '}', app.escapar_html(c.value));
  end loop;
  v_assunto := regexp_replace(replace(v_assunto, '{link}', coalesce(v_url, '')), '[\r\n]+', ' ', 'g');
  v_corpo := replace(v_corpo, E'\n', '<br>');
  v_corpo := replace(v_corpo, '{link}', '<a href="' || app.escapar_html(coalesce(v_url, '')) || '" style="color:#006666;font-weight:600">' || app.escapar_html(coalesce(v_url, '')) || '</a>');
  return jsonb_build_object('assunto', v_assunto, 'corpo_html', '<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.5;color:#1d2f2c">' || v_corpo || '</div>');
end $$;

-- Gente e Gestão coloca na fila. Quem já tem e-mail de acesso aguardando envio não ganha outro.
create function public.enviar_email_acesso(p_usuarios uuid[]) returns integer
language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  perform app.exigir_admin();
  if not exists (select 1 from modelos_email where tipo = 'acesso_portal' and ativo) then raise exception 'O modelo "Acesso ao portal" está desligado em Acessos > E-mails'; end if;
  insert into notificacoes (tipo, destinatario)
  select 'acesso_portal', lower(u.email) from usuarios u
  where u.id = any (p_usuarios) and u.ativo
    and not exists (select 1 from notificacoes n where n.tipo = 'acesso_portal' and n.destinatario = lower(u.email) and n.status in ('pendente', 'erro'));
  get diagnostics v = row_count;
  return v;
end $$;

-- Último e-mail de acesso de cada pessoa, para a lista de Acessos.
create function public.emails_acesso_enviados() returns table (email text, situacao text, quando timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  return query select distinct on (n.destinatario) n.destinatario, n.status::text, coalesce(n.enviado_em, n.criado_em)
    from notificacoes n where n.tipo = 'acesso_portal' order by n.destinatario, n.criado_em desc;
end $$;

-- Fila do n8n: avisos de treinamento primeiro; e-mails de acesso limitados por rodada.
create or replace function public.notificacoes_para_envio(p_limite integer default 50) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v jsonb; v_acessos integer := coalesce(app.param_int('acessos_por_rodada'), 20);
begin
  perform rotina_diaria();
  perform app.gerar_avisos_por_horario();
  update notificacoes n set status = 'cancelada', erro = 'Modelo de e-mail desligado'
    where n.status in ('pendente', 'erro') and not exists (select 1 from modelos_email m where m.tipo = n.tipo and m.ativo);
  update notificacoes n set status = 'cancelada', erro = 'O treinamento já começou'
    where n.tipo in ('lembrete_1h', 'lembrete_1h_colaborador', 'convocacao_colaborador', 'alteracao_colaborador') and n.status in ('pendente', 'erro') and lower(app.periodo_turma(n.turma_id)) <= now();
  update notificacoes n set status = 'cancelada', erro = 'Acesso desativado antes do envio'
    where n.tipo = 'acesso_portal' and n.status in ('pendente', 'erro') and not exists (select 1 from usuarios u where lower(u.email) = n.destinatario and u.ativo);
  with fila as (
    select n.id, n.tipo, n.destinatario, n.turma_id, n.tentativas, n.criado_em,
           row_number() over (partition by n.tipo = 'acesso_portal' order by n.criado_em) as pos
    from notificacoes n where n.status = 'pendente' or (n.status = 'erro' and n.tentativas < 3)
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'tipo', x.tipo, 'destinatario', x.destinatario, 'tentativas', x.tentativas)
           || case when x.tipo = 'acesso_portal' then app.montar_email_acesso(x.destinatario) else app.montar_email(x.tipo, x.turma_id) end), '[]') into v
  from (
    select * from (
      select f.*, 0 as grupo from fila f where f.tipo <> 'acesso_portal'
      union all
      select f.*, 1 from fila f where f.tipo = 'acesso_portal' and f.pos <= v_acessos
    ) y order by y.grupo, y.criado_em limit p_limite) x;
  return v;
end $$;

revoke all on function public.enviar_email_acesso(uuid[]), public.emails_acesso_enviados() from public, anon;
grant execute on function public.enviar_email_acesso(uuid[]), public.emails_acesso_enviados() to authenticated;
revoke all on function app.montar_email_acesso(text) from public, anon, authenticated;
revoke all on function public.notificacoes_para_envio(integer) from public, anon, authenticated;
grant execute on function public.notificacoes_para_envio(integer) to service_role;
