-- Cenário do ciclo completo, com cada perfil. Rodar num Postgres local: resultado esperado = só linhas "ok".
\set ON_ERROR_STOP on
create schema teste;
create function teste.como(p_email text) returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', coalesce((select id::text from public.usuarios where email = p_email), ''), false);
  if p_email is null then execute 'set role anon'; else execute 'set role authenticated'; end if;
end $$;
create function teste.ok(p_nome text, p_cond boolean) returns void language plpgsql as $$
begin
  raise notice '% %', case when p_cond then 'ok  ' else 'FALHOU' end, p_nome;
end $$;
create function teste.falha(p_nome text, p_sql text) returns void language plpgsql as $$
begin
  begin execute p_sql; raise notice 'FALHOU % (deveria recusar)', p_nome;
  exception when others then raise notice 'ok   % -> %', p_nome, sqlerrm; end;
end $$;
grant execute on all functions in schema teste to anon, authenticated;
grant usage on schema teste to anon, authenticated;

do $$
declare u record; i uuid;
begin
  for u in select * from (values ('gestao.teste@example.com','admin','Gabriela Teste'),('seguranca.teste@example.com','instrutor','Sara Teste'),
    ('instrutor.teste@example.com','colaborador','Igor Teste Instrutor'),('gestor.teste@example.com','gestor','Gustavo Teste Gestor'),('colaborador.teste@example.com','colaborador','Clara Teste'),('outro.instrutor@example.com','instrutor',null)) x(email,perfil,nome) loop
    i := gen_random_uuid();
    insert into auth.users values (i, u.email);
    insert into public.usuarios (id, nome, email, perfil, colaborador_id) values (i, coalesce(u.nome,'Outro'), u.email, u.perfil::perfil_usuario, (select id from colaboradores where nome = u.nome));
  end loop;
  insert into usuarios_departamentos select id, (select id from departamentos where nome = 'CONTROLADORIA') from usuarios where email = 'gestor.teste@example.com';
end $$;

create table public.ctx (k text primary key, v uuid); grant all on public.ctx to authenticated, anon;
alter table public.ctx enable row level security; create policy tudo on public.ctx using (true) with check (true);

-- Acessos
select teste.como(null);
select teste.falha('anon não lê colaboradores', 'select 1 from public.colaboradores');
select teste.falha('anon não chama funções', 'select public.listar_turmas()');
select teste.como('colaborador.teste@example.com');
select teste.ok('colaborador só se vê', (select count(*) from colaboradores) = 1);
select teste.falha('colaborador não cria turma', $q$select criar_turma((select id from treinamentos limit 1),'normal',current_date+5,'09:00',null,'a@b.c',array[(select id from cargos limit 1)])$q$);
select teste.falha('colaborador não grava presença direto', $q$update turma_participantes set situacao='presente'$q$);
select teste.ok('painel do colaborador só com ele', (select count(*) from painel_colaboradores()) = 1);
select teste.como('gestor.teste@example.com');
select teste.ok('gestor vê só a área e si', (select count(*) from colaboradores) = (select count(*) from painel_colaboradores()) and (select count(distinct departamento) from painel_colaboradores()) = 1);
select teste.falha('gestor não lê fila', 'select fila_inicio()');
select teste.como('seguranca.teste@example.com');
select teste.ok('técnico de segurança entra como instrutor e só se vê', (select count(*) from colaboradores) = 1);
select teste.falha('instrutor não formaliza', $q$select formalizar_turma(gen_random_uuid())$q$);

-- Ciclo. Cargo sem elegível não vira linha.
select teste.como('gestao.teste@example.com');
select teste.ok('a planejar tem pendências', (select count(*) from a_planejar()) > 0);
insert into ctx values ('c_jr',(select id from cargos where nome like '%JUNIOR')),('c_en',(select id from cargos where nome='ENGENHEIRO DE OBRAS')),('c_se',(select id from cargos where nome='TÉCNICO DE SEGURANÇA'));
select teste.ok('planejar consolida o treinamento nos cargos escolhidos', (select jsonb_array_length(cargos) from planejar_treinamentos(array[(select v from ctx where k='c_jr'),(select v from ctx where k='c_en')]) where treinamento='Código de Ética') = 2);
select teste.ok('planejar sem cargo não traz treinamento normal', not exists (select 1 from planejar_treinamentos('{}') where tipo <> 'reciclagem'));
select teste.falha('envio sem data é recusado', $q$select enviar_planejamento('[{"treinamento_id":"00000000-0000-0000-0000-000000000000","cargos":[],"data":"","hora_1":"09:00","email":"a@b.c"}]')$q$);
select teste.falha('envio é tudo ou nada', format($q$select enviar_planejamento('[{"treinamento_id":"%s","cargos":["%s"],"data":"2031-01-10","hora_1":"09:00","email":"a@b.c"},{"treinamento_id":"%s","cargos":["%s"],"data":"","hora_1":"09:00","email":"a@b.c"}]')$q$, (select id from treinamentos where nome='LGPD no dia a dia'), (select v from ctx where k='c_jr'), (select id from treinamentos where nome='LGPD no dia a dia'), (select v from ctx where k='c_jr')));
select teste.ok('tudo ou nada não deixa turma', not exists (select 1 from turmas where data='2031-01-10'));
insert into ctx select 't1', criar_turma((select id from treinamentos where nome='Código de Ética'),'admissao',current_date+5,'09:00','14:00','INSTRUTOR.TESTE@example.com',
  array[(select v from ctx where k='c_jr'),(select v from ctx where k='c_en'),(select id from cargos where nome='CONSULTOR DE VENDAS'),(select id from cargos where nome='ANALISTA GENTE E GESTÃO')]);
