# Teste do banco

Roda as migrações num Postgres local, com uma imitação mínima do Supabase e dados fictícios, e percorre o ciclo da turma com cada perfil. Resultado esperado: só linhas `ok`.

```bash
createdb portal_teste
for f in 01_imitacao_supabase.sql ../migrations/*.sql 02_dados_ficticios.sql 03_cenario.sql; do
  psql -q -v ON_ERROR_STOP=1 -d portal_teste -f "$f"
done
```
