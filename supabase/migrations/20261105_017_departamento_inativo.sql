-- Departamento pode ser inativado. Só sai de uso quando não há cargo nem colaborador ativo nele.
alter table public.departamentos add column ativo boolean not null default true;

create function app.validar_departamento_inativo() returns trigger language plpgsql security definer set search_path = public as $$
declare v_cargos integer; v_pessoas integer;
begin
  select count(*) into v_cargos from cargos where departamento_id = new.id and ativo;
  select count(*) into v_pessoas from colaboradores where departamento_id = new.id and ativo;
  if v_cargos > 0 or v_pessoas > 0 then
    raise exception '% tem % cargo(s) e % colaborador(es) ativos. Mova ou inative antes de inativar o departamento.', new.nome, v_cargos, v_pessoas using errcode = '22023';
  end if;
  return new;
end $$;
create trigger valida_inativo before update of ativo on public.departamentos
  for each row when (old.ativo and not new.ativo) execute function app.validar_departamento_inativo();

-- Departamento inativo não recebe cargo nem colaborador ativo.
create function app.exigir_departamento_ativo() returns trigger language plpgsql security definer set search_path = public as $$
declare v_nome text;
begin
  if new.ativo and new.departamento_id is not null then
    select nome into v_nome from departamentos where id = new.departamento_id and not ativo;
    if v_nome is not null then raise exception 'O departamento % está inativo. Reative o departamento antes.', v_nome using errcode = '22023'; end if;
  end if;
  return new;
end $$;
create trigger departamento_ativo before insert or update of departamento_id, ativo on public.cargos
  for each row execute function app.exigir_departamento_ativo();
create trigger departamento_ativo before insert or update of departamento_id, ativo on public.colaboradores
  for each row execute function app.exigir_departamento_ativo();

revoke all on function app.validar_departamento_inativo(), app.exigir_departamento_ativo() from public, anon, authenticated;