select teste.ok('mesmo treinamento aberto consolida, sem turma nova', criar_turma((select id from treinamentos where nome='Código de Ética'),'admissao',current_date+5,'09:00','14:00','instrutor.teste@example.com',array[(select v from ctx where k='c_jr')]) = (select v from ctx where k='t1'));
select teste.ok('só elegíveis na janela (Bruna, 90 dias, e Gabriela ficam fora)', (select jsonb_agg(p->>'nome' order by p->>'nome') from jsonb_array_elements(turma_detalhe((select v from ctx where k='t1'))->'participantes') p) = '["Caio Teste", "Clara Teste", "Eduardo Teste", "Vera Teste"]');
select teste.ok('cargo sem elegível aparece com zero, sem linha de participante', (select (c->>'elegiveis')::int from jsonb_array_elements(turma_detalhe((select v from ctx where k='t1'))->'cargos') c where c->>'nome'='ANALISTA GENTE E GESTÃO') = 0);
select teste.ok('aviso único na fila', (select count(*) from notificacoes where turma_id=(select v from ctx where k='t1')) = 1);
select teste.falha('não formaliza sem aceite do instrutor', $q$select formalizar_turma((select v from ctx where k='t1'))$q$);
select teste.como('outro.instrutor@example.com');
select teste.falha('outro instrutor não responde', $q$select responder_agenda((select v from ctx where k='t1'),'aceitar','09:00')$q$);
select teste.ok('outro instrutor não vê a turma', (select count(*) from minhas_turmas()) = 0);
select teste.como('instrutor.teste@example.com');
select teste.falha('horário fora das opções recusado', $q$select responder_agenda((select v from ctx where k='t1'),'aceitar','10:00')$q$);
select responder_agenda((select v from ctx where k='t1'),'aceitar','14:00');
select teste.falha('segundo clique recusado com aviso claro', $q$select responder_agenda((select v from ctx where k='t1'),'recusar',null,null,'x')$q$);
select teste.como('gestao.teste@example.com');
select teste.falha('não formaliza sem sala', $q$select formalizar_turma((select v from ctx where k='t1'))$q$);
select definir_sala((select v from ctx where k='t1'),'Time Forte');
select formalizar_turma((select v from ctx where k='t1'));
insert into ctx select 'dup', criar_turma((select id from treinamentos where nome='Código de Ética'),'admissao',current_date+40,'09:00',null,'instrutor.teste@example.com',array[(select v from ctx where k='c_jr')]);
select teste.ok('quem já está em turma aberta do treinamento não é convocado de novo', not exists (select 1 from turma_participantes where turma_id=(select v from ctx where k='dup') and situacao='convocado' and colaborador_id in (select colaborador_id from turma_participantes where turma_id=(select v from ctx where k='t1'))));
select cancelar_turma((select v from ctx where k='dup'),'Teste');
select teste.ok('convite do Outlook sai do portal: nenhum e-mail de calendário', not exists (select 1 from notificacoes where tipo like 'calendario_%'));
select teste.falha('presença só abre no horário', $q$select marcar_presenca((select v from ctx where k='t1'),(select id from colaboradores where nome='Clara Teste'),'presente')$q$);

-- Alteração depois do convite: mesma turma, evento atualizado.
select teste.como('instrutor.teste@example.com');
select solicitar_alteracao((select v from ctx where k='t1'),'alteracao','Viagem no dia','{"data":"2031-05-05","hora":"10:00"}');
select teste.falha('só uma solicitação aberta', $q$select solicitar_alteracao((select v from ctx where k='t1'),'alteracao','Outra')$q$);
select teste.como('gestao.teste@example.com');
select decidir_solicitacao((select id from turma_solicitacoes where turma_id=(select v from ctx where k='t1')),true,'Ok');
select teste.ok('mesma turma com nova data', (select data='2031-05-05' and hora_inicio='10:00' and status='convite_enviado' from turmas where id=(select v from ctx where k='t1')));
select teste.ok('alteração avisa o instrutor', exists (select 1 from notificacoes where tipo='aviso_decisao' and turma_id=(select v from ctx where k='t1')));

-- Pessoa admitida depois do convite entra sozinha; saiu, sai.
select salvar_colaborador(null,'Nova Teste',null,(select v from ctx where k='c_jr'),current_date);
select teste.ok('admitida depois do convite entra na lista', exists (select 1 from jsonb_array_elements(turma_detalhe((select v from ctx where k='t1'))->'participantes') p where p->>'nome'='Nova Teste'));
select salvar_colaborador((select id from colaboradores where nome='Nova Teste'),'Nova Teste',null,(select v from ctx where k='c_jr'),null,false);
select teste.ok('inativada sai da lista', not exists (select 1 from jsonb_array_elements(turma_detalhe((select v from ctx where k='t1'))->'participantes') p where p->>'nome'='Nova Teste'));

-- Presença: dois do mesmo cargo, com correção. Hoje esse caso se perde.
insert into ctx select 'p_'||split_part(nome,' ',1), id from colaboradores where nome in ('Aline Teste','Antonio Teste','Vera Teste');
select teste.como('instrutor.teste@example.com');
insert into ctx values ('t2',(select id from turmas where status='convite_enviado' and data < current_date));
select marcar_presenca((select v from ctx where k='t2'),(select v from ctx where k='p_Aline'),'ausente');
select marcar_presenca((select v from ctx where k='t2'),(select v from ctx where k='p_Aline'),'presente');
select marcar_presenca((select v from ctx where k='t2'),(select v from ctx where k='p_Antonio'),'ausente');
select teste.falha('não conclui com pessoa sem marcar', $q$select concluir_presenca((select v from ctx where k='t2'))$q$);
select marcar_presenca((select v from ctx where k='t2'),(select v from ctx where k='p_Vera'),'presente');
select concluir_presenca((select v from ctx where k='t2'));
select teste.ok('correção e segundo do mesmo cargo gravados', (select count(*) from turma_participantes where turma_id=(select v from ctx where k='t2') and situacao='presente') = 2 and (select count(*) from turma_participantes where turma_id=(select v from ctx where k='t2') and situacao='ausente') = 1);
select teste.falha('depois de concluir, instrutor não altera', $q$select marcar_presenca((select v from ctx where k='t2'),(select v from ctx where k='p_Vera'),'ausente')$q$);
select teste.como('gestao.teste@example.com');
select teste.ok('turma realizada', (select status='realizada' from turmas where id=(select v from ctx where k='t2')));
select teste.ok('ausente volta para a planejar', exists (select 1 from a_planejar() p, jsonb_array_elements(p.pessoas) x where x->>'nome'='Antonio Teste' and p.treinamento like 'Política%'));

