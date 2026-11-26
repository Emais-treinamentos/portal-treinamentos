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

## Sincronização de 19/11/2026

Leitura feita no SQL Editor do banco atual, só com consultas de leitura, comparando com a foto de 11/11 por assinatura (md5) de cada tabela e de cada registro. Cadastros, cargos, matriz, movimentações e reciclagens não mudaram. Mudaram só as turmas incluídas em 11/11:

- 7 turmas passaram para realizada, com a presença e o horário registrados no banco atual. As avaliações de satisfação foram geradas no portal.
- Con1 - Consultivo: agenda confirmada pelo instrutor (17/11, 15:00), sem convite enviado.
- LGPD: data recusada pelo instrutor, turma marcada para replanejar.

## Baixas de 23/11/2026 (pedido de Gente e Gestão)

- Código de Ética de 13/11: Luiz Fernando e Vitor presentes, turma realizada às 11h.
- LGPD e Consultivo remarcados para 24/11 (14h e 15h). Consultivo só com o Vitor.
- Regra: treinamento da lista de uma reciclagem parcial só conta se estiver na matriz vigente na data de referência (migração 026). Tirou o POP indevido de Bruno, Francieli e Marcos.
- Presenças informadas por Gente e Gestão gravadas para Daniela, Francieli, Gabriel, Gabriela, José Kemyson, Maria Clara e Taissa. Onde não havia turma realizada na data, foi criada uma turma realizada com o instrutor usual do treinamento.
- Maria Luiza e Renan: reciclagem passou para dispensa (termos assinados fora do portal em 12/08 e 08/06).
- Gabriele Corrêa Trovó: cadastro inativado no portal por ter sido usado como teste.
- E-mails de convocação e avaliação dessas baixas foram cancelados. Ficaram só os pedidos de assinatura da lista de presença.
- Ajustes de 23/11 (tarde): Consultivo de 24/11 com o Luiz (conforme a matriz), sem o Vitor. Boas Vindas Área do Gabriel com a Marcela Zanateli. Turmas abertas do Rodrigo (Código de Ética 20/10 e Boas Vindas Área 07/10) concluídas com presença.
- Regra: cargo sem matriz na data de referência passa a usar a primeira matriz publicada para o cargo (migração 027). Caso da Maria Clara.
- 11 turmas antigas (junho a outubro) sem convocados foram canceladas direto no banco, sem e-mail. As realizações dessas pessoas já estavam na lista de presença.

## Turma online pelo Teams (26/11/2026)

- Sala "Online (Teams)" marca a turma como online. Ela não disputa sala com outras turmas.
- Fila calendario_eventos: o banco decide sozinho se falta criar, atualizar ou cancelar o evento do Outlook a cada mudança na turma ou nos participantes.
- Fluxo do n8n "Portal de Treinamentos - Calendário Teams" (a cada 5 minutos): busca a fila, cria, atualiza ou cancela o evento pela API do Microsoft 365 com a credencial "Outlook Treinamentos GG" e devolve o id do evento e o link do Teams.
- Testado em 26/11 com uma turma de teste: criar, atualizar horário e cancelar. A turma de teste foi apagada.
