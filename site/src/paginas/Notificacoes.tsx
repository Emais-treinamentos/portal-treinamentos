import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { dataBR, hora, nomesTipoSolicitacao, rpc, textoErro, useDados } from '../lib/api';
import { avisarNotificacoes } from '../componentes/Topo';

type Participante = { colaborador_id: string; nome: string; situacao: 'presente' | 'ausente' };
type Proposta = { data?: string; hora?: string; sala?: string; instrutor_email?: string; data_anterior?: string; hora_anterior?: string };
type Pedido = { id: string; tipo: string; motivo: string; proposta: Proposta; solicitado_em: string; solicitante: string; turma_id: string; treinamento: string; data: string | null; hora: string | null; sala: string | null; instrutor_email: string; status_turma: string; participantes: Participante[] | null };
type Comentario = { id: string; treinamento: string; data: string | null; instrutor_email: string; nota: number; melhorias: string[]; comentario: string | null; respondido_em: string | null; lido: boolean };
type Historico = { id: string; tipo: string; status: string; motivo: string; resposta: string | null; proposta: Proposta; solicitado_em: string; decidido_em: string; solicitante: string; decidido_por: string | null; automatico: boolean; turma_id: string; treinamento: string; data: string | null };
type Painel = { pedidos: Pedido[]; comentarios: Comentario[]; historico: Historico[] };

const abas = [['pedidos', 'Pedidos dos instrutores'], ['comentarios', 'Comentários dos colaboradores'], ['historico', 'Histórico']] as const;
const quando = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
const textoProposta = (p: Proposta) => [p.data && `data ${dataBR(p.data)}`, p.hora && `horário ${hora(p.hora)}`, p.sala && `sala ${p.sala}`, p.instrutor_email && `instrutor ${p.instrutor_email}`].filter(Boolean).join(', ');

export function Notificacoes() {
  const [aba, setAba] = useState<(typeof abas)[number][0]>('pedidos');
  const d = useDados(() => rpc<Painel>('painel_notificacoes', { p_dias: 60 }), []);
  const [decidir, setDecidir] = useState<Pedido | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const recarregar = () => { void d.recarregar(); avisarNotificacoes(); };
  const naoLidos = (d.dados?.comentarios ?? []).filter((c) => !c.lido);
  const ler = async (ids: string[]) => {
    try { await rpc('marcar_lido', { p_chaves: ids.map((i) => `avaliacao:${i}`) }); recarregar(); } catch (e) { setErro(textoErro(e)); }
  };
  const contagem = { pedidos: d.dados?.pedidos.length ?? 0, comentarios: naoLidos.length, historico: 0 };
  return (
    <Pagina titulo="Notificações" apoio="Pedidos dos instrutores para decidir e comentários das avaliações de satisfação. Mostra os últimos 60 dias.">
      {msg && <Mensagem tipo="ok" aoFechar={() => setMsg(null)}>{msg}</Mensagem>}
      {(erro || d.erro) && <Mensagem tipo="erro" aoFechar={() => setErro(null)}>{erro ?? d.erro}</Mensagem>}
      <div className="chips chips-filtro" role="group" aria-label="Notificações">
        {abas.map(([a, nome]) => <button key={a} type="button" className="chip" aria-pressed={aba === a} onClick={() => setAba(a)}>{nome}{contagem[a] > 0 && <span className="contador">{contagem[a]}</span>}</button>)}
      </div>
      {d.carregando && !d.dados && <Carregando />}

      {d.dados && aba === 'pedidos' && (
        d.dados.pedidos.length ? <div className="lista-avisos">{d.dados.pedidos.map((p) => (
          <article className="cartao-aviso" key={p.id}>
            <header><strong>{nomesTipoSolicitacao[p.tipo] ?? p.tipo}</strong><small>{quando(p.solicitado_em)}</small></header>
            <p className="cartao-aviso-titulo">{p.treinamento}</p>
            <p className="apoio">Turma de {dataBR(p.data)} {hora(p.hora)}{p.sala ? ` · ${p.sala}` : ''} · instrutor {p.instrutor_email}</p>
            <p><span className="apoio">Pedido de {p.solicitante}:</span> {p.motivo}</p>
            {textoProposta(p.proposta) && <p><span className="apoio">Proposta:</span> {textoProposta(p.proposta)}</p>}
            <div className="linha-acoes">
              <button className="botao botao-pequeno" type="button" onClick={() => setDecidir(p)}>{p.tipo === 'correcao_presenca' ? 'Corrigir ou recusar' : 'Decidir'}</button>
              <Link className="botao botao-discreto botao-pequeno" to={`/turmas?turma=${p.turma_id}`}>Ver turma</Link>
            </div>
          </article>
        ))}</div> : <p className="vazio">Nenhum pedido aberto.</p>
      )}

      {d.dados && aba === 'comentarios' && (
        <>
          <p className="apoio">As respostas são anônimas. Aparecem só as avaliações com comentário ou ponto de melhoria.</p>
          {naoLidos.length > 1 && <div className="linha-acoes"><button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void ler(naoLidos.map((c) => c.id))}>Marcar todos como lidos</button></div>}
          {d.dados.comentarios.length ? <div className="lista-avisos">{d.dados.comentarios.map((c) => (
            <article className={`cartao-aviso${c.lido ? ' cartao-lido' : ''}`} key={c.id}>
              <header><strong>{c.treinamento}</strong><small>Nota {c.nota} de 5</small></header>
              <p className="apoio">Turma de {dataBR(c.data)} · instrutor {c.instrutor_email}{c.respondido_em ? ` · respondida em ${dataBR(c.respondido_em)}` : ''}</p>
              {c.comentario && <p className="cartao-aviso-citacao">{c.comentario}</p>}
              {c.melhorias.length > 0 && <div className="chips">{c.melhorias.map((m) => <span className="chip chip-fixo" key={m}>{m}</span>)}</div>}
              {!c.lido && <div className="linha-acoes"><button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void ler([c.id])}>Marcar como lido</button></div>}
            </article>
          ))}</div> : <p className="vazio">Nenhum comentário nos últimos 60 dias.</p>}
        </>
      )}

      {d.dados && aba === 'historico' && (
        d.dados.historico.length ? <div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Decidido em</th><th>Pedido</th><th>Treinamento</th><th>Quem pediu</th><th>Decisão</th></tr></thead>
          <tbody>{d.dados.historico.map((h) => (
            <tr key={h.id}>
              <td>{quando(h.decidido_em)}</td>
              <td><strong className="celula-nome">{nomesTipoSolicitacao[h.tipo] ?? h.tipo}</strong><small className="celula-apoio">{h.motivo}</small></td>
              <td><Link className="link" to={`/turmas?turma=${h.turma_id}`}>{h.treinamento}</Link><small className="celula-apoio">{dataBR(h.data)}</small></td>
              <td>{h.solicitante}</td>
              <td>{h.automatico ? 'Feito pelo instrutor, dentro do prazo' : `${h.status === 'aprovada' ? 'Aprovado' : 'Recusado'}${h.decidido_por ? ` por ${h.decidido_por}` : ''}`}{h.resposta && <small className="celula-apoio">{h.resposta}</small>}</td>
            </tr>
          ))}</tbody></table></div> : <p className="vazio">Nenhum pedido decidido nos últimos 60 dias.</p>
      )}

      {decidir && <DecidirPedido p={decidir} aoFechar={() => setDecidir(null)} aoSalvar={(t) => { setDecidir(null); setMsg(t); recarregar(); }} />}
    </Pagina>
  );
}