-- Cancelar: nada pendente continua.
select cancelar_turma((select v from ctx where k='t1'),'Teste');
select teste.ok('notificações pendentes canceladas', not exists (select 1 from notificacoes where turma_id=(select v from ctx where k='t1') and status='pendente' and tipo='calendario_atualizar'));
select teste.ok('cancelamento avisa o instrutor', exists (select 1 from notificacoes where turma_id=(select v from ctx where k='t1') and status='pendente' and tipo='aviso_cancelamento'));

-- Matriz
insert into ctx select 'tr', id from treinamentos where nome='LGPD no dia a dia';
select teste.falha('matriz travada sem revisão', $q$select alternar_vinculo((select v from ctx where k='c_jr'),(select v from ctx where k='tr'),false)$q$);
select iniciar_revisao('Revisão de teste da matriz');
select alternar_vinculo((select v from ctx where k='c_jr'),(select v from ctx where k='tr'),false);
select teste.ok('remoção em revisão aberta não altera o vigente', exists (select 1 from matriz_vigente_em((select v from ctx where k='c_jr'),current_date) m where m.treinamento_id=(select v from ctx where k='tr')));
select cancelar_revisao();
select teste.ok('cancelar restaura', exists (select 1 from matriz_vinculos where cargo_id=(select v from ctx where k='c_jr') and treinamento_id=(select v from ctx where k='tr') and revisao_remocao_id is null));
select iniciar_revisao('Revisão de teste da matriz 2');
select alternar_vinculo((select v from ctx where k='c_jr'),(select v from ctx where k='tr'),false);
select publicar_revisao(current_date + 10);
select teste.ok('publicada vale só a partir da vigência', exists (select 1 from matriz_vigente_em((select v from ctx where k='c_jr'),current_date+9) m where m.treinamento_id=(select v from ctx where k='tr')) and not exists (select 1 from matriz_vigente_em((select v from ctx where k='c_jr'),current_date+10) m where m.treinamento_id=(select v from ctx where k='tr')));

-- Reciclagem
select teste.ok('promovida entra na fila', exists (select 1 from movimentacoes_pendentes() where nome='Paula Teste' and decisao is null));
select teste.ok('sugestão da promoção', (sugerir_reciclagem((select id from colaboradores where nome='Paula Teste'),'promocao_vertical')->>'acao_sugerida') = 'parcial');
select confirmar_reciclagem((select id from colaboradores where nome='Paula Teste'),'promocao_vertical','dispensa');
select teste.ok('dispensa zera pendências', (select pendentes from painel_colaboradores() where nome='Paula Teste') = 0 and (select not classificar from painel_colaboradores() where nome='Paula Teste'));
select teste.ok('painel e fila respondem', (select count(*) from fila_inicio()) >= 0 and (indicadores()->>'colaboradores')::int > 0);

-- Código único e avaliação confidencial
select teste.ok('presença gera código único por pessoa', (select count(distinct codigo_presenca) = count(*) and count(*) > 0 from turma_participantes where situacao='presente'));
select teste.ok('ausente fica sem código', not exists (select 1 from turma_participantes where situacao <> 'presente' and codigo_presenca is not null));
select teste.ok('resposta não tem coluna de pessoa nem data', not exists (select 1 from information_schema.columns where table_name='avaliacao_respostas' and (column_name like '%colaborador%' or data_type like 'timestamp%' or column_name like '%usuario%')));

