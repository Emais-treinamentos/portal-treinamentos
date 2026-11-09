-- Reciclagem: vale o treinamento feito a partir da movimentação, e não só depois do registro da decisão.
create or replace function app.exigido_por_decisao(p_colaborador uuid, p_treinamento uuid) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare d reciclagem_decisoes; c uuid;
begin
  d := app.decisao_vigente(p_colaborador);
  if d.id is null or d.acao_final = 'dispensa' then return false; end if;
  if d.acao_final = 'parcial' and not (p_treinamento = any (d.treinamentos_parcial)) then return false; end if;
  if d.acao_final = 'total' then
    select cargo_id into c from colaboradores where id = p_colaborador;
    if not exists (select 1 from matriz_vigente_em(c, app.hoje()) m where m.treinamento_id = p_treinamento) then return false; end if;
  end if;
  return coalesce(app.ultima_realizacao(p_colaborador, p_treinamento)
                  < least(coalesce(app.data_referencia(p_colaborador), (d.decidido_em at time zone 'America/Sao_Paulo')::date),
                          (d.decidido_em at time zone 'America/Sao_Paulo')::date), true);
end $$;
