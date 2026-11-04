import { useEffect, useState } from 'react';
import { Navigate, useSearchParams } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, Farol, FormDialogo, SeloSituacao } from '../componentes/Pecas';
import { cargaTexto, dataBR, hora, horaFim, nomesEtapa, nomesStatus, nomesTipoSolicitacao, rpc, textoErro, useDados, type Etapa, type Solicitacao, type TurmaDetalhe } from '../lib/api';
import { gerarListaPresenca } from '../lib/documentos';
import { supabase } from '../lib/supabase';
import { Dialogo } from '../componentes/Dialogo';

type TurmaLinha = { id: string; treinamento: string; etapa: Etapa; status: string; data: string | null; hora: string | null; sala: string | null; instrutor_email: string; participantes: number; solicitacao_aberta: boolean; conflito: boolean; motivo: string | null };
const etapasFormalizar: Etapa[] = ['a_planejar', 'aguardando_instrutor', 'formalizar'];
const etapasAcompanhar: Etapa[] = ['agendadas', 'presenca', 'realizadas', 'canceladas'];

export function resumoTurma(t: TurmaLinha) {
  if (t.solicitacao_aberta) return 'Solicitação aberta';
  if (t.conflito) return 'Conflito de agenda';
  if (t.status === 'precisa_replanejar') return t.motivo ?? 'Precisa replanejar';
  if (t.status === 'agenda_confirmada') return t.sala ? 'Pronta para formalizar' : 'Aceite recebido, falta a sala';
  return nomesStatus[t.status];
}
const corTurma = (t: TurmaLinha) => (t.solicitacao_aberta || t.conflito || t.status === 'precisa_replanejar' ? 'vermelho' : t.status === 'agenda_confirmada' && t.sala ? 'verde' : ['realizada'].includes(t.status) ? 'verde' : ['cancelada', 'encerrada'].includes(t.status) ? 'cinza' : 'amarelo');

function useTurmas() {
  return useDados(() => rpc<TurmaLinha[]>('listar_turmas'));
}

// Links antigos e atalhos para uma turma: abre a aba certa conforme a etapa dela.
export function IrParaTurma() {
  const [params] = useSearchParams();
  const turmas = useTurmas();
  const id = params.get('turma');
  if (params.get('etapa') === 'a_planejar') return <Navigate to="/planejar" replace />;
  if (!id) return <Navigate to="/acompanhar" replace />;
  if (!turmas.dados) return turmas.erro ? <Navigate to="/acompanhar" replace /> : <Carregando />;
  const t = turmas.dados.find((x) => x.id === id);
  const aba = t && etapasFormalizar.includes(t.etapa) ? 'formalizar' : 'acompanhar';
  return <Navigate to={`/${aba}?turma=${id}`} replace />;
}

export function Formalizar() {
  const [params] = useSearchParams();
  const [busca, setBusca] = useState('');
  const [sel, setSel] = useState<string | null>(params.get('turma'));
  const turmas = useTurmas();
  const q = busca.trim().toLowerCase();
  const peso = (t: TurmaLinha) => (t.etapa === 'formalizar' ? 0 : 1);
  const lista = (turmas.dados ?? []).filter((t) => etapasFormalizar.includes(t.etapa) && (!q || `${t.treinamento} ${t.instrutor_email}`.toLowerCase().includes(q))).sort((a, b) => peso(a) - peso(b));
  return (
    <Pagina titulo="Formalizar Convites" apoio="Revise os treinamentos consolidados, verifique conflitos e confirme o envio.">
      {turmas.erro && <Mensagem tipo="erro">{turmas.erro}</Mensagem>}
      {turmas.carregando && !turmas.dados && <Carregando />}
      <div className="mestre-detalhe">
        <div>
          <label className="campo campo-busca"><span className="sr">Buscar</span><input type="search" placeholder="Buscar treinamento ou instrutor" value={busca} onChange={(e) => setBusca(e.target.value)} /></label>
          <div className="lista-turmas">
            {turmas.dados && !lista.length && <p className="vazio">Nenhum convite a formalizar.</p>}
            {lista.map((t) => (
              <button key={t.id} type="button" className="item-lista" aria-current={sel === t.id} onClick={() => setSel(t.id)}>
                <Farol cor={corTurma(t)} />
                <span><strong>{t.treinamento}</strong><small>{resumoTurma(t)}</small><small>{dataBR(t.data)} {hora(t.hora)} · {t.instrutor_email}</small></span>
                <small>{t.participantes} pessoa(s)</small>
              </button>
            ))}
          </div>
        </div>
        {sel ? <PainelTurma id={sel} admin aoMudar={() => void turmas.recarregar()} /> : <p className="vazio">Escolha um treinamento para ver os detalhes.</p>}
      </div>
    </Pagina>
  );
}