-- Assinatura eletrônica
select teste.falha('lista não vai para assinatura com treinamento em aberto', $q$select solicitar_assinatura((select id from colaboradores where nome='Clara Teste'),'lista_presenca')$q$);
select teste.falha('termo exige dispensa', $q$select solicitar_assinatura((select id from colaboradores where nome='Clara Teste'),'termo_dispensa')$q$);
insert into ctx select 'doc', (solicitar_assinatura((select id from colaboradores where nome='Paula Teste'),'termo_dispensa')->>'id')::uuid;
select teste.falha('não envia o mesmo termo duas vezes', $q$select solicitar_assinatura((select id from colaboradores where nome='Paula Teste'),'termo_dispensa')$q$);
reset role;
insert into auth.users select gen_random_uuid(), 'paula.login@example.com';
insert into usuarios (id, nome, email, perfil, colaborador_id) select u.id, 'Paula Teste', u.email, 'colaborador', (select id from colaboradores where nome='Paula Teste') from auth.users u where u.email='paula.login@example.com';
select teste.como('colaborador.teste@example.com');
select teste.falha('outra pessoa não assina', $q$select assinar_documento((select v from ctx where k='doc'),'data:image/png;base64,AAAA')$q$);
select teste.falha('outra pessoa não abre o documento', $q$select documento_assinatura((select v from ctx where k='doc'))$q$);
select teste.como('paula.login@example.com');
select teste.falha('assinatura inválida é recusada', $q$select assinar_documento((select v from ctx where k='doc'),'qualquer coisa')$q$);
select assinar_documento((select v from ctx where k='doc'),'data:image/png;base64,AAAA');
select teste.falha('não assina duas vezes', $q$select assinar_documento((select v from ctx where k='doc'),'data:image/png;base64,AAAA')$q$);
reset role;
select teste.ok('assinatura guarda data, nome e e-mail', (select assinado_em is not null and assinatura_nome='Paula Teste' and assinatura_email='paula.login@example.com' and length(hash)=64 from documentos_assinatura where id=(select v from ctx where k='doc')));
select teste.ok('Gente e Gestão recebe o aviso', exists (select 1 from notificacoes where tipo='assinatura_concluida'));
select teste.falha('documento assinado não muda', $q$update documentos_assinatura set conteudo='{}' where id=(select v from ctx where k='doc')$q$);
select teste.falha('documento assinado não é apagado', $q$delete from documentos_assinatura where id=(select v from ctx where k='doc')$q$);
select teste.como('gestao.teste@example.com');
select teste.ok('assinado aparece na fila', exists (select 1 from fila_inicio() where grupo='assinatura'));
select marcar_documento_baixado((select v from ctx where k='doc'));
select teste.ok('baixado sai da fila', not exists (select 1 from fila_inicio() where grupo='assinatura'));
reset role;
insert into turma_participantes (turma_id, colaborador_id, situacao, cargo_na_data_id)
select (select v from ctx where k='t2'), id, 'presente', cargo_id from colaboradores where nome='Vera Teste' on conflict (turma_id, colaborador_id) do update set situacao='presente';
delete from matriz_vinculos v where v.cargo_id=(select cargo_id from colaboradores where nome='Vera Teste') and v.treinamento_id not in (select t.treinamento_id from turmas t where t.id=(select v from ctx where k='t2'));
select app.solicitar_lista_se_concluida(id) from colaboradores where nome='Vera Teste';
select teste.ok('grade concluída vai sozinha para assinatura', exists (select 1 from documentos_assinatura d join colaboradores c on c.id=d.colaborador_id where c.nome='Vera Teste' and d.tipo='lista_presenca' and d.status='pendente'));
select app.solicitar_lista_se_concluida(id) from colaboradores where nome='Vera Teste';
select teste.ok('não repete a mesma lista', (select count(*) from documentos_assinatura d join colaboradores c on c.id=d.colaborador_id where c.nome='Vera Teste' and d.tipo='lista_presenca') = 1);
select teste.como('gestao.teste@example.com');

-- Avaliação de Eficácia
reset role;
insert into cargos (nome, departamento_id) select 'CARGO EFICACIA', id from departamentos where nome='COMERCIAL';
insert into matriz_vinculos (cargo_id, treinamento_id, revisao_criacao_id) select (select id from cargos where nome='CARGO EFICACIA'), (select id from treinamentos where nome='Código de Ética'), (select id from matriz_revisoes where numero='REV-INICIAL');
insert into colaboradores (nome, cargo_id, departamento_id, data_admissao) select n, (select id from cargos where nome='CARGO EFICACIA'), (select id from departamentos where nome='COMERCIAL'), case n when 'Erica Teste' then current_date - 120 when 'Breno Teste' then current_date - 10 else date '2020-03-01' end from unnest(array['Erica Teste','Breno Teste','Olavo Teste']) n;
insert into turmas (treinamento_id, status, data, hora_inicio, hora_opcao_1, sala, instrutor_email, presenca_concluida_em) select (select id from treinamentos where nome='Código de Ética'), 'realizada', d, '09:00', '09:00', 'Time Forte', 'instrutor.teste@example.com', now() from unnest(array[current_date - 120, current_date - 10]) d;
insert into turma_participantes (turma_id, colaborador_id, situacao, cargo_na_data_id) select t.id, c.id, 'presente', c.cargo_id from colaboradores c join turmas t on t.data = case c.nome when 'Erica Teste' then current_date - 120 else current_date - 10 end and t.status = 'realizada' and t.sala = 'Time Forte' and t.hora_inicio = '09:00' and t.treinamento_id = (select id from treinamentos where nome='Código de Ética') where c.nome in ('Erica Teste','Breno Teste');
insert into turma_participantes (turma_id, colaborador_id, situacao, cargo_na_data_id) select p.turma_id, c.id, 'presente', c.cargo_id from turma_participantes p join colaboradores e on e.id = p.colaborador_id and e.nome = 'Erica Teste', colaboradores c where c.nome = 'Olavo Teste';
select teste.como('colaborador.teste@example.com');
select teste.falha('colaborador não vê a eficácia', $q$select * from eficacia_painel()$q$);
select teste.como('gestao.teste@example.com');
select teste.ok('passou de 90 dias fica a avaliar', (select situacao='a_avaliar' from eficacia_painel() where nome='Erica Teste'));
select teste.ok('antes de 90 dias fica aguardando', (select situacao='aguardando' from eficacia_painel() where nome='Breno Teste'));
select teste.ok('a avaliar aparece no Dashboard', exists (select 1 from fila_inicio() where grupo='eficacia' and titulo like 'Erica%'));
select teste.falha('não avalia antes de 90 dias', $q$select salvar_eficacia((select id from colaboradores where nome='Breno Teste'), current_date, 'Avaliador', 'eficaz')$q$);
select teste.falha('resultado parcial exige observação', $q$select salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date, 'Avaliador', 'parcial')$q$);
select teste.falha('data futura é recusada', $q$select salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date + 1, 'Avaliador', 'eficaz')$q$);
insert into ctx select 'ef', salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date, 'Avaliador Teste', 'eficaz');
select teste.ok('avaliada sai do Dashboard', not exists (select 1 from fila_inicio() where grupo='eficacia' and titulo like 'Erica%'));
select teste.ok('avaliada aparece uma vez', (select count(*)=1 and bool_and(situacao='avaliada') from eficacia_painel() where nome='Erica Teste'));
select teste.falha('não avalia o mesmo colaborador duas vezes', $q$select salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date, 'Avaliador', 'eficaz')$q$);
select salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date, 'Avaliador Teste', 'parcial', 'Precisa reforço', (select v from ctx where k='ef'));
select teste.ok('correção fica registrada', (eficacia_documento((select v from ctx where k='ef'))->>'resultado')='parcial');
select teste.ok('admissão antiga não entra', not exists (select 1 from eficacia_painel() where nome='Olavo Teste'));
reset role;
insert into turma_participantes (turma_id, colaborador_id, situacao, cargo_na_data_id) select t.id, c.id, 'presente', c.cargo_id from turmas t, colaboradores c where c.nome='Erica Teste' and t.status='realizada' and t.id not in (select turma_id from turma_participantes where colaborador_id=c.id) limit 1;
select teste.como('gestao.teste@example.com');
select teste.ok('treinamento novo, como reciclagem, não abre outra avaliação', (select count(*)=1 and bool_and(situacao='avaliada') from eficacia_painel() where nome='Erica Teste'));
select teste.ok('quem foi dispensado não entra', not exists (select 1 from eficacia_painel() where nome='Paula Teste'));
reset role;

