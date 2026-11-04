-- Portal de Treinamentos · modelo de dados e regras de acesso
-- Colaboradores internos. Regras de negócio no banco; o site só mostra e chama funções.
-- Escrita em turmas, participantes, matriz e reciclagem: somente pelas funções da migração 002.

create schema if not exists app;
grant usage on schema app to authenticated;

create type public.perfil_usuario as enum ('admin', 'seguranca', 'gestor', 'colaborador', 'instrutor');
create type public.tipo_turma as enum ('normal', 'admissao', 'reciclagem');
create type public.status_turma as enum ('pendente', 'aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado', 'realizada', 'encerrada', 'cancelada');
create type public.situacao_participante as enum ('convocado', 'presente', 'ausente', 'nao_aplicavel', 'a_validar');
create type public.status_revisao as enum ('aberta', 'vigente', 'arquivada');
create type public.tipo_movimentacao as enum ('admissao', 'promocao', 'transferencia');
create type public.reciclagem_tipo as enum ('step_horizontal', 'promocao_lideranca', 'mudanca_departamento', 'promocao_vertical', 'interinidade');
create type public.reciclagem_acao as enum ('total', 'parcial', 'dispensa');
create type public.tipo_solicitacao as enum ('nova_agenda', 'alteracao', 'cancelamento', 'correcao_presenca');
create type public.status_solicitacao as enum ('aberta', 'aprovada', 'recusada');
create type public.status_notificacao as enum ('pendente', 'enviada', 'erro', 'cancelada');

-- Cadastros
create table public.departamentos (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique
);

create table public.cargos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  departamento_id uuid not null references public.departamentos on delete restrict,
  ativo boolean not null default true,
  unique (nome, departamento_id)
);