export function Acompanhar() {
  const [params, setParams] = useSearchParams();
  const [etapa, setEtapa] = useState<Etapa>('agendadas');
  const [sel, setSel] = useState<string | null>(params.get('turma'));
  const turmas = useTurmas();
  useEffect(() => {
    const t = turmas.dados?.find((x) => x.id === params.get('turma'));
    if (t) { if (etapasAcompanhar.includes(t.etapa)) setEtapa(t.etapa); setSel(t.id); setParams({}, { replace: true }); }
  }, [params, turmas.dados, setParams]);
  const conta = (e: Etapa) => (turmas.dados ?? []).filter((t) => t.etapa === e).length;
  const linhas = (turmas.dados ?? []).filter((t) => t.etapa === etapa);
  return (
    <Pagina titulo="Acompanhar Treinamentos" apoio="Treinamentos confirmados: execução, presença e resultado.">
      {turmas.erro && <Mensagem tipo="erro">{turmas.erro}</Mensagem>}
      <div className="chips chips-filtro" role="group" aria-label="Situação">
        {etapasAcompanhar.map((e) => <button key={e} type="button" className="chip" aria-pressed={etapa === e} onClick={() => { setEtapa(e); void turmas.recarregar(); }}>{nomesEtapa[e]}<small>{conta(e)}</small></button>)}
      </div>
      {turmas.carregando && !turmas.dados && <Carregando />}
      {turmas.dados && (
        <div className="tabela-rolagem">
          <table className="tabela">
            <thead><tr><th>Treinamento e instrutor</th><th>Data e horário</th><th>Sala</th><th>Pessoas</th><th>Status</th><th>Ações</th></tr></thead>
            <tbody>
              {!linhas.length && <tr><td colSpan={6}>Nenhum treinamento nesta situação.</td></tr>}
              {linhas.map((t) => (
                <tr key={t.id}>
                  <td><strong className="celula-nome">{t.treinamento}</strong><small className="celula-apoio">{t.instrutor_email}</small></td><td className="celula-sem-quebra">{dataBR(t.data)} {hora(t.hora)}</td><td>{t.sala}</td><td>{t.participantes}</td>
                  <td><Farol cor={corTurma(t)} /> {resumoTurma(t)}</td>
                  <td><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => setSel(t.id)}>Ver</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {sel && <Dialogo aberto titulo="Treinamento" largura="larga" aoFechar={() => { setSel(null); void turmas.recarregar(); }}><PainelTurma id={sel} admin aoMudar={() => void turmas.recarregar()} /></Dialogo>}
    </Pagina>
  );
}

export function PainelTurma({ id, admin, aoMudar }: { id: string; admin: boolean; aoMudar: () => void }) {
  const d = useDados(() => rpc<TurmaDetalhe>('turma_detalhe', { p_turma: id }), [id]);
  const salas = useDados(async () => JSON.parse((await supabase.from('parametros').select('valor').eq('chave', 'salas').single()).data?.valor ?? '[]') as string[]);
  const [erro, setErro] = useState<string | null>(null);
  const [janela, setJanela] = useState<'alterar' | 'cancelar' | 'incluir' | Solicitacao | null>(null);
  const t = d.dados;
  async function acao(f: () => Promise<unknown>) {
    setErro(null);
    try { await f(); } catch (e) { setErro(textoErro(e)); }
    await d.recarregar();
    aoMudar();
  }
  if (!t) return d.erro ? <Mensagem tipo="erro">{d.erro}</Mensagem> : <Carregando />;
  const aberta = ['aguardando_instrutor', 'agenda_confirmada', 'precisa_replanejar', 'convite_enviado'].includes(t.status);
  const solicitacoes = t.solicitacoes.filter((s) => s.status === 'aberta');
  const h = t.hora_inicio ?? t.hora_opcao_1;
  const pessoas = t.participantes.filter((p) => p.situacao !== 'nao_aplicavel');
  const podeFormalizar = t.status === 'agenda_confirmada' && !!t.sala && !solicitacoes.length && !t.conflitos.length && pessoas.length > 0;
  return (
    <aside className="painel" aria-label="Detalhe da turma">
      <h2>{t.treinamento}</h2>
      <dl className="dados">
        <div><dt>Situação</dt><dd>{nomesStatus[t.status]}</dd></div>
        <div><dt>Data</dt><dd>{dataBR(t.data)}</dd></div>
        <div><dt>Horário</dt><dd>{t.hora_inicio ? `${hora(h)} às ${horaFim(h, t.carga_minutos)}` : [hora(t.hora_opcao_1), hora(t.hora_opcao_2)].filter(Boolean).join(' ou ')}</dd></div>
        <div><dt>Carga</dt><dd>{cargaTexto(t.carga_minutos)}</dd></div>
        <div><dt>Instrutor</dt><dd>{t.instrutor_email}</dd></div>
        <div><dt>Sala</dt><dd>{t.sala ?? 'Não definida'}</dd></div>
      </dl>
      {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
      {!t.instrutor_tem_acesso && aberta && <p className="aviso aviso-alerta">Este instrutor ainda não tem acesso ao portal. Crie em Acessos para ele responder.</p>}
      {t.motivo_replanejamento && <p className="aviso aviso-alerta">{t.motivo_replanejamento}</p>}
      {t.conflitos.map((c, i) => <p className="aviso aviso-erro" key={i}>Conflito de {c.tipo} com {c.treinamento}.</p>)}
      {solicitacoes.map((s) => (
        <div className="aviso aviso-info" key={s.id}>
          <strong>{nomesTipoSolicitacao[s.tipo]}:</strong> {s.motivo}
          {(s.proposta.data || s.proposta.hora) && <div>Proposta: {dataBR(s.proposta.data)} {s.proposta.hora ?? ''}</div>}
          {admin && <div className="linha-acoes"><button className="botao botao-pequeno" type="button" onClick={() => setJanela(s)}>Decidir</button></div>}
        </div>
      ))}
      {admin && aberta && t.status !== 'convite_enviado' && (
        <Campo rotulo="Sala"><select value={t.sala ?? ''} onChange={(e) => void acao(() => rpc('definir_sala', { p_turma: t.id, p_sala: e.target.value }))}><option value="">Escolher sala</option>{(salas.dados ?? []).map((s) => <option key={s}>{s}</option>)}</select></Campo>
      )}
      {admin && aberta && (
        <fieldset className="campo-grupo"><legend>Cargos da turma</legend>
          {t.cargos.map((c) => (
            <label className="opcao" key={c.cargo_id}>
              <input type="checkbox" checked={c.incluir} onChange={(e) => void acao(() => rpc('alternar_cargo_turma', { p_turma: t.id, p_cargo: c.cargo_id, p_incluir: e.target.checked }))} />
              {c.nome} {c.incluir && c.elegiveis === 0 && <span className="aviso-cargo">(cargo sem elegível)</span>}
            </label>
          ))}
        </fieldset>
      )}
      <div>
        <h3>{t.status === 'realizada' || t.status === 'encerrada' ? 'Participantes' : 'Quem será convocado'} ({pessoas.length})</h3>
        {!pessoas.length && <p className="apoio">Nenhuma pessoa elegível no momento.</p>}
        {pessoas.map((p) => (
          <div className="pessoa" key={p.colaborador_id}>
            <span>{p.nome}<small>{p.cargo}{p.origem === 'manual' ? ' · incluído manualmente' : ''}</small></span>
            <span className="linha-acoes">
              <SeloSituacao situacao={p.situacao} />
              {admin && aberta && p.situacao === 'convocado' && <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void acao(() => rpc('ajustar_participante', { p_turma: t.id, p_colaborador: p.colaborador_id, p_incluir: false }))}>Retirar</button>}
            </span>
          </div>
        ))}
      </div>
      {admin && (
        <div className="linha-acoes">
          {t.status === 'agenda_confirmada' && <button className="botao" type="button" disabled={!podeFormalizar} title={podeFormalizar ? '' : 'Precisa de aceite, sala, ao menos uma pessoa e nenhum conflito'} onClick={() => void acao(() => rpc('formalizar_turma', { p_turma: t.id }))}>Formalizar</button>}
          {aberta && <button className="botao botao-secundario" type="button" onClick={() => setJanela('alterar')}>{t.status === 'precisa_replanejar' ? 'Replanejar' : 'Alterar'}</button>}
          {aberta && <button className="botao botao-secundario" type="button" onClick={() => setJanela('incluir')}>Incluir pessoa</button>}
          {pessoas.length > 0 && <button className="botao botao-secundario" type="button" onClick={() => void gerarListaPresenca(t)}>Lista de presença</button>}
          {(aberta || t.status === 'pendente') && <button className="botao botao-discreto" type="button" onClick={() => setJanela('cancelar')}>Cancelar turma</button>}
        </div>
      )}
      {janela === 'alterar' && <AlterarTurma t={t} salas={salas.dados ?? []} aoFechar={() => setJanela(null)} aoSalvar={() => { void d.recarregar(); aoMudar(); }} />}
      {janela === 'cancelar' && <CancelarTurma id={t.id} aoFechar={() => setJanela(null)} aoSalvar={() => { void d.recarregar(); aoMudar(); }} />}
      {janela === 'incluir' && <IncluirPessoa id={t.id} jaNaLista={pessoas.map((p) => p.colaborador_id)} aoFechar={() => setJanela(null)} aoSalvar={() => { void d.recarregar(); aoMudar(); }} />}
      {typeof janela === 'object' && janela && <DecidirSolicitacao s={janela} aoFechar={() => setJanela(null)} aoSalvar={() => { void d.recarregar(); aoMudar(); }} />}
    </aside>
  );
}

function AlterarTurma({ t, salas, aoFechar, aoSalvar }: { t: TurmaDetalhe; salas: string[]; aoFechar: () => void; aoSalvar: () => void }) {
  const [data, setData] = useState(t.data ?? '');
  const [h, setH] = useState(hora(t.hora_inicio ?? t.hora_opcao_1));
  const [sala, setSala] = useState(t.sala ?? '');
  const [email, setEmail] = useState(t.instrutor_email);
  const [motivo, setMotivo] = useState('');
  return (
    <FormDialogo titulo="Alterar turma" rotulo="Salvar alteração" aoFechar={aoFechar}
      aoEnviar={async () => { await rpc('alterar_turma', { p_turma: t.id, p_data: data || null, p_hora: h || null, p_sala: sala || null, p_instrutor_email: email, p_motivo: motivo }); aoSalvar(); }}>
      <p className="apoio">A turma continua a mesma. O instrutor recebe um aviso, e o convite do calendário é atualizado se já tiver saído.</p>
      <div className="grade-2">
        <Campo rotulo="Data"><input type="date" value={data} onChange={(e) => setData(e.target.value)} /></Campo>
        <Campo rotulo="Horário"><input type="time" value={h} onChange={(e) => setH(e.target.value)} /></Campo>
        <Campo rotulo="Sala"><select value={sala} onChange={(e) => setSala(e.target.value)}><option value="">Não definida</option>{salas.map((s) => <option key={s}>{s}</option>)}</select></Campo>
        <Campo rotulo="E-mail do instrutor"><input type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
      </div>
      <Campo rotulo="Motivo"><textarea required rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
    </FormDialogo>
  );
}

function CancelarTurma({ id, aoFechar, aoSalvar }: { id: string; aoFechar: () => void; aoSalvar: () => void }) {
  const [motivo, setMotivo] = useState('');
  return (
    <FormDialogo titulo="Cancelar turma" rotulo="Cancelar a turma" perigo aoFechar={aoFechar} desabilitar={!motivo.trim()} aoEnviar={async () => { await rpc('cancelar_turma', { p_turma: id, p_motivo: motivo }); aoSalvar(); }}>
      <p className="apoio">O instrutor é avisado, o convite é cancelado e os avisos pendentes desta turma deixam de sair.</p>
      <Campo rotulo="Motivo"><textarea required rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
    </FormDialogo>
  );
}

function IncluirPessoa({ id, jaNaLista, aoFechar, aoSalvar }: { id: string; jaNaLista: string[]; aoFechar: () => void; aoSalvar: () => void }) {
  const pessoas = useDados(async () => (await supabase.from('colaboradores').select('id, nome').eq('ativo', true).order('nome')).data ?? []);
  const [pessoa, setPessoa] = useState('');
  return (
    <FormDialogo titulo="Incluir pessoa na turma" rotulo="Incluir" aoFechar={aoFechar} desabilitar={!pessoa} aoEnviar={async () => { await rpc('ajustar_participante', { p_turma: id, p_colaborador: pessoa, p_incluir: true }); aoSalvar(); }}>
      <Campo rotulo="Pessoa"><select value={pessoa} onChange={(e) => setPessoa(e.target.value)}><option value="">Escolha</option>{(pessoas.dados ?? []).filter((p) => !jaNaLista.includes(p.id)).map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}</select></Campo>
    </FormDialogo>
  );
}

function DecidirSolicitacao({ s, aoFechar, aoSalvar }: { s: Solicitacao; aoFechar: () => void; aoSalvar: () => void }) {
  const [aprovar, setAprovar] = useState(true);
  const [resposta, setResposta] = useState('');
  return (
    <FormDialogo titulo={`Solicitação: ${nomesTipoSolicitacao[s.tipo]}`} rotulo="Confirmar decisão" aoFechar={aoFechar} aoEnviar={async () => { await rpc('decidir_solicitacao', { p_solicitacao: s.id, p_aprovar: aprovar, p_resposta: resposta || null }); aoSalvar(); }}>
      <p>{s.motivo}</p>
      {(s.proposta.data || s.proposta.hora) && <p>Proposta: {dataBR(s.proposta.data)} {s.proposta.hora ?? ''}</p>}
      <div className="linha-acoes">
        <label className="opcao"><input type="radio" checked={aprovar} onChange={() => setAprovar(true)} />Aprovar</label>
        <label className="opcao"><input type="radio" checked={!aprovar} onChange={() => setAprovar(false)} />Recusar</label>
      </div>
      <Campo rotulo="Resposta ao instrutor (opcional)"><textarea rows={2} value={resposta} onChange={(e) => setResposta(e.target.value)} /></Campo>
    </FormDialogo>
  );
}