-- Regras editáveis e fluxo único de e-mails
select teste.ok('nada de e-mail de calendário na fila', not exists (select 1 from notificacoes where tipo like 'calendario_%' and status in ('pendente','erro')));
select teste.como('gestao.teste@example.com');
update parametros set valor='20' where chave='janela_convocacao_dias';
select teste.ok('Gente e Gestão altera a janela', app.param_int('janela_convocacao_dias')=20);
update parametros set valor='15' where chave='janela_convocacao_dias';
select teste.falha('regra fora do limite', $q$update parametros set valor='0' where chave='janela_convocacao_dias'$q$);
select teste.falha('regra que não é número', $q$update parametros set valor='abc' where chave='prazo_eficacia_dias'$q$);
select teste.falha('data inválida', $q$update parametros set valor='31/31/2026' where chave='eficacia_admissao_desde'$q$);
select teste.falha('modelo com campo inexistente', $q$update modelos_email set corpo='Oi {nome}' where tipo='lembrete_1h'$q$);
update modelos_email set assunto='Lembrete de {treinamento} às {inicio}' where tipo='lembrete_1h';
select teste.como('instrutor.teste@example.com');
select teste.ok('instrutor não lê modelos', not exists (select 1 from modelos_email));
select teste.falha('instrutor não altera regras', $q$do $x$ begin update parametros set valor='20' where chave='janela_convocacao_dias'; if not found then raise exception 'sem efeito'; end if; end $x$$q$);
select teste.falha('logado não busca a fila', $q$select notificacoes_para_envio()$q$);
reset role;
create temp table f as select now() as a;
do $x$
declare v_t uuid; v_e jsonb; v_n integer; v_i text := 'instrutor.teste@example.com';
begin
  select t.id into v_t from turmas t where t.status = 'convite_enviado' limit 1;
  if v_t is null then
    insert into turmas (treinamento_id, status, data, hora_inicio, sala, instrutor_email) select id, 'convite_enviado', current_date, '09:00', 'Time <Forte>', v_i from treinamentos limit 1 returning id into v_t;
    insert into turma_participantes (turma_id, colaborador_id) select v_t, id from colaboradores where ativo limit 2;
  end if;
  -- começa daqui a 30 minutos
  update turmas set instrutor_email = v_i, sala = 'Time <Forte>', presenca_concluida_em = null, data = (now() at time zone 'America/Sao_Paulo')::date, hora_inicio = ((now() + interval '30 minutes') at time zone 'America/Sao_Paulo')::time where id = v_t;
  v_e := notificacoes_para_envio(500);
  select count(*) into v_n from notificacoes where tipo = 'lembrete_1h' and turma_id = v_t;
  perform teste.ok('lembrete sai antes do início', v_n = 1);
  perform notificacoes_para_envio(500);
  select count(*) into v_n from notificacoes where tipo = 'lembrete_1h' and turma_id = v_t;
  perform teste.ok('lembrete não repete', v_n = 1);
  select x into v_e from jsonb_array_elements(notificacoes_para_envio(500)) x where x->>'tipo' = 'lembrete_1h' limit 1;
  perform teste.ok('e-mail traz treinamento no assunto', v_e->>'assunto' like 'Lembrete de % às %');
  perform teste.ok('e-mail traz participantes', exists (select 1 from turma_participantes p join colaboradores c on c.id = p.colaborador_id where p.turma_id = v_t and v_e->>'corpo_html' like '%' || c.nome || '%'));
  perform teste.ok('e-mail protege o HTML', v_e->>'corpo_html' like '%Time &lt;Forte&gt;%');
  perform registrar_envio((v_e->>'id')::uuid, true);
  -- muda o horário: novo lembrete
  update turmas set hora_inicio = ((now() + interval '45 minutes') at time zone 'America/Sao_Paulo')::time where id = v_t;
  perform notificacoes_para_envio(500);
  select count(*) into v_n from notificacoes where tipo = 'lembrete_1h' and turma_id = v_t;
  perform teste.ok('novo horário gera novo lembrete', v_n = 2);
  -- terminou faz 5 minutos: aviso de presença com o mesmo cuidado de não repetir
  update turmas set hora_inicio = ((now() - interval '5 minutes') at time zone 'America/Sao_Paulo')::time - make_interval(mins => (select carga_minutos from treinamentos where id = treinamento_id)) where id = v_t;
  perform notificacoes_para_envio(500);
  perform notificacoes_para_envio(500);
  select count(*) into v_n from notificacoes where tipo = 'aviso_presenca' and turma_id = v_t;
  perform teste.ok('aviso de presença depois do fim, sem repetir', v_n = 1);
  perform teste.ok('lembrete vencido é descartado', not exists (select 1 from notificacoes where tipo = 'lembrete_1h' and turma_id = v_t and status = 'pendente'));
  -- modelo desligado não envia
  update modelos_email set ativo = false where tipo = 'aviso_presenca';
  perform notificacoes_para_envio(500);
  perform teste.ok('modelo desligado cancela o aviso', not exists (select 1 from notificacoes where tipo = 'aviso_presenca' and turma_id = v_t and status = 'pendente'));
  update modelos_email set ativo = true where tipo = 'aviso_presenca';