create table public.colaboradores (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  email text,
  cargo_id uuid references public.cargos on delete restrict,
  departamento_id uuid references public.departamentos on delete restrict,
  data_admissao date,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
create index on public.colaboradores (cargo_id) where ativo;

create table public.movimentacoes (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores on delete restrict,
  cargo_id uuid not null references public.cargos on delete restrict,
  departamento_id uuid references public.departamentos on delete restrict,
  data_inicio date not null,
  data_fim date,
  tipo public.tipo_movimentacao not null,
  criado_em timestamptz not null default now()
);
create unique index movimentacao_ativa_unica on public.movimentacoes (colaborador_id) where data_fim is null;
create index on public.movimentacoes (colaborador_id, data_inicio);

create table public.treinamentos (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  carga_minutos integer not null check (carga_minutos > 0),
  cargo_instrutor_id uuid references public.cargos on delete set null,
  cargo_backup_id uuid references public.cargos on delete set null,
  departamento_id uuid references public.departamentos on delete set null,
  eh_politica boolean not null default false,
  individual_por_colaborador boolean not null default false,
  ativo boolean not null default true
);

-- Matriz versionada
create table public.matriz_revisoes (
  id uuid primary key default gen_random_uuid(),
  numero text not null unique,
  status public.status_revisao not null default 'aberta',
  data_inicio_vigencia date,
  descricao text,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  fechado_em timestamptz,
  constraint vigente_com_data check (status <> 'vigente' or data_inicio_vigencia is not null)
);
create unique index uma_revisao_aberta on public.matriz_revisoes ((true)) where status = 'aberta';

create table public.matriz_vinculos (
  id uuid primary key default gen_random_uuid(),
  cargo_id uuid not null references public.cargos on delete restrict,
  treinamento_id uuid not null references public.treinamentos on delete restrict,
  obrigatorio boolean not null default true,
  revisao_criacao_id uuid not null references public.matriz_revisoes on delete restrict,
  revisao_remocao_id uuid references public.matriz_revisoes on delete restrict
);
create index on public.matriz_vinculos (cargo_id, treinamento_id);

-- Turmas: o identificador não muda quando data, horário, sala ou instrutor mudam.
create table public.turmas (
  id uuid primary key default gen_random_uuid(),
  treinamento_id uuid not null references public.treinamentos on delete restrict,
  tipo public.tipo_turma not null default 'normal',
  status public.status_turma not null default 'aguardando_instrutor',
  data date,
  hora_opcao_1 time,
  hora_opcao_2 time,
  hora_inicio time,
  sala text,
  instrutor_email text check (instrutor_email = lower(instrutor_email)),
  turma_origem_id uuid references public.turmas on delete set null,
  instrutor_respondeu_em timestamptz,
  convite_enviado_em timestamptz,
  outlook_evento_id text,
  presenca_concluida_em timestamptz,
  motivo_replanejamento text,
  criado_por uuid,
  criado_em timestamptz not null default now()
);
create index on public.turmas (status);
create index on public.turmas (instrutor_email);
create index on public.turmas (treinamento_id);

create table public.turma_cargos (
  turma_id uuid not null references public.turmas on delete cascade,
  cargo_id uuid not null references public.cargos on delete restrict,
  incluir_no_convite boolean not null default true,
  primary key (turma_id, cargo_id)
);

-- Fonte da verdade do histórico: uma linha por pessoa e turma, sempre com colaborador.
create table public.turma_participantes (
  turma_id uuid not null references public.turmas on delete cascade,
  colaborador_id uuid not null references public.colaboradores on delete restrict,
  cargo_na_data_id uuid references public.cargos on delete set null,
  situacao public.situacao_participante not null default 'convocado',
  origem text not null default 'calculo' check (origem in ('calculo', 'manual', 'legado_individual', 'legado_inferido')),
  registrado_por uuid,
  registrado_em timestamptz,
  primary key (turma_id, colaborador_id)
);
create index on public.turma_participantes (colaborador_id, situacao);

create table public.turma_solicitacoes (
  id uuid primary key default gen_random_uuid(),
  turma_id uuid not null references public.turmas on delete cascade,
  tipo public.tipo_solicitacao not null,
  motivo text not null,
  proposta jsonb not null default '{}',
  status public.status_solicitacao not null default 'aberta',
  resposta text,
  solicitado_por uuid,
  solicitado_em timestamptz not null default now(),
  decidido_por uuid,
  decidido_em timestamptz
);
create index on public.turma_solicitacoes (turma_id) where status = 'aberta';

create table public.reciclagem_decisoes (
  id uuid primary key default gen_random_uuid(),
  colaborador_id uuid not null references public.colaboradores on delete restrict,
  cargo_anterior_id uuid references public.cargos on delete set null,
  cargo_atual_id uuid references public.cargos on delete set null,
  tipo_movimentacao public.reciclagem_tipo not null,
  acao_sugerida public.reciclagem_acao,
  acao_final public.reciclagem_acao not null,
  treinamentos_parcial uuid[] not null default '{}',
  decidido_por uuid,
  decidido_em timestamptz not null default now()
);
create index on public.reciclagem_decisoes (colaborador_id, decidido_em desc);

-- Apoio
create table public.usuarios (
  id uuid primary key references auth.users on delete cascade,
  nome text not null,
  email text not null unique check (email = lower(email)),
  perfil public.perfil_usuario not null,
  colaborador_id uuid references public.colaboradores on delete set null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

create table public.usuarios_departamentos (
  usuario_id uuid not null references public.usuarios on delete cascade,
  departamento_id uuid not null references public.departamentos on delete cascade,
  primary key (usuario_id, departamento_id)
);

create table public.parametros (
  chave text primary key,
  valor text not null,
  descricao text not null
);

create table public.modelos_documento (
  codigo text primary key,
  titulo text not null,
  texto text not null,
  revisao text,
  data_revisao date
);

create table public.eventos (
  id bigint generated always as identity primary key,
  tabela text not null,
  registro_id text,
  acao text not null,
  antes jsonb,
  depois jsonb,
  usuario uuid,
  quando timestamptz not null default now()
);
create index on public.eventos (tabela, registro_id);

create table public.notificacoes (
  id uuid primary key default gen_random_uuid(),
  tipo text not null,
  turma_id uuid references public.turmas on delete cascade,
  destinatario text not null,
  status public.status_notificacao not null default 'pendente',
  tentativas integer not null default 0,
  erro text,
  criado_em timestamptz not null default now(),
  enviado_em timestamptz
);
create index on public.notificacoes (status, criado_em);

insert into public.parametros (chave, valor, descricao) values
  ('janela_convocacao_dias', '15', 'Dias depois da admissão ou movimentação em que a pessoa entra na turma'),
  ('prazo_reciclagem_dias', '730', 'Dias para reciclagem por movimentação'),
  ('meses_politicas', '24', 'Meses de empresa para cobrar políticas na reciclagem'),
  ('meses_movimentacao', '24', 'Meses que definem movimentação recente na reciclagem'),
  ('prazo_resposta_instrutor_dias', '2', 'Dias até lembrar o instrutor de responder a agenda'),
  ('prazo_presenca_dias', '3', 'Dias depois da turma até lembrar o instrutor de registrar a presença'),
  ('salas', '["Time Forte","Obstinação por Resultados","Foco do Cliente","Postura de Dono","Meritocracia","Edícula","Inovação","Externo"]', 'Salas disponíveis, em JSON');

-- Quem é quem. Definer para não acionar as próprias regras de acesso.
create function app.perfil() returns public.perfil_usuario language sql stable security definer set search_path = public as $$
  select perfil from usuarios where id = auth.uid() and ativo $$;
create function app.eh_admin() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select perfil = 'admin' from usuarios where id = auth.uid() and ativo), false) $$;
create function app.le_tudo() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select perfil in ('admin', 'seguranca') from usuarios where id = auth.uid() and ativo), false) $$;
create function app.meu_email() returns text language sql stable security definer set search_path = public as $$
  select email from usuarios where id = auth.uid() and ativo $$;
