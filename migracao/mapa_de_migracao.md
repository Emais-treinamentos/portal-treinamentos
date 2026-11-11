# Mapa de migração: banco atual para o portal novo

Extração feita em 05/11/2026, só com SELECT (`extracao_somente_leitura.sql`). Nada foi gravado no banco atual.
O arquivo extraído tem nomes e e-mails. Ele não entra no repositório.

## O que vai para onde

| Banco atual | Linhas | Portal novo | Regra |
| --- | --- | --- | --- |
| departamentos | 30 | departamentos | Mantém o id |
| cargos | 272 | cargos | Mantém o id. 1 cargo está sem departamento e o novo exige um |
| treinamentos | 166 | treinamentos | carga_horaria HH:MM vira minutos. Cargo do instrutor e departamento são procurados pelo nome |
| colaboradores | 60 | colaboradores | Mantém o id |
| historico_cargos | 106 | movimentacoes | 8 linhas apontam para colaborador que não existe mais e ficam de fora |
| matriz_revisoes | 26 | matriz_revisoes | Mantém número, status e vigência |
| cargos_treinamentos | 5.837 | matriz_vinculos | Mantém revisão de criação e de remoção |
| planejamentos | 406 | turmas (406) | Cada planejamento vira uma turma, porque em 34 dos 54 grupos consolidados a data ou o horário variam |
| planejamento_cargos | 802 | turma_cargos | Cargos de cada turma |
| presenca_colaborador | 707 | turma_participantes | confirmado vira presente. ausente continua ausente. Origem legado_individual |
| confirmacao_treinamento | 699 | Só conferência | Toda confirmação com pessoa já está na presença. As outras 280 são por cargo |
| reciclagem_decisoes | 10 | reciclagem_decisoes | Só as 6 confirmadas. As 4 pendentes o portal recalcula |
| profiles, matriz_temp | | Não migram | Os acessos são criados de novo |

## Status das turmas

| Banco atual | Linhas | Portal novo |
| --- | --- | --- |
| realizado | 342 | realizada |
| encerrado | 37 | encerrada |
| cancelado | 7 | cancelada |
| convite_enviado | 8 | A decidir, todas com data passada |
| agenda_confirmada | 7 | A decidir, todas com data passada |
| aguardando_resposta_instrutor | 4 | A decidir, todas com data passada |
| aguardando_reagendamento | 1 | A decidir, data passada |

## O que validar antes da inclusão

1. As 20 turmas abertas com data passada. Precisa decidir uma a uma, para não disparar lembrete antigo ao ligar o n8n.
2. 22 turmas realizadas ou encerradas sem nenhuma presença.
3. 8 registros de presença sem colaborador válido (5 sem pessoa e 3 de colaborador excluído) e 1 de planejamento excluído.
4. 56 treinamentos com cargo do instrutor sem cargo de nome igual e 28 com departamento sem nome igual.
5. 8 e-mails repetidos entre colaboradores. Só um usuário pode entrar com cada e-mail.
6. Os códigos de assinatura antigos não migram. Cada pessoa presente ganha um código novo, então um PDF já arquivado mantém o código antigo.

## Ordem da inclusão

1. Reconectar o Supabase do banco novo e aplicar a migração 012.
2. Limpar os dados de teste do banco novo, com aprovação.
3. Incluir na ordem da tabela acima, sem gerar e-mail.
4. Conferir as contagens contra este mapa.
5. Limpar a fila de envios e só então ligar o n8n.

## Sincronização de 11/11/2026

Nova extração só de leitura do banco atual, comparada com a de 05/11. Cadastros, cargos, matriz, movimentações e reciclagens não mudaram. Entraram só os treinamentos de admissão de 2 colaboradores (Corretor de Incorporação e Assistente Jurídico).

| Banco atual | Novos | Portal novo | Regra |
| --- | --- | --- | --- |
| planejamentos | 28 | turmas (25) | Mantém o id do planejamento. Quando o mesmo treinamento foi remarcado, vale o planejamento criado por último (3 versões anteriores ficam de fora) |
| planejamento_cargos | 37 | turma_cargos (32) | Cargo ligado pelo nome |
| presenca_colaborador | 23 | turma_participantes (20) | Colaborador ligado pelo nome. As 3 presenças das versões anteriores ficam de fora |
| confirmacao_treinamento | 23 | Só conferência | |

- Turma aguardando o instrutor usa a data sugerida.
- Turmas abertas recebem os convocados pelo cálculo do portal.
- As convocações geradas na inclusão foram canceladas, porque o banco atual já tinha enviado os convites.
- A carga de 05/11 gerou ids novos para cargos e colaboradores. Por isso a ligação é feita pelo nome, com checagem de par único.
