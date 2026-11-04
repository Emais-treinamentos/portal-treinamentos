import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { dataBR, rpc, useDados } from '../lib/api';
import { supabase } from '../lib/supabase';

const nomes: Record<string, string> = {
  aviso_instrutor: 'Aviso ao instrutor', avaliacao_treinamento: 'Pedido de avaliação ao colaborador', aviso_decisao: 'Aviso de alteração ou decisão', aviso_cancelamento: 'Aviso de cancelamento', lembrete_agenda: 'Lembrete de agenda', lembrete_presenca: 'Lembrete de presença',
  calendario_criar: 'Criar convite no calendário', calendario_atualizar: 'Atualizar convite no calendário', calendario_cancelar: 'Cancelar convite no calendário',
};

export function Envios() {
  const l = useDados(async () => (await supabase.from('notificacoes').select('id, tipo, destinatario, status, tentativas, erro, criado_em, turmas(treinamentos(nome))').order('criado_em', { ascending: false }).limit(200)).data ?? []);
  return (
    <Pagina titulo="Envios" apoio="Fila de avisos e convites. No teste inicial o n8n ainda não está ligado, então tudo fica como pendente.">
      {l.erro && <Mensagem tipo="erro">{l.erro}</Mensagem>}
      {l.carregando && !l.dados && <Carregando />}
      {l.dados && !l.dados.length && <p className="vazio">Nenhum envio ainda.</p>}
      {!!l.dados?.length && <div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Quando</th><th>Tipo</th><th>Para</th><th>Turma</th><th>Situação</th><th /></tr></thead>
        <tbody>{l.dados.map((n) => { const t = n.turmas as unknown as { treinamentos: { nome: string } } | null; return (
          <tr key={n.id}><td>{dataBR(n.criado_em)}</td><td>{nomes[n.tipo] ?? n.tipo}</td><td>{n.destinatario}</td><td>{t?.treinamentos?.nome}</td><td>{n.status}{n.erro ? `: ${n.erro}` : ''}</td>
            <td>{n.status === 'erro' && <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void rpc('reenviar_notificacao', { p_notificacao: n.id }).then(() => l.recarregar())}>Reenviar</button>}</td></tr>
        ); })}</tbody></table></div>}
    </Pagina>
  );
}