create function app.meu_colaborador() returns uuid language sql stable security definer set search_path = public as $$
  select colaborador_id from usuarios where id = auth.uid() and ativo $$;
create function app.gestor_do_departamento(p_departamento uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from usuarios u join usuarios_departamentos d on d.usuario_id = u.id
                 where u.id = auth.uid() and u.ativo and u.perfil = 'gestor' and d.departamento_id = p_departamento) $$;
create function app.pode_ver_colaborador(p_colaborador uuid) returns boolean language sql stable security definer set search_path = public as $$
  select app.le_tudo() or p_colaborador = app.meu_colaborador()
    or exists (select 1 from colaboradores c where c.id = p_colaborador and app.gestor_do_departamento(c.departamento_id)) $$;
create function app.eh_instrutor_da_turma(p_turma uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from turmas t where t.id = p_turma and t.instrutor_email = app.meu_email()) $$;
create function app.pode_ver_turma(p_turma uuid) returns boolean language sql stable security definer set search_path = public as $$
  select app.le_tudo() or app.eh_instrutor_da_turma(p_turma)
    or exists (select 1 from turma_participantes p where p.turma_id = p_turma and app.pode_ver_colaborador(p.colaborador_id)) $$;

-- Histórico de alterações
create function app.registrar_evento() returns trigger language plpgsql security definer set search_path = public as $$
declare
  novo jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  velho jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
begin
  insert into eventos (tabela, registro_id, acao, antes, depois, usuario)
  values (tg_table_name,
          coalesce(novo, velho) ->> coalesce(tg_argv[0], 'id'),
          lower(tg_op), velho, novo, auth.uid());
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['colaboradores','movimentacoes','treinamentos','cargos','matriz_revisoes','matriz_vinculos','turmas','turma_solicitacoes','reciclagem_decisoes','usuarios'] loop
    execute format('create trigger evento after insert or update or delete on public.%I for each row execute function app.registrar_evento()', t);
  end loop;
  execute 'create trigger evento after insert or update or delete on public.turma_participantes for each row execute function app.registrar_evento(''turma_id'')';
  execute 'create trigger evento after insert or update or delete on public.turma_cargos for each row execute function app.registrar_evento(''turma_id'')';
  execute 'create trigger evento after insert or update or delete on public.parametros for each row execute function app.registrar_evento(''chave'')';