function DecidirPedido({ p, aoFechar, aoSalvar }: { p: Pedido; aoFechar: () => void; aoSalvar: (texto: string) => void }) {
  const correcao = p.tipo === 'correcao_presenca';
  const [aprovar, setAprovar] = useState(true);
  const [resposta, setResposta] = useState('');
  const [situacoes, setSituacoes] = useState<Record<string, 'presente' | 'ausente'>>(() => Object.fromEntries((p.participantes ?? []).map((x) => [x.colaborador_id, x.situacao])));
  const mudou = (p.participantes ?? []).filter((x) => situacoes[x.colaborador_id] !== x.situacao);
  return (
    <FormDialogo titulo={`${nomesTipoSolicitacao[p.tipo] ?? p.tipo}: ${p.treinamento}`} rotulo={aprovar ? (correcao ? 'Salvar correção' : 'Aprovar') : 'Recusar'} largura={correcao ? 'larga' : 'normal'}
      desabilitar={correcao && aprovar && !mudou.length} aoFechar={aoFechar}
      aoEnviar={async () => {
        if (correcao) {
          await rpc('decidir_correcao_presenca', { p_solicitacao: p.id, p_aprovar: aprovar, p_resposta: resposta || null, p_correcoes: aprovar ? mudou.map((x) => ({ colaborador_id: x.colaborador_id, situacao: situacoes[x.colaborador_id] })) : [] });
          aoSalvar(aprovar ? `Presença corrigida para ${mudou.length} pessoa(s). O instrutor recebe um aviso.` : 'Pedido recusado. O instrutor recebe um aviso.');
        } else {
          await rpc('decidir_solicitacao', { p_solicitacao: p.id, p_aprovar: aprovar, p_resposta: resposta || null });
          aoSalvar(aprovar ? 'Pedido aprovado e aplicado na turma.' : 'Pedido recusado. O instrutor recebe um aviso.');
        }
      }}>
      <p><span className="apoio">Pedido de {p.solicitante}:</span> {p.motivo}</p>
      {textoProposta(p.proposta) && <p><span className="apoio">Proposta:</span> {textoProposta(p.proposta)}</p>}
      <div className="linha-acoes">
        <label className="opcao"><input type="radio" checked={aprovar} onChange={() => setAprovar(true)} />{correcao ? 'Corrigir a presença' : 'Aprovar'}</label>
        <label className="opcao"><input type="radio" checked={!aprovar} onChange={() => setAprovar(false)} />Recusar</label>
      </div>
      {correcao && aprovar && (
        <fieldset className="campo-grupo"><legend>Presença da turma</legend>
          <p className="apoio">Altere só quem precisa de correção. Cada mudança fica registrada com o motivo do pedido.</p>
          <div className="lista-marcar">
            {(p.participantes ?? []).map((x) => (
              <div className="treino-vinculo" key={x.colaborador_id}>
                <span className="opcao">{x.nome}{situacoes[x.colaborador_id] !== x.situacao && <small className="apoio"> (era {x.situacao})</small>}</span>
                <label className="campo treino-substituto"><span className="sr">Situação de {x.nome}</span>
                  <select value={situacoes[x.colaborador_id]} onChange={(e) => setSituacoes({ ...situacoes, [x.colaborador_id]: e.target.value as 'presente' | 'ausente' })}>
                    <option value="presente">Presente</option><option value="ausente">Ausente</option>
                  </select>
                </label>
              </div>
            ))}
          </div>
        </fieldset>
      )}
      <Campo rotulo="Resposta ao instrutor (opcional)"><textarea rows={2} value={resposta} onChange={(e) => setResposta(e.target.value)} /></Campo>
    </FormDialogo>
  );
}