end $x$;

-- Instrutor remarca direto, com travas
do $x$
declare v_t uuid; v_o uuid; v_tr uuid; v_c uuid; v jsonb; v_d date := current_date + 5; v_e text := 'instrutor.teste@example.com'; v_n int; v_ref date;
begin
  execute 'reset role';
  select id into v_c from colaboradores where ativo limit 1;
  update colaboradores set data_admissao = current_date where id = v_c;
  delete from movimentacoes where colaborador_id = v_c;
  select id into v_tr from treinamentos where ativo limit 1;
  insert into turmas (treinamento_id, status, data, hora_inicio, hora_opcao_1, sala, instrutor_email) values (v_tr, 'agenda_confirmada', v_d, '09:00', '09:00', 'Externo', v_e) returning id into v_t;
  insert into turma_participantes (turma_id, colaborador_id, origem) values (v_t, v_c, 'manual');
  -- a mesma pessoa em outra turma às 14:00, de outro instrutor
  insert into turmas (treinamento_id, status, data, hora_inicio, sala, instrutor_email) select id, 'convite_enviado', v_d, '14:00', 'Externo', 'outro@example.com' from treinamentos where id <> v_tr limit 1 returning id into v_o;
  insert into turma_participantes (turma_id, colaborador_id) values (v_o, v_c);
  perform teste.como(v_e);
  v := verificar_novo_horario(v_t, v_d, '14:00');
  perform teste.ok('mostra colaborador indisponível', not (v->>'ok')::boolean and jsonb_array_length(v->'indisponiveis') = 1 and v->'indisponiveis'->0->>'nome' is not null);
  v := verificar_novo_horario(v_t, v_d, '11:00');
  perform teste.ok('horário livre passa', (v->>'ok')::boolean);
  perform teste.ok('limite é a admissão mais a janela', (v->>'limite')::date = current_date + 15);
  v := verificar_novo_horario(v_t, current_date - 1, '11:00');
  perform teste.ok('data antes da admissão é barrada', not (v->>'ok')::boolean and v->>'antes_da_admissao' is not null);
  v := verificar_novo_horario(v_t, current_date + 16, '11:00');
  perform teste.ok('data depois do limite é barrada', not (v->>'ok')::boolean and (v->>'fora_do_prazo')::boolean);
  begin perform instrutor_remarcar(v_t, v_d, '14:00', 'Teste'); perform teste.ok('remarcar com conflito é recusado', false);
  exception when others then perform teste.ok('remarcar com conflito é recusado: ' || sqlerrm, sqlerrm like 'Horário indisponível%'); end;
  begin perform instrutor_remarcar(v_t, current_date + 16, '11:00', 'Teste'); perform teste.ok('remarcar depois do limite é recusado', false);
  exception when others then perform teste.ok('remarcar depois do limite é recusado', sqlerrm like 'A data limite%'); end;
  perform instrutor_remarcar(v_t, v_d, '11:00', 'Consulta médica');
  execute 'reset role';
  perform teste.ok('remarcação aplicada sem aprovação', exists (select 1 from turmas where id = v_t and hora_inicio = '11:00' and status = 'agenda_confirmada'));
  perform teste.ok('Gente e Gestão é avisada', exists (select 1 from notificacoes where tipo = 'alteracao_instrutor' and turma_id = v_t));
  perform teste.ok('remarcação fica no histórico', exists (select 1 from turma_solicitacoes where turma_id = v_t and status = 'aprovada' and motivo = 'Consulta médica'));
  -- passou da janela: só Gente e Gestão
  update colaboradores set data_admissao = current_date - 16 where id = v_c;
  update movimentacoes set data_inicio = current_date - 16 where colaborador_id = v_c;
  perform teste.como(v_e);
  v := verificar_novo_horario(v_t);
  perform teste.ok('prazo encerrado aparece', not (v->>'prazo_aberto')::boolean);
  begin perform instrutor_remarcar(v_t, v_d, '10:00', 'Teste'); perform teste.ok('instrutor não remarca depois do prazo', false);
  exception when others then perform teste.ok('instrutor não remarca depois do prazo', sqlerrm like 'O prazo para remarcar%'); end;
  perform teste.como('colaborador.teste@example.com');
  begin perform instrutor_remarcar(v_t, v_d, '10:00', 'Teste'); perform teste.ok('outra pessoa não remarca', false);
  exception when others then perform teste.ok('outra pessoa não remarca', true); end;
  execute 'reset role';
  delete from turmas where id in (v_t, v_o);
  update colaboradores set data_admissao = current_date - 400 where id = v_c;
end $x$;

-- Edição de cargo e departamento
do $x$
declare v_c uuid; v_cg uuid; v_d uuid; v_nome text;
begin
  execute 'reset role';
  select c.id, c.cargo_id into v_c, v_cg from colaboradores c join movimentacoes m on m.colaborador_id = c.id and m.data_fim is null and m.cargo_id = c.cargo_id where c.ativo limit 1;
  select d.id into v_d from departamentos d where d.id <> (select departamento_id from cargos where id = v_cg) limit 1;
  perform teste.como('gestao.teste@example.com');
  update departamentos set nome = nome || ' X' where id = v_d returning nome into v_nome;
  update cargos set departamento_id = v_d, nome = nome || ' X' where id = v_cg;
  execute 'reset role';
  perform teste.ok('nome do departamento alterado', exists (select 1 from departamentos where id = v_d and nome = v_nome));
  perform teste.ok('colaborador acompanha o departamento do cargo', (select departamento_id from colaboradores where id = v_c) = v_d);
  perform teste.ok('movimentação aberta acompanha', (select departamento_id from movimentacoes where colaborador_id = v_c and data_fim is null) = v_d);
  perform teste.ok('nome do cargo aparece para o colaborador', (select g.nome like '% X' from colaboradores c join cargos g on g.id = c.cargo_id where c.id = v_c));
  perform teste.como('instrutor.teste@example.com');
  update departamentos set nome = 'Invadido' where id = v_d;
  update cargos set nome = 'Invadido' where id = v_cg;
  execute 'reset role';
  perform teste.ok('instrutor não edita', not exists (select 1 from departamentos where nome = 'Invadido') and not exists (select 1 from cargos where nome = 'Invadido'));