end $$;

-- Regras de acesso
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

grant select on public.departamentos, public.cargos, public.treinamentos, public.parametros, public.modelos_documento to authenticated;
grant insert, update on public.departamentos, public.cargos, public.treinamentos, public.parametros, public.modelos_documento to authenticated;
grant select on public.colaboradores, public.movimentacoes, public.matriz_revisoes, public.matriz_vinculos, public.turmas, public.turma_cargos,
  public.turma_participantes, public.turma_solicitacoes, public.reciclagem_decisoes, public.usuarios, public.usuarios_departamentos,
  public.eventos, public.notificacoes to authenticated;

create policy leitura on public.departamentos for select to authenticated using ((select app.perfil()) is not null);
create policy leitura on public.cargos for select to authenticated using ((select app.perfil()) is not null);
create policy leitura on public.treinamentos for select to authenticated using ((select app.perfil()) is not null);
create policy leitura on public.parametros for select to authenticated using ((select app.perfil()) is not null);
create policy leitura on public.modelos_documento for select to authenticated using ((select app.perfil()) is not null);
create policy inclusao on public.departamentos for insert to authenticated with check ((select app.eh_admin()));
create policy edicao on public.departamentos for update to authenticated using ((select app.eh_admin()));
create policy inclusao on public.cargos for insert to authenticated with check ((select app.eh_admin()));
create policy edicao on public.cargos for update to authenticated using ((select app.eh_admin()));
create policy inclusao on public.treinamentos for insert to authenticated with check ((select app.eh_admin()));
create policy edicao on public.treinamentos for update to authenticated using ((select app.eh_admin()));
create policy inclusao on public.parametros for insert to authenticated with check ((select app.eh_admin()));
create policy edicao on public.parametros for update to authenticated using ((select app.eh_admin()));
create policy inclusao on public.modelos_documento for insert to authenticated with check ((select app.eh_admin()));
create policy edicao on public.modelos_documento for update to authenticated using ((select app.eh_admin()));

create policy leitura on public.colaboradores for select to authenticated using (app.pode_ver_colaborador(id));
create policy leitura on public.movimentacoes for select to authenticated using (app.pode_ver_colaborador(colaborador_id));
create policy leitura on public.matriz_revisoes for select to authenticated using ((select app.le_tudo()));
create policy leitura on public.matriz_vinculos for select to authenticated using ((select app.le_tudo()));
create policy leitura on public.turmas for select to authenticated using (app.pode_ver_turma(id));
create policy leitura on public.turma_cargos for select to authenticated using (app.pode_ver_turma(turma_id));
create policy leitura on public.turma_participantes for select to authenticated using ((select app.le_tudo()) or app.eh_instrutor_da_turma(turma_id) or app.pode_ver_colaborador(colaborador_id));
create policy leitura on public.turma_solicitacoes for select to authenticated using ((select app.le_tudo()) or app.eh_instrutor_da_turma(turma_id));
create policy leitura on public.reciclagem_decisoes for select to authenticated using ((select app.eh_admin()) or colaborador_id = (select app.meu_colaborador()));
create policy leitura on public.usuarios for select to authenticated using (id = (select auth.uid()) or (select app.eh_admin()));
create policy leitura on public.usuarios_departamentos for select to authenticated using (usuario_id = (select auth.uid()) or (select app.eh_admin()));
create policy leitura on public.eventos for select to authenticated using ((select app.eh_admin()));
create policy leitura on public.notificacoes for select to authenticated using ((select app.eh_admin()));
