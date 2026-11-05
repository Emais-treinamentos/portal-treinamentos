-- A regra de Ativos agora vale também para Cadastros.
update public.parametros set rotulo = 'Colaboradores ativos recentes', grupo = 'Colaboradores',
  descricao = 'Dias depois da admissão ou movimentação em que o colaborador fica na aba Ativos, em Cadastros e na Lista de Presença. Depois vai para o Histórico.'
  where chave = 'ativos_lista_dias';
