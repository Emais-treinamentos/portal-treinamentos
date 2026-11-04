-- Segurança do Trabalho não tem perfil próprio: quem aplica treinamento entra como instrutor.
update public.usuarios set perfil = 'instrutor' where perfil = 'seguranca';
alter table public.usuarios add constraint perfil_sem_seguranca check (perfil <> 'seguranca');
create or replace function app.le_tudo() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select perfil = 'admin' from usuarios where id = auth.uid() and ativo), false) $$;
