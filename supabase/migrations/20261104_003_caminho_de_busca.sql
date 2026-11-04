-- Fixa o caminho de busca das funções auxiliares, como pede o alerta de segurança do Supabase.
alter function app.hoje() set search_path = public;
alter function app.exigir_admin() set search_path = public;
alter function app.etapa_turma(public.status_turma, tstzrange) set search_path = public;
