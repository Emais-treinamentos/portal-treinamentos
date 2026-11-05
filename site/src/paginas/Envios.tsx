import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { dataBR, rpc, useDados } from '../lib/api';
import { supabase } from '../lib/supabase';

const nomes: Record<string, string> = {
  aviso_instrutor: 'Confirmar agenda', lembrete_1h: 'Lembrete antes do treinamento', aviso_presenca: 'Confirmar presença', lembrete_agenda: 'Agenda sem resposta', lembrete_presenca: 'Presença pendente', aviso_decisao: 'Treinamento atualizado', aviso_cancelamento: 'Treinamento cancelado',
  avaliacao_treinamento: 'Avaliar o treinamento', assinatura_solicitada: 'Assinar documento', assinatura_concluida: 'Documento assinado',
};

export function Envios() {
  const l = useDados(async () => (await supabase.from('notificacoes').select('id, tipo, destinatario, status, tentativas, erro, criado_em, turmas(treinamentos(nome))').order('criado_em', { ascending: false }).limit(200)).data ?? []);
  return (
    <Pagina titulo="Envios" apoio="Fila de e-mails. Enquanto o n8n não estiver ligado, tudo fica como pendente. Os textos ficam em Acessos, na aba E-mails.">
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
