-- O gestor vê os departamentos marcados e também as pessoas escolhidas uma a uma.
create table public.usuarios_colaboradores (
  usuario_id uuid not null references public.usuarios on delete cascade,
  colaborador_id uuid not null references public.colaboradores on delete cascade,
  primary key (usuario_id, colaborador_id)
);
create index usuarios_colaboradores_colaborador on public.usuarios_colaboradores (colaborador_id);

alter table public.usuarios_colaboradores enable row level security;
revoke all on public.usuarios_colaboradores from anon, authenticated;
grant select on public.usuarios_colaboradores to authenticated;
create policy leitura on public.usuarios_colaboradores for select to authenticated using (usuario_id = (select auth.uid()) or (select app.eh_admin()));
create trigger evento after insert or update or delete on public.usuarios_colaboradores for each row execute function app.registrar_evento('usuario_id');

create function app.gestor_do_colaborador(p_colaborador uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from usuarios u join usuarios_colaboradores e on e.usuario_id = u.id
                 where u.id = auth.uid() and u.ativo and u.perfil = 'gestor' and e.colaborador_id = p_colaborador) $$;

create or replace function app.pode_ver_colaborador(p_colaborador uuid) returns boolean language sql stable security definer set search_path = public as $$
  select app.le_tudo() or p_colaborador = app.meu_colaborador()
    or app.gestor_do_colaborador(p_colaborador)
    or exists (select 1 from colaboradores c where c.id = p_colaborador and app.gestor_do_departamento(c.departamento_id)) $$;
