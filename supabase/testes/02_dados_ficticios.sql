-- Dados fictícios para o teste inicial. Datas relativas ao dia da carga. Nenhuma pessoa real.
do $$
declare
  hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  rev uuid; dg uuid; dc uuid; dt uuid; ds uuid; dm uuid;
  cAG uuid; cAP uuid; cCO uuid; cSU uuid; cEN uuid; cAU uuid; cTS uuid; cVE uuid;
  tBV uuid; tPC uuid; tET uuid; tLG uuid; tSI uuid; tNR uuid; tNE uuid; tVD uuid;
  c record; tt uuid;
begin
  insert into departamentos (nome) values ('GENTE E GESTÃO') returning id into dg;
  insert into departamentos (nome) values ('CONTROLADORIA') returning id into dc;
  insert into departamentos (nome) values ('ENGENHARIA') returning id into dt;
  insert into departamentos (nome) values ('SEGURANÇA DO TRABALHO') returning id into ds;
  insert into departamentos (nome) values ('COMERCIAL') returning id into dm;
  insert into cargos (nome, departamento_id) values ('ANALISTA GENTE E GESTÃO', dg) returning id into cAG;
  insert into cargos (nome, departamento_id) values ('ANALISTA CONTROLADORIA PLENO', dc) returning id into cAP;
  insert into cargos (nome, departamento_id) values ('ANALISTA CONTROLADORIA JUNIOR', dc) returning id into cCO;
  insert into cargos (nome, departamento_id) values ('SUPERVISOR CONTROLADORIA', dc) returning id into cSU;
  insert into cargos (nome, departamento_id) values ('ENGENHEIRO DE OBRAS', dt) returning id into cEN;
  insert into cargos (nome, departamento_id) values ('AUXILIAR DE OBRAS', dt) returning id into cAU;
  insert into cargos (nome, departamento_id) values ('TÉCNICO DE SEGURANÇA', ds) returning id into cTS;
  insert into cargos (nome, departamento_id) values ('CONSULTOR DE VENDAS', dm) returning id into cVE;
  insert into treinamentos (nome, carga_minutos, eh_politica, cargo_instrutor_id) values ('Boas-vindas à Emais', 60, false, cAG) returning id into tBV;
  insert into treinamentos (nome, carga_minutos, eh_politica, cargo_instrutor_id) values ('Política de Cursos e Treinamentos', 30, true, cAG) returning id into tPC;
  insert into treinamentos (nome, carga_minutos, eh_politica, cargo_instrutor_id) values ('Código de Ética', 45, true, cAG) returning id into tET;
  insert into treinamentos (nome, carga_minutos, eh_politica, cargo_instrutor_id) values ('LGPD no dia a dia', 90, true, cAG) returning id into tLG;
  insert into treinamentos (nome, carga_minutos) values ('Rotinas da Controladoria', 120) returning id into tSI;
  insert into treinamentos (nome, carga_minutos, cargo_instrutor_id) values ('NR 35 Trabalho em Altura', 240, cTS) returning id into tNR;
  insert into treinamentos (nome, carga_minutos, cargo_instrutor_id) values ('Orientação de Segurança na Obra', 90, cTS) returning id into tNE;
  insert into treinamentos (nome, carga_minutos, individual_por_colaborador) values ('Rotinas Comerciais', 120, true) returning id into tVD;
  insert into matriz_revisoes (numero, status, data_inicio_vigencia, descricao, fechado_em) values ('REV-INICIAL', 'vigente', '2020-01-01', 'Matriz inicial fictícia', now()) returning id into rev;
  insert into matriz_vinculos (cargo_id, treinamento_id, revisao_criacao_id)
  select g, t, rev from unnest(array[cAG, cAP, cCO, cSU, cEN, cAU, cTS, cVE]) g cross join unnest(array[tBV, tPC, tET, tLG]) t;
  insert into matriz_vinculos (cargo_id, treinamento_id, revisao_criacao_id) values
    (cAP, tSI, rev), (cSU, tSI, rev), (cEN, tNE, rev), (cAU, tNE, rev), (cAU, tNR, rev), (cTS, tNE, rev), (cTS, tNR, rev), (cVE, tVD, rev);
  for c in select * from (values
    ('Gabriela Teste', 'gestao.teste@example.com', cAG, 900), ('Sara Teste', 'seguranca.teste@example.com', cTS, 800),
    ('Igor Teste Instrutor', 'instrutor.teste@example.com', cSU, 1000), ('Gustavo Teste Gestor', 'gestor.teste@example.com', cSU, 1100),
    ('Clara Teste', 'colaborador.teste@example.com', cCO, 5), ('Caio Teste', null, cCO, 7), ('Paula Teste', null, cAP, 400),
    ('Eduardo Teste', null, cEN, 3), ('Aline Teste', null, cAU, 2), ('Antonio Teste', null, cAU, 6),
    ('Tales Teste', null, cTS, 12), ('Vera Teste', null, cVE, 4), ('Bruna Teste', null, cCO, 90), ('Otavio Teste', null, cEN, 700)
  ) as x(nome, email, cargo, dias) loop
    insert into colaboradores (nome, email, cargo_id, departamento_id, data_admissao)
    select c.nome, c.email, c.cargo, departamento_id, hoje - c.dias from cargos where id = c.cargo returning id into tt;
    insert into movimentacoes (colaborador_id, cargo_id, departamento_id, data_inicio, tipo)
    select tt, c.cargo, departamento_id, hoje - c.dias, 'admissao' from cargos where id = c.cargo;
  end loop;
  -- Promoção recente: de Junior para Pleno, sem classificar.
  update movimentacoes set data_fim = hoje - 10, cargo_id = cCO where colaborador_id = (select id from colaboradores where nome = 'Paula Teste');
  insert into movimentacoes (colaborador_id, cargo_id, departamento_id, data_inicio, tipo) select id, cAP, dc, hoje - 10, 'promocao' from colaboradores where nome = 'Paula Teste';
  -- Histórico já realizado dos mais antigos.
  insert into turmas (treinamento_id, tipo, status, data, hora_opcao_1, hora_inicio, sala, instrutor_email, convite_enviado_em, presenca_concluida_em, criado_em)
  values (tBV, 'admissao', 'realizada', hoje - 300, '09:00', '09:00', 'Time Forte', 'instrutor.teste@example.com', now() - interval '310 days', now() - interval '300 days', now() - interval '320 days') returning id into tt;
  insert into turma_cargos (turma_id, cargo_id) select tt, unnest(array[cAG, cTS, cSU, cEN]);
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id, situacao, origem, registrado_em)
  select tt, id, cargo_id, 'presente', 'manual', now() - interval '300 days' from colaboradores where nome in ('Gabriela Teste', 'Sara Teste', 'Igor Teste Instrutor', 'Gustavo Teste Gestor', 'Otavio Teste', 'Paula Teste');
  -- Turma já ocorrida, com presença a registrar.
  insert into turmas (treinamento_id, tipo, status, data, hora_opcao_1, hora_inicio, sala, instrutor_email, convite_enviado_em, criado_em)
  values (tPC, 'admissao', 'convite_enviado', hoje - 1, '09:00', '09:00', 'Inovação', 'instrutor.teste@example.com', now() - interval '3 days', now() - interval '5 days') returning id into tt;
  insert into turma_cargos (turma_id, cargo_id) select tt, unnest(array[cAU, cVE]);
  insert into turma_participantes (turma_id, colaborador_id, cargo_na_data_id) select tt, id, cargo_id from colaboradores where nome in ('Aline Teste', 'Antonio Teste', 'Vera Teste');
end $$;
