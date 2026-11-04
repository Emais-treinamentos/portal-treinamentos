import { useState } from 'react';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, Farol, FormDialogo, SeloSituacao } from '../componentes/Pecas';
import { cargaTexto, dataBR, hora, horaFim, nomesStatus, nomesTipoSolicitacao, rpc, textoErro, useDados, type TurmaDetalhe } from '../lib/api';

type Minha = { id: string; treinamento: string; status: string; etapa: string; data: string | null; hora: string | null; sala: string | null; participantes: number; pendentes: number; solicitacao_aberta: boolean };

const grupos: [string, string, string[]][] = [
  ['confirmar', 'Confirmar agenda', ['aguardando_instrutor']], ['presenca', 'Registrar presença', ['presenca']], ['agendadas', 'Agendadas', ['agendadas', 'formalizar']], ['realizadas', 'Realizadas', ['realizadas']],
];

export function MinhasTurmas() {
  const lista = useDados(() => rpc<Minha[]>('minhas_turmas'));
  const [sel, setSel] = useState<string | null>(null);
  return (
    <Pagina titulo="Minhas turmas" apoio="Confirme a agenda, peça alterações e registre a presença por aqui. Os dados são sempre os atuais da turma.">
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {lista.carregando && !lista.dados && <Carregando />}
      {lista.dados && !lista.dados.length && <p className="vazio">Você não tem turmas como instrutor.</p>}
      {!!lista.dados?.length && (
        <div className="mestre-detalhe">
          <div>
            {grupos.map(([g, nome, es]) => {
              const itens = lista.dados!.filter((t) => es.includes(t.etapa));
              if (!itens.length) return null;
              return (
                <section key={g}>
                  <p className="grupo-titulo">{nome} ({itens.length})</p>
                  <div className="lista-turmas">
                    {itens.map((t) => (
                      <button key={t.id} type="button" className="item-lista" aria-current={sel === t.id} onClick={() => setSel(t.id)}>
                        <Farol cor={g === 'realizadas' ? 'verde' : g === 'agendadas' ? 'cinza' : 'amarelo'} />
                        <span><strong>{t.treinamento}</strong><small>{dataBR(t.data)} {hora(t.hora)}{t.sala ? ` · ${t.sala}` : ''}</small>{t.solicitacao_aberta && <small>Solicitação em análise</small>}</span>
                        <small>{t.participantes} pessoa(s)</small>
                      </button>
                    ))}
                  </div>
                </section>
              );
            })}
          </div>
          {sel ? <PainelInstrutor id={sel} aoMudar={() => void lista.recarregar()} /> : <p className="vazio">Escolha uma turma.</p>}
        </div>
      )}
    </Pagina>
  );
}

