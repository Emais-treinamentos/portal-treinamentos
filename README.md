# Portal de Treinamentos

Portal do Grupo Emais para os treinamentos dos colaboradores internos: planejamento, turmas, presença, reciclagem e indicadores.
Sistema separado do Portal de Terceiros, que serviu só de referência de padrão.

- **Banco e login:** Supabase, projeto `ayytbphndmfudxefposk` (São Paulo)
- **Site:** React + Vite, publicado no GitHub Pages em `https://emais-treinamentos.github.io/portal-treinamentos/`

O repositório não guarda dados pessoais, senhas nem chaves secretas. A chave em `site/.env.production` é a pública: quem decide o acesso são as regras do banco.

## Como está organizado

| Pasta | O que tem |
|---|---|
| `supabase/migrations` | Estrutura do banco e regras de negócio, na ordem de aplicação |
| `supabase/functions/gerenciar-acesso` | Cria acessos e gera o link de primeiro acesso ou de nova senha |
| `supabase/testes` | Dados fictícios e cenário do ciclo completo, para rodar num Postgres local |
| `site` | O site |
| `.github/workflows` | Publicação automática a cada atualização da `main`, se o repositório for público |

## Princípios

1. **O banco decide, o site mostra.** Elegibilidade, ciclo da turma, situação por pessoa e reciclagem estão em funções únicas do banco.
2. **O n8n só envia.** Toda ação grava a mudança e a notificação na mesma transação, na tabela `notificacoes`. O n8n busca em `notificacoes_para_envio` e devolve em `registrar_envio`.
3. **O e-mail só avisa.** O instrutor responde, pede alteração e registra presença em Minhas turmas.
4. **A turma mantém o identificador.** Alterar data, horário, sala ou instrutor atualiza a mesma turma. Nova turma só para ausentes.
5. **`turma_participantes` é a fonte da verdade.** Uma linha por pessoa e turma, sempre com colaborador.

## Perfis

| Perfil | Vê e faz |
|---|---|
| Gente e Gestão | Tudo |
| Segurança do Trabalho | Lê turmas, colaboradores e indicadores |
| Gestor | Só os departamentos marcados no acesso, em leitura |
| Colaborador | Os próprios treinamentos e documentos |
| Instrutor | Minhas turmas. Qualquer perfil vê as turmas em que o e-mail dele é o do instrutor |

## Parâmetros

Ficam na tabela `parametros`: janela de convocação (15 dias), prazo de reciclagem (730 dias), meses da regra de políticas, prazos de lembrete e salas.

## Configuração no Supabase (uma vez)

- **Authentication > Sign In / Providers:** desligar **Allow new users to sign up**.
- **Authentication > URL Configuration:** Site URL e Redirect URLs com o endereço do site.
