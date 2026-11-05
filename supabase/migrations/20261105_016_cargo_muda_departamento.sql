-- Se o cargo muda de departamento, quem está nele acompanha: colaborador e movimentação em aberto.
-- Movimentações encerradas ficam como estão, porque são histórico.
create function app.gatilho_cargo_departamento() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update colaboradores set departamento_id = new.departamento_id where cargo_id = new.id and departamento_id is distinct from new.departamento_id;
  update movimentacoes set departamento_id = new.departamento_id where cargo_id = new.id and data_fim is null and departamento_id is distinct from new.departamento_id;
  return new;
end $$;
create trigger cargo_departamento after update of departamento_id on public.cargos
  for each row when (old.departamento_id is distinct from new.departamento_id) execute function app.gatilho_cargo_departamento();
revoke all on function app.gatilho_cargo_departamento() from public, anon, authenticated;
