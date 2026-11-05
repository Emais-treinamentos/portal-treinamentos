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
select teste.ok('convite vira notificação de calendário', exists (select 1 from notificacoes where tipo='calendario_criar' and turma_id=(select v from ctx where k='t1')));
select teste.falha('presença só abre no horário', $q$select marcar_presenca((select v from ctx where k='t1'),(select id from colaboradores where nome='Clara Teste'),'presente')$q$);

-- Alteração depois do convite: mesma turma, evento atualizado.
select teste.como('instrutor.teste@example.com');
select solicitar_alteracao((select v from ctx where k='t1'),'alteracao','Viagem no dia','{"data":"2031-05-05","hora":"10:00"}');
select teste.falha('só uma solicitação aberta', $q$select solicitar_alteracao((select v from ctx where k='t1'),'alteracao','Outra')$q$);
select teste.como('gestao.teste@example.com');
select decidir_solicitacao((select id from turma_solicitacoes where turma_id=(select v from ctx where k='t1')),true,'Ok');
select teste.ok('mesma turma com nova data', (select data='2031-05-05' and hora_inicio='10:00' and status='convite_enviado' from turmas where id=(select v from ctx where k='t1')));
select teste.ok('calendário atualizado na fila', exists (select 1 from notificacoes where tipo='calendario_atualizar' and turma_id=(select v from ctx where k='t1')));

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
select teste.ok('cancelamento do calendário na fila', exists (select 1 from notificacoes where turma_id=(select v from ctx where k='t1') and status='pendente' and tipo='calendario_cancelar'));

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
insert into colaboradores (nome, cargo_id, departamento_id, data_admissao) select n, (select id from cargos where nome='CARGO EFICACIA'), (select id from departamentos where nome='COMERCIAL'), current_date - 400 from unnest(array['Erica Teste','Breno Teste']) n;
insert into turmas (treinamento_id, status, data, hora_inicio, hora_opcao_1, sala, instrutor_email, presenca_concluida_em) select (select id from treinamentos where nome='Código de Ética'), 'realizada', d, '09:00', '09:00', 'Time Forte', 'instrutor.teste@example.com', now() from unnest(array[current_date - 120, current_date - 10]) d;
insert into turma_participantes (turma_id, colaborador_id, situacao, cargo_na_data_id) select t.id, c.id, 'presente', c.cargo_id from colaboradores c join turmas t on t.data = case c.nome when 'Erica Teste' then current_date - 120 else current_date - 10 end and t.status = 'realizada' and t.sala = 'Time Forte' and t.hora_inicio = '09:00' and t.treinamento_id = (select id from treinamentos where nome='Código de Ética') where c.nome in ('Erica Teste','Breno Teste');
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
select teste.falha('não avalia o mesmo ciclo duas vezes', $q$select salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date, 'Avaliador', 'eficaz')$q$);
select salvar_eficacia((select id from colaboradores where nome='Erica Teste'), current_date, 'Avaliador Teste', 'parcial', 'Precisa reforço', (select v from ctx where k='ef'));
select teste.ok('correção fica registrada', (eficacia_documento((select v from ctx where k='ef'))->>'resultado')='parcial');
select teste.ok('quem foi dispensado não entra', not exists (select 1 from eficacia_painel() where nome='Paula Teste'));
reset role;
select teste.ok('nenhum participante sem pessoa', not exists (select 1 from turma_participantes where colaborador_id is null));
select teste.ok('histórico registrado', (select count(*) from eventos) > 0);
