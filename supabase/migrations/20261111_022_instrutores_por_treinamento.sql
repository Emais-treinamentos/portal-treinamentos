-- Quem aplica cada treinamento e quem substitui. O vínculo fica no acesso da pessoa.
create function app.pode_ser_instrutor(p_usuario uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from usuarios u where u.id = p_usuario and (u.perfil in ('instrutor', 'gestor') or (u.perfil = 'admin' and u.tambem_instrutor))) $$;

create table public.instrutores_treinamento (
  usuario_id uuid not null references public.usuarios on delete cascade,
  treinamento_id uuid not null references public.treinamentos on delete cascade,
  substituto_id uuid references public.usuarios on delete set null,
  primary key (usuario_id, treinamento_id),
  constraint substituto_diferente check (substituto_id is distinct from usuario_id)
);
create index instrutores_treinamento_treinamento on public.instrutores_treinamento (treinamento_id);
create index instrutores_treinamento_substituto on public.instrutores_treinamento (substituto_id);

alter table public.instrutores_treinamento enable row level security;
revoke all on public.instrutores_treinamento from anon, authenticated;
grant select on public.instrutores_treinamento to authenticated;
create policy leitura on public.instrutores_treinamento for select to authenticated
  using ((select app.le_tudo()) or usuario_id = (select auth.uid()) or substituto_id = (select auth.uid()));
create trigger evento after insert or update or delete on public.instrutores_treinamento for each row execute function app.registrar_evento('usuario_id');

create function app.validar_instrutor_treinamento() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not app.pode_ser_instrutor(new.usuario_id) then raise exception 'Este perfil não aplica treinamentos'; end if;
  if new.substituto_id is not null and not exists (select 1 from usuarios u where u.id = new.substituto_id and u.ativo and app.pode_ser_instrutor(u.id)) then
    raise exception 'O substituto precisa ser um acesso ativo com perfil de instrutor';
  end if;
  return new;
end $$;
create trigger validar before insert or update on public.instrutores_treinamento for each row execute function app.validar_instrutor_treinamento();

-- Sugestões para o Planejar e para a troca de instrutor: titulares primeiro, depois substitutos.
create function public.instrutores_dos_treinamentos() returns table (treinamento_id uuid, email text, nome text, papel text, ativo boolean)
language plpgsql stable security definer set search_path = public as $$
begin
  perform app.exigir_admin();
  return query
  select x.treinamento_id, x.email, x.nome, x.papel, x.ativo from (
    select i.treinamento_id, u.email, u.nome, 'titular' as papel, u.ativo, 1 as ordem from instrutores_treinamento i join usuarios u on u.id = i.usuario_id
    union
    select i.treinamento_id, s.email, s.nome, 'substituto', s.ativo, 2 from instrutores_treinamento i join usuarios s on s.id = i.substituto_id
    where not exists (select 1 from instrutores_treinamento t where t.treinamento_id = i.treinamento_id and t.usuario_id = i.substituto_id)
  ) x order by x.treinamento_id, x.ordem, not x.ativo, x.nome;
end $$;
revoke all on function public.instrutores_dos_treinamentos() from public, anon;
grant execute on function public.instrutores_dos_treinamentos() to authenticated;
revoke all on function app.pode_ser_instrutor(uuid), app.validar_instrutor_treinamento() from public, anon, authenticated;
