-- O aviso ao montar a turma passa a olhar o perfil: só instrutor (ou Gente e Gestão) consegue responder.
create or replace function public.turma_detalhe(p_turma uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not app.pode_ver_turma(p_turma) then raise exception 'Sem acesso a esta turma' using errcode = '42501'; end if;
  select to_jsonb(t) || jsonb_build_object(
    'treinamento', tr.nome, 'carga_minutos', tr.carga_minutos, 'etapa', app.etapa_turma(t.status, app.periodo_turma(t.id)),
    'inicio', lower(app.periodo_turma(t.id)), 'fim', upper(app.periodo_turma(t.id)),
    'sou_instrutor', t.instrutor_email = app.meu_email(),
    'instrutor_tem_acesso', exists (select 1 from usuarios u where u.email = t.instrutor_email and u.ativo and u.perfil in ('instrutor', 'admin')),
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