function PainelInstrutor({ id, aoMudar }: { id: string; aoMudar: () => void }) {
  const d = useDados(() => rpc<TurmaDetalhe>('turma_detalhe', { p_turma: id }), [id]);
  const [erro, setErro] = useState<string | null>(null);
  const [janela, setJanela] = useState<'propor' | 'recusar' | 'solicitar' | null>(null);
  const t = d.dados;
  async function acao(f: () => Promise<unknown>) {
    setErro(null);
    try { await f(); } catch (e) { setErro(textoErro(e)); }
    await d.recarregar();
    aoMudar();
  }
  if (!t) return d.erro ? <Mensagem tipo="erro">{d.erro}</Mensagem> : <Carregando />;
  const h = t.hora_inicio ?? t.hora_opcao_1;
  const pessoas = t.participantes.filter((p) => p.situacao !== 'nao_aplicavel');
  const aberta = t.solicitacoes.find((s) => s.status === 'aberta');
  const ultima = t.solicitacoes.find((s) => s.status !== 'aberta');
  const presenca = t.etapa === 'presenca';
  const faltam = pessoas.filter((p) => p.situacao === 'convocado').length;
  const recarregar = () => { void d.recarregar(); aoMudar(); };
  return (
    <aside className="painel" aria-label="Detalhe da turma">
      <h2>{t.treinamento}</h2>
      <dl className="dados">
        <div><dt>Situação</dt><dd>{nomesStatus[t.status]}</dd></div>
        <div><dt>Data</dt><dd>{dataBR(t.data)}</dd></div>
        <div><dt>Horário</dt><dd>{t.hora_inicio ? `${hora(h)} às ${horaFim(h, t.carga_minutos)}` : 'A confirmar'}</dd></div>
        <div><dt>Carga</dt><dd>{cargaTexto(t.carga_minutos)}</dd></div>
        <div><dt>Sala</dt><dd>{t.sala ?? 'A definir'}</dd></div>
      </dl>
      {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
      {aberta && <p className="aviso aviso-info">Sua solicitação de {nomesTipoSolicitacao[aberta.tipo].toLowerCase()} está com Gente e Gestão.</p>}
      {ultima && !aberta && <p className="aviso aviso-info">Última solicitação {ultima.status === 'aprovada' ? 'aprovada' : 'recusada'}{ultima.resposta ? `: ${ultima.resposta}` : ''}.</p>}

      {t.status === 'aguardando_instrutor' && !aberta && (
        <div className="detalhe">
          <h3>Você pode aplicar este treinamento?</h3>
          <div className="linha-acoes">
            {[t.hora_opcao_1, t.hora_opcao_2].filter(Boolean).map((op) => <button key={op} className="botao" type="button" onClick={() => void acao(() => rpc('responder_agenda', { p_turma: t.id, p_acao: 'aceitar', p_hora: op }))}>Confirmar {hora(op)}</button>)}
          </div>
          <div className="linha-acoes">
            <button className="botao botao-secundario" type="button" onClick={() => setJanela('propor')}>Propor outro horário</button>
            <button className="botao botao-discreto" type="button" onClick={() => setJanela('recusar')}>Recusar</button>
          </div>
        </div>
      )}

      <div>
        <h3>{presenca ? `Quem participou? (${pessoas.length - faltam} de ${pessoas.length} marcados)` : `Participantes (${pessoas.length})`}</h3>
        {!pessoas.length && <p className="apoio">Nenhuma pessoa na lista no momento.</p>}
        {pessoas.map((p) => (
          <div className="pessoa" key={p.colaborador_id}>
            <span>{p.nome}<small>{p.cargo}</small></span>
            {presenca ? (
              <span className="alternar">
                <button type="button" className="presente" aria-pressed={p.situacao === 'presente'} onClick={() => void acao(() => rpc('marcar_presenca', { p_turma: t.id, p_colaborador: p.colaborador_id, p_situacao: 'presente' }))}>Presente</button>
                <button type="button" className="ausente" aria-pressed={p.situacao === 'ausente'} onClick={() => void acao(() => rpc('marcar_presenca', { p_turma: t.id, p_colaborador: p.colaborador_id, p_situacao: 'ausente' }))}>Ausente</button>
              </span>
            ) : <SeloSituacao situacao={p.situacao} />}
          </div>
        ))}
      </div>
      {presenca && <p className="apoio">Pode corrigir até concluir. Nenhuma marcação se perde.</p>}
      <div className="linha-acoes">
        {presenca && <button className="botao" type="button" disabled={faltam > 0 || !pessoas.length} onClick={() => void acao(() => rpc('concluir_presenca', { p_turma: t.id }))}>Concluir presença</button>}
        {!aberta && t.status !== 'cancelada' && t.status !== 'aguardando_instrutor' && <button className="botao botao-secundario" type="button" onClick={() => setJanela('solicitar')}>{t.presenca_concluida_em ? 'Solicitar correção' : 'Solicitar alteração'}</button>}
      </div>
      {janela === 'propor' && <Propor id={t.id} aoFechar={() => setJanela(null)} aoSalvar={recarregar} />}
      {janela === 'recusar' && <Recusar id={t.id} aoFechar={() => setJanela(null)} aoSalvar={recarregar} />}
      {janela === 'solicitar' && <Solicitar t={t} aoFechar={() => setJanela(null)} aoSalvar={recarregar} />}
    </aside>
  );
}

function Propor({ id, aoFechar, aoSalvar }: { id: string; aoFechar: () => void; aoSalvar: () => void }) {
  const [data, setData] = useState(''); const [h, setH] = useState(''); const [motivo, setMotivo] = useState('');
  return (
    <FormDialogo titulo="Propor outro horário" rotulo="Enviar a Gente e Gestão" aoFechar={aoFechar} aoEnviar={async () => { await rpc('responder_agenda', { p_turma: id, p_acao: 'propor', p_hora: h || null, p_nova_data: data || null, p_motivo: motivo }); aoSalvar(); }}>
      <div className="grade-2">
        <Campo rotulo="Nova data"><input type="date" value={data} onChange={(e) => setData(e.target.value)} /></Campo>
        <Campo rotulo="Novo horário"><input type="time" value={h} onChange={(e) => setH(e.target.value)} /></Campo>
      </div>
      <Campo rotulo="Motivo"><textarea required rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
    </FormDialogo>
  );
}

function Recusar({ id, aoFechar, aoSalvar }: { id: string; aoFechar: () => void; aoSalvar: () => void }) {
  const [motivo, setMotivo] = useState('');
  return (
    <FormDialogo titulo="Recusar a turma" rotulo="Recusar" perigo aoFechar={aoFechar} desabilitar={!motivo.trim()} aoEnviar={async () => { await rpc('responder_agenda', { p_turma: id, p_acao: 'recusar', p_motivo: motivo }); aoSalvar(); }}>
      <p className="apoio">Gente e Gestão vê o motivo e replaneja a turma.</p>
      <Campo rotulo="Motivo"><textarea required rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
    </FormDialogo>
  );
}

function Solicitar({ t, aoFechar, aoSalvar }: { t: TurmaDetalhe; aoFechar: () => void; aoSalvar: () => void }) {
  const concluida = !!t.presenca_concluida_em;
  const [tipo, setTipo] = useState(concluida ? 'correcao_presenca' : 'alteracao');
  const [data, setData] = useState(''); const [h, setH] = useState(''); const [motivo, setMotivo] = useState('');
  return (
    <FormDialogo titulo={concluida ? 'Solicitar correção' : 'Solicitar alteração'} rotulo="Enviar a Gente e Gestão" aoFechar={aoFechar} desabilitar={!motivo.trim()}
      aoEnviar={async () => { await rpc('solicitar_alteracao', { p_turma: t.id, p_tipo: tipo, p_motivo: motivo, p_proposta: tipo === 'alteracao' ? { ...(data ? { data } : {}), ...(h ? { hora: h } : {}) } : {} }); aoSalvar(); }}>
      {!concluida && <Campo rotulo="O que você precisa?"><select value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="alteracao">Mudar data ou horário</option><option value="cancelamento">Cancelar a turma</option></select></Campo>}
      {tipo === 'alteracao' && <div className="grade-2"><Campo rotulo="Nova data"><input type="date" value={data} onChange={(e) => setData(e.target.value)} /></Campo><Campo rotulo="Novo horário"><input type="time" value={h} onChange={(e) => setH(e.target.value)} /></Campo></div>}
      <Campo rotulo="Motivo"><textarea required rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
    </FormDialogo>
  );
}
