-- Controle de frequência do código de acesso enviado pelo n8n (um por minuto para cada e-mail).
create table public.codigos_acesso_envios (
  email text primary key,
  enviado_em timestamptz not null default now()
);
alter table public.codigos_acesso_envios enable row level security;
revoke all on public.codigos_acesso_envios from anon, authenticated;

-- Configurações que só as funções do servidor leem (endereço e chave do n8n). Valores gravados fora do repositório.
create table public.configuracao_privada (
  chave text primary key,
  valor text not null,
  atualizado_em timestamptz not null default now()
);
alter table public.configuracao_privada enable row level security;
revoke all on public.configuracao_privada from anon, authenticated;