end $x$;

-- Departamento inativo
do $x$
declare v_d uuid; v_vazio uuid; v_cg uuid; v_ok boolean;
begin
  execute 'reset role';
  select c.departamento_id into v_d from colaboradores c where c.ativo and c.departamento_id is not null limit 1;
  perform teste.como('gestao.teste@example.com');
  begin update departamentos set ativo = false where id = v_d; perform teste.ok('não inativa com gente ativa', false);
  exception when others then perform teste.ok('não inativa com gente ativa: ' || sqlerrm, sqlerrm like '%Mova ou inative%'); end;
  insert into departamentos (nome) values ('Departamento vazio') returning id into v_vazio;
  update departamentos set ativo = false where id = v_vazio;
  perform teste.ok('inativa departamento vazio', exists (select 1 from departamentos where id = v_vazio and not ativo));
  begin insert into cargos (nome, departamento_id) values ('Cargo novo', v_vazio); perform teste.ok('sem cargo em departamento inativo', false);
  exception when others then perform teste.ok('sem cargo em departamento inativo', sqlerrm like '%está inativo%'); end;
  select id into v_cg from cargos where ativo limit 1;
  begin update cargos set departamento_id = v_vazio where id = v_cg; perform teste.ok('não move cargo para departamento inativo', false);
  exception when others then perform teste.ok('não move cargo para departamento inativo', sqlerrm like '%está inativo%'); end;
  update departamentos set ativo = true where id = v_vazio;
  perform teste.ok('reativa departamento', exists (select 1 from departamentos where id = v_vazio and ativo));
  execute 'reset role';
  delete from departamentos where id = v_vazio;
end $x$;
-- Equipe do gestor: departamentos mais pessoas escolhidas uma a uma
do $x$
declare v_fora uuid; v_gestor uuid; v_outra uuid; v_dep uuid;
begin
  execute 'reset role';
  select id into v_gestor from usuarios where email = 'gestor.teste@example.com';
  select id into v_dep from departamentos where nome = 'CONTROLADORIA';
  select id into v_fora from colaboradores where ativo and departamento_id <> v_dep order by nome limit 1;
  select id into v_outra from colaboradores where ativo and departamento_id <> v_dep and id <> v_fora order by nome limit 1;
  perform teste.como('gestor.teste@example.com');
  perform teste.ok('gestor não vê pessoa de fora antes de escolher', not exists (select 1 from painel_colaboradores() p where p.id = v_fora));
  execute 'reset role';
  insert into usuarios_colaboradores values (v_gestor, v_fora);
  perform teste.como('gestor.teste@example.com');
  perform teste.ok('gestor vê a pessoa escolhida', exists (select 1 from painel_colaboradores() p where p.id = v_fora) and exists (select 1 from colaboradores where id = v_fora));
  perform teste.ok('gestor segue vendo o departamento', exists (select 1 from colaboradores where departamento_id = v_dep));
  perform teste.ok('gestor não vê quem não foi escolhido', not exists (select 1 from colaboradores where id = v_outra));
  perform teste.ok('gestor lê a própria equipe', (select count(*) from usuarios_colaboradores) = 1);
  begin insert into usuarios_colaboradores values (v_gestor, v_outra); perform teste.ok('gestor não aumenta a própria equipe', false);
  exception when insufficient_privilege then perform teste.ok('gestor não aumenta a própria equipe', true); end;
  perform teste.como('colaborador.teste@example.com');
  perform teste.ok('colaborador não lê equipe de gestor', (select count(*) from usuarios_colaboradores) = 0);
  execute 'reset role';
  update usuarios set perfil = 'colaborador' where id = v_gestor;
  perform teste.como('gestor.teste@example.com');
  perform teste.ok('quem deixa de ser gestor não vê mais a pessoa', not exists (select 1 from colaboradores where id = v_fora));
  execute 'reset role';
  update usuarios set perfil = 'gestor' where id = v_gestor;
  delete from usuarios_colaboradores where usuario_id = v_gestor;
end $x$;
-- Avisos ao colaborador
do $x$
declare v_t uuid; v_tr uuid; v_com uuid; v_com2 uuid; v_sem uuid; v_novo uuid; v_cg uuid; v_e text; v_e2 text; v_inst text := 'outro.instrutor@example.com'; v_d date := (now() at time zone 'America/Sao_Paulo')::date + 10;
  conta int;
