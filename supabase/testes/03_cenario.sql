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
  for u in select * from (values ('gestao.teste@example.com','admin','Gabriela Teste'),('seguranca.teste@example.com','seguranca','Sara Teste'),
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
select teste.ok('segurança lê todos', (select count(*) from colaboradores) = 14);
select teste.falha('segurança não formaliza', $q$select formalizar_turma(gen_random_uuid())$q$);

-- Ciclo. Cargo sem elegível não vira linha.
select teste.como('gestao.teste@example.com');
select teste.ok('a planejar tem pendências', (select count(*) from a_planejar()) > 0);
insert into ctx values ('c_jr',(select id from cargos where nome like '%JUNIOR')),('c_en',(select id from cargos where nome='ENGENHEIRO DE OBRAS')),('c_se',(select id from cargos where nome='TÉCNICO DE SEGURANÇA'));
insert into ctx select 't1', criar_turma((select id from treinamentos where nome='Código de Ética'),'admissao',current_date+5,'09:00','14:00','INSTRUTOR.TESTE@example.com',
  array[(select v from ctx where k='c_jr'),(select v from ctx where k='c_en'),(select id from cargos where nome='CONSULTOR DE VENDAS'),(select id from cargos where nome='ANALISTA GENTE E GESTÃO')]);
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
reset role;
select teste.ok('nenhum participante sem pessoa', not exists (select 1 from turma_participantes where colaborador_id is null));
select teste.ok('histórico registrado', (select count(*) from eventos) > 0);
