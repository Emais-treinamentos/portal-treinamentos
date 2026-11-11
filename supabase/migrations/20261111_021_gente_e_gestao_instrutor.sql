-- Gente e Gestão pode ou não entrar também como instrutor. Gestor entra sempre como gestor e instrutor.
alter table public.usuarios add column tambem_instrutor boolean not null default true;
comment on column public.usuarios.tambem_instrutor is 'Só vale para Gente e Gestão: oferece também o perfil de instrutor ao entrar';