begin
  execute 'reset role';
  update parametros set valor = '2026-01-01' where chave = 'avisos_desde';
  select id into v_tr from treinamentos where ativo order by nome limit 1;
  select id, cargo_id, lower(email) into v_com, v_cg, v_e from colaboradores where ativo and email is not null order by nome limit 1;
  select id, lower(email) into v_com2, v_e2 from colaboradores where ativo and email is not null and id <> v_com order by nome limit 1;
  select id into v_sem from colaboradores where ativo and id not in (v_com, v_com2) order by nome limit 1;
  update colaboradores set email = null where id = v_sem;
  select id into v_novo from colaboradores where ativo and id not in (v_com, v_com2, v_sem) and email is not null order by nome limit 1;
  insert into turmas (treinamento_id, status, data, hora_inicio, sala, instrutor_email) values (v_tr, 'agenda_confirmada', v_d, '10:00', 'Sala aviso', v_inst) returning id into v_t;
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id, origem) values (v_t, v_com, v_cg, 'manual'), (v_t, v_com2, v_cg, 'manual'), (v_t, v_sem, v_cg, 'manual');
  perform teste.ok('sem aviso antes de formalizar', not exists (select 1 from notificacoes where turma_id = v_t and tipo like '%_colaborador'));
  update turmas set status = 'convite_enviado', convite_enviado_em = now() where id = v_t;
  select count(*) into conta from notificacoes where turma_id = v_t and tipo = 'convocacao_colaborador';
  perform teste.ok('convoca só quem tem e-mail', conta = 2);
  -- Horário muda antes do envio: a convocação pendente já sai com o dado novo, sem e-mail extra.
  update turmas set hora_inicio = '11:00' where id = v_t;
  perform teste.ok('sem alteração para quem não recebeu a convocação', not exists (select 1 from notificacoes where turma_id = v_t and tipo = 'alteracao_colaborador'));
  update notificacoes set status = 'enviada', enviado_em = now() where turma_id = v_t and destinatario = v_e;
  update turmas set hora_inicio = '12:00' where id = v_t;
  perform teste.ok('alteração só para quem já foi convocado', (select array_agg(destinatario) from notificacoes where turma_id = v_t and tipo = 'alteracao_colaborador' and status = 'pendente') = array[v_e]);
  update turmas set sala = 'Sala nova' where id = v_t;
  perform teste.ok('alteração não acumula', (select count(*) from notificacoes where turma_id = v_t and tipo = 'alteracao_colaborador' and status = 'pendente') = 1);
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id, origem) values (v_t, v_novo, v_cg, 'manual');
  perform teste.ok('quem entra depois é convocado', (select count(*) from notificacoes where turma_id = v_t and tipo = 'convocacao_colaborador') = 3);
  delete from turma_participantes where turma_id = v_t and colaborador_id = v_com2;
  perform teste.ok('quem sai antes do envio não recebe nada', not exists (select 1 from notificacoes where turma_id = v_t and destinatario = v_e2 and status = 'pendente'));
  -- Lembrete: turma entrando na janela de 1 hora.
  update turmas set data = (now() at time zone 'America/Sao_Paulo')::date, hora_inicio = ((now() at time zone 'America/Sao_Paulo') + interval '30 minutes')::time(0) where id = v_t;
  perform app.gerar_avisos_por_horario(); perform app.gerar_avisos_por_horario();
  if ((now() at time zone 'America/Sao_Paulo') + interval '30 minutes')::date = (now() at time zone 'America/Sao_Paulo')::date then
    perform teste.ok('lembrete de 1 hora ao colaborador, uma vez só', (select count(*) from notificacoes where turma_id = v_t and tipo = 'lembrete_1h_colaborador' and destinatario = v_e) = 1);
    perform teste.ok('lembrete não vai a quem saiu nem a quem não tem e-mail', (select count(*) from notificacoes where turma_id = v_t and tipo = 'lembrete_1h_colaborador') = 2);
  else perform teste.ok('lembrete de 1 hora ao colaborador, uma vez só', true); perform teste.ok('lembrete não vai a quem saiu nem a quem não tem e-mail', true); end if;
  update turmas set data = v_d, hora_inicio = '12:00' where id = v_t;
  perform teste.como('gestao.teste@example.com');
  perform cancelar_turma(v_t, 'Teste');
  execute 'reset role';
  perform teste.ok('cancelamento avisa quem já foi convocado', (select array_agg(destinatario) from notificacoes where turma_id = v_t and tipo = 'desmarcado_colaborador' and status = 'pendente') = array[v_e]);
  perform teste.ok('cancelamento descarta os outros avisos', not exists (select 1 from notificacoes where turma_id = v_t and status = 'pendente' and tipo in ('convocacao_colaborador', 'alteracao_colaborador', 'lembrete_1h_colaborador')));
  perform teste.ok('monta o e-mail do colaborador', (app.montar_email('convocacao_colaborador', v_t) ->> 'assunto') like 'Convocação:%');
  -- Volta para reagendar: desmarca e convoca de novo ao formalizar.
  insert into turmas (treinamento_id, status, data, hora_inicio, sala, instrutor_email) values (v_tr, 'agenda_confirmada', v_d + 1, '10:00', 'Sala aviso 2', v_inst) returning id into v_t;
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id, origem) values (v_t, v_com, v_cg, 'manual');
  update turmas set status = 'convite_enviado', convite_enviado_em = now() where id = v_t;
  update notificacoes set status = 'enviada', enviado_em = now() where turma_id = v_t;
  update turmas set status = 'aguardando_instrutor', convite_enviado_em = null where id = v_t;
  perform teste.ok('reagendar desmarca', exists (select 1 from notificacoes where turma_id = v_t and tipo = 'desmarcado_colaborador' and status = 'pendente'));
  update turmas set status = 'convite_enviado', convite_enviado_em = now() where id = v_t;
  perform teste.ok('nova formalização convoca de novo', exists (select 1 from notificacoes where turma_id = v_t and tipo = 'convocacao_colaborador' and status = 'pendente'));
  -- Turma antiga não gera aviso.
  insert into turmas (treinamento_id, status, data, hora_inicio, sala, instrutor_email) values (v_tr, 'agenda_confirmada', v_d - 400, '10:00', 'Sala aviso 3', v_inst) returning id into v_t;
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id, origem) values (v_t, v_com, v_cg, 'manual');
  update turmas set status = 'convite_enviado' where id = v_t;
  perform teste.ok('turma passada não convoca', not exists (select 1 from notificacoes where turma_id = v_t and tipo like '%_colaborador'));
  update turmas set status = 'cancelada' where id = v_t;
  delete from notificacoes where tipo like '%_colaborador';
  update colaboradores set email = 'restaurado@example.com' where id = v_sem;
end $x$;
select teste.ok('nenhum participante sem pessoa', not exists (select 1 from turma_participantes where colaborador_id is null));
select teste.ok('histórico registrado', (select count(*) from eventos) > 0);
