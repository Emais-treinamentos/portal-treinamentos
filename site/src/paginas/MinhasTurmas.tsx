import { useState } from 'react';
import { Pagina, Mensagem, VoltarLista } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, Farol, FormDialogo, SeloSituacao } from '../componentes/Pecas';
import { Dialogo } from '../componentes/Dialogo';
import { Calendario, type EventoCal } from '../componentes/Calendario';
import { baixarIcs, linkOutlook, type EventoAgenda } from '../lib/calendario';
import { cargaTexto, dataBR, hora, horaFim, nomesStatus, nomesTipoSolicitacao, rpc, textoErro, useDados, type TurmaDetalhe } from '../lib/api';

type Minha = { id: string; treinamento: string; status: string; etapa: string; data: string | null; hora: string | null; sala: string | null; participantes: number; pendentes: number; solicitacao_aberta: boolean };

const grupos: [string, string, string[]][] = [
  ['confirmar', 'Confirmar agenda', ['aguardando_instrutor']], ['presenca', 'Registrar presença', ['presenca']], ['agendadas', 'Agendadas', ['agendadas', 'formalizar']], ['realizadas', 'Realizadas', ['realizadas']],
];

export function MinhasTurmas() {
  return <TurmasInstrutor titulo="Minhas turmas" apoio="Confirme a agenda, remarque e registre a presença por aqui." grupos={grupos} vazio="Você não tem turmas como instrutor." />;
}

export function ConfirmarAgenda() {
  return <TurmasInstrutor titulo="Confirmar Agenda" apoio="Confirme os treinamentos que você vai aplicar, escolha outro horário ou recuse."
    grupos={[['confirmar', 'Aguardando sua confirmação', ['aguardando_instrutor']], ['formalizar', 'Confirmados, aguardando convite', ['formalizar']], ['agendadas', 'Agendados', ['agendadas']]]} vazio="Nenhum treinamento para confirmar." />;
}

export function PresencaInstrutor() {
  return <TurmasInstrutor titulo="Presença" apoio="Marque quem participou. Cada presente recebe um código único, que aparece na lista de presença do colaborador."
    grupos={[['presenca', 'Registrar presença', ['presenca']], ['realizadas', 'Concluídos nos últimos 30 dias', ['realizadas']]]} vazio="Nenhum treinamento com presença a registrar." comHistorico />;
}

// Concluídos há mais de 30 dias vão para a aba Histórico.
const limiteRecentes = () => { const d = new Date(); d.setDate(d.getDate() - 30); return d.toISOString().slice(0, 10); };

function TurmasInstrutor({ titulo, apoio, grupos, vazio, comHistorico }: { titulo: string; apoio: string; grupos: [string, string, string[]][]; vazio: string; comHistorico?: boolean }) {
  const lista = useDados(() => rpc<Minha[]>('minhas_turmas'));
  const [sel, setSel] = useState<string | null>(null);
  const [aba, setAba] = useState<'ativos' | 'historico'>('ativos');
  const [busca, setBusca] = useState('');
  const limite = limiteRecentes();
  const antiga = (t: Minha) => t.etapa === 'realizadas' && (t.data ?? '') < limite;
  const todas = (lista.dados ?? []).filter((t) => grupos.some(([, , es]) => es.includes(t.etapa)));
  const historico = comHistorico ? todas.filter(antiga).filter((t) => !busca.trim() || t.treinamento.toLowerCase().includes(busca.trim().toLowerCase())).sort((a, b) => (b.data ?? '').localeCompare(a.data ?? '')) : [];
  const visiveis = comHistorico && aba === 'historico' ? historico : todas.filter((t) => !comHistorico || !antiga(t)).sort((a, b) => (a.etapa === 'realizadas' && b.etapa === 'realizadas' ? (b.data ?? '').localeCompare(a.data ?? '') : 0));
  const gruposVisiveis: [string, string, string[]][] = comHistorico && aba === 'historico' ? [['realizadas', 'Concluídos há mais de 30 dias', ['realizadas']]] : grupos;
  const qtdHistorico = comHistorico ? todas.filter(antiga).length : 0;
  return (
    <Pagina titulo={titulo} apoio={apoio}>
      {comHistorico && (
        <div className="chips chips-filtro" role="group" aria-label="Período">
          <button type="button" className="chip" aria-pressed={aba === 'ativos'} onClick={() => { setAba('ativos'); setSel(null); }}>Últimos 30 dias<small>{todas.length - qtdHistorico}</small></button>
          <button type="button" className="chip" aria-pressed={aba === 'historico'} onClick={() => { setAba('historico'); setSel(null); }}>Histórico<small>{qtdHistorico}</small></button>
        </div>
      )}
      {comHistorico && aba === 'historico' && <label className="campo"><span className="sr">Buscar treinamento</span><input type="search" placeholder="Buscar treinamento no histórico" value={busca} onChange={(e) => setBusca(e.target.value)} /></label>}
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {lista.carregando && !lista.dados && <Carregando />}
      {lista.dados && !visiveis.length && <p className="vazio">{comHistorico && aba === 'historico' ? 'Nenhum treinamento concluído há mais de 30 dias.' : vazio}</p>}
      {!!visiveis.length && (
        <div className={`mestre-detalhe ${sel ? 'com-selecao' : 'sem-selecao'}`}>
          <div>
            {gruposVisiveis.map(([g, nome, es]) => {
              const itens = visiveis.filter((t) => es.includes(t.etapa));
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
          {sel ? <div><VoltarLista key={sel} aoVoltar={() => setSel(null)} /><PainelInstrutor id={sel} aoMudar={() => void lista.recarregar()} /></div> : <p className="vazio">Escolha um treinamento.</p>}
        </div>
      )}
    </Pagina>
  );
}

const corCalendario = (t: Minha): EventoCal['cor'] => (t.etapa === 'presenca' ? 'presenca' : t.etapa === 'realizadas' ? 'feito' : t.etapa === 'agendadas' || t.etapa === 'formalizar' ? 'confirmado' : 'aguardando');

export function CalendarioInstrutor() {
  const lista = useDados(() => rpc<Minha[]>('minhas_turmas'));
  const [sel, setSel] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const eventos: EventoCal[] = (lista.dados ?? []).filter((t) => t.data).map((t) => ({ id: t.id, titulo: t.treinamento, data: t.data!, hora: t.hora, cor: corCalendario(t) }));
  async function baixarTudo() {
    setErro(null);
    try {
      const futuras = (lista.dados ?? []).filter((t) => t.etapa === 'agendadas');
      const ds = await Promise.all(futuras.map((t) => rpc<TurmaDetalhe>('turma_detalhe', { p_turma: t.id })));
      const evs = ds.filter((t) => t.inicio && t.fim).map(paraAgenda);
      if (!evs.length) throw new Error('Nenhum treinamento agendado para exportar.');
      baixarIcs(evs, 'agenda_treinamentos.ics');
    } catch (e) { setErro(textoErro(e)); }
  }
  return (
    <Pagina titulo="Calendário" apoio="Os treinamentos da sua agenda. Clique em um deles para ver os detalhes." acoes={<button className="botao botao-secundario" type="button" onClick={() => void baixarTudo()}>Exportar agendados (.ics)</button>}>
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      {lista.carregando && !lista.dados && <Carregando />}
      {lista.dados && <Calendario eventos={eventos} aoAbrir={setSel} legenda={[['aguardando', 'Aguardando sua confirmação'], ['confirmado', 'Confirmado'], ['presenca', 'Presença a registrar'], ['feito', 'Concluído']]} />}
      {sel && <Dialogo aberto titulo="Treinamento" largura="larga" aoFechar={() => { setSel(null); void lista.recarregar(); }}><PainelInstrutor id={sel} consulta aoMudar={() => void lista.recarregar()} /></Dialogo>}
    </Pagina>
  );
}

const textoConvite = (t: TurmaDetalhe) => [
  'Olá,',
  'Segue o convite do treinamento de integração a partir da sua confirmação de data e horário:',
  `Treinamento: ${t.treinamento}`,
  `Data: ${dataBR(t.data)}`,
  `Horário: ${hora(t.hora_inicio)}`,
  `Sala: ${t.sala ?? 'A definir'}`,
  'Participantes:',
  ...t.participantes.filter((p) => p.situacao !== 'nao_aplicavel').map((p) => [p.cargo, p.nome].filter(Boolean).join(' - ')),
  'Atenciosamente,',
  'Gente e Gestão',
].join('\n');

const paraAgenda = (t: TurmaDetalhe): EventoAgenda => ({ id: t.id, titulo: `Treinamento: ${t.treinamento}`, inicio: t.inicio!, fim: t.fim!, sala: t.sala, detalhes: textoConvite(t) });

// Com consulta, só mostra: confirmar fica em Confirmar Agenda, e marcar presença, em Presença.
export function PainelInstrutor({ id, aoMudar, consulta = false }: { id: string; aoMudar: () => void; consulta?: boolean }) {
  const d = useDados(() => rpc<TurmaDetalhe>('turma_detalhe', { p_turma: id }), [id]);
  const [erro, setErro] = useState<string | null>(null);
  const [janela, setJanela] = useState<'remarcar' | 'recusar' | 'solicitar' | null>(null);
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
  const ultima = t.solicitacoes.find((s) => s.status !== 'aberta' && !s.resposta?.startsWith('Remarcado pelo instrutor'));
  const presenca = t.etapa === 'presenca' && !consulta;
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

      {!!t.hora_inicio && !!t.inicio && !!t.fim && ['agenda_confirmada', 'convite_enviado'].includes(t.status) && t.etapa !== 'presenca' && (
        <div className="linha-acoes">
          <a className="botao botao-secundario" href={linkOutlook(paraAgenda(t))} target="_blank" rel="noreferrer">Adicionar ao Outlook</a>
          <button className="botao botao-discreto" type="button" onClick={() => baixarIcs([paraAgenda(t)], `treinamento_${t.id.slice(0, 8)}.ics`)}>Baixar arquivo .ics</button>
        </div>
      )}

      {consulta && t.status === 'aguardando_instrutor' && <p className="aviso aviso-info">Responda este treinamento na aba Confirmar Agenda.</p>}
      {consulta && t.etapa === 'presenca' && <p className="aviso aviso-info">Registre os participantes na aba Presença.</p>}

      {!consulta && t.status === 'aguardando_instrutor' && !aberta && (
        <div className="detalhe">
          <h3>Você pode aplicar este treinamento?</h3>
          <div className="linha-acoes">
            {[t.hora_opcao_1, t.hora_opcao_2].filter(Boolean).map((op) => <button key={op} className="botao" type="button" onClick={() => void acao(() => rpc('responder_agenda', { p_turma: t.id, p_acao: 'aceitar', p_hora: op }))}>Confirmar {hora(op)}</button>)}
          </div>
          <div className="linha-acoes">
            <button className="botao botao-secundario" type="button" onClick={() => setJanela('remarcar')}>Escolher outro horário</button>
            <button className="botao botao-discreto" type="button" onClick={() => setJanela('recusar')}>Recusar</button>
          </div>
        </div>
      )}

      <div>
        <h3>{presenca ? `Quem participou? (${pessoas.length - faltam} de ${pessoas.length} marcados)` : `Participantes (${pessoas.length})`}</h3>
        {!pessoas.length && <p className="apoio">Nenhuma pessoa na lista no momento.</p>}
        {pessoas.map((p) => (
          <div className="pessoa" key={p.colaborador_id}>
            <span>{p.nome}<small>{p.cargo}{p.codigo ? ` · Código ${p.codigo}` : ''}</small></span>
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
        {!consulta && !aberta && ['agenda_confirmada', 'convite_enviado'].includes(t.status) && t.etapa !== 'presenca' && <button className="botao" type="button" onClick={() => setJanela('remarcar')}>Remarcar</button>}
        {!consulta && !aberta && t.status !== 'cancelada' && t.status !== 'aguardando_instrutor' && <button className="botao botao-secundario" type="button" onClick={() => setJanela('solicitar')}>{t.presenca_concluida_em ? 'Solicitar correção' : t.etapa === 'presenca' ? 'Solicitar alteração' : 'Solicitar cancelamento'}</button>}
      </div>
      {janela === 'remarcar' && <Remarcar t={t} aoFechar={() => setJanela(null)} aoSalvar={recarregar} />}
      {janela === 'recusar' && <Recusar id={t.id} aoFechar={() => setJanela(null)} aoSalvar={recarregar} />}
      {janela === 'solicitar' && <Solicitar t={t} aoFechar={() => setJanela(null)} aoSalvar={recarregar} />}
    </aside>
  );
}

type Verificacao = {
  ok: boolean; limite: string | null; prazo_aberto: boolean; passado?: boolean; fora_do_prazo?: boolean; igual?: boolean; antes_da_admissao?: string | null;
  indisponiveis: { nome: string; treinamento: string; inicio: string; fim: string; confirmada: boolean }[];
  instrutor: { treinamento: string; inicio: string; fim: string }[];
  sala: { treinamento: string; inicio: string; fim: string }[];
};

// Cada data e horário digitados são conferidos na hora. Só libera quando todos os participantes podem.
function Remarcar({ t, aoFechar, aoSalvar }: { t: TurmaDetalhe; aoFechar: () => void; aoSalvar: () => void }) {
  const [data, setData] = useState(''); const [h, setH] = useState(''); const [motivo, setMotivo] = useState('');
  const v = useDados(() => rpc<Verificacao>('verificar_novo_horario', { p_turma: t.id, p_data: data || null, p_hora: h || null }), [t.id, data, h]);
  const d = v.dados;
  const preenchido = !!data && !!h;
  const limite = d?.limite ? dataBR(d.limite) : null;
  if (d && !d.prazo_aberto) {
    return (
      <FormDialogo titulo="Remarcar treinamento" rotulo="Enviar a Gente e Gestão" aoFechar={aoFechar} desabilitar={!motivo.trim()}
        aoEnviar={async () => { await rpc('solicitar_alteracao', { p_turma: t.id, p_tipo: 'alteracao', p_motivo: motivo, p_proposta: { ...(data ? { data } : {}), ...(h ? { hora: h } : {}) } }); aoSalvar(); }}>
        <p className="aviso aviso-erro">O prazo para remarcar terminou em {limite}. Agora só Gente e Gestão pode alterar.</p>
        <div className="grade-2">
          <Campo rotulo="Data que você sugere"><input type="date" value={data} onChange={(e) => setData(e.target.value)} /></Campo>
          <Campo rotulo="Horário que você sugere"><input type="time" value={h} onChange={(e) => setH(e.target.value)} /></Campo>
        </div>
        <Campo rotulo="Motivo"><textarea required rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
      </FormDialogo>
    );
  }
  return (
    <FormDialogo titulo="Remarcar treinamento" rotulo="Confirmar novo horário" aoFechar={aoFechar} desabilitar={!d?.ok || v.carregando || !motivo.trim()}
      aoEnviar={async () => { await rpc('instrutor_remarcar', { p_turma: t.id, p_data: data, p_hora: h, p_motivo: motivo }); aoSalvar(); }}>
      {limite && <p className="apoio">Você pode remarcar até <strong>{limite}</strong>. Depois disso, só Gente e Gestão altera.</p>}
      <div className="grade-2">
        <Campo rotulo="Nova data"><input type="date" required max={d?.limite?.slice(0, 10) ?? undefined} value={data} onChange={(e) => setData(e.target.value)} /></Campo>
        <Campo rotulo="Novo horário"><input type="time" required value={h} onChange={(e) => setH(e.target.value)} /></Campo>
      </div>
      {preenchido && d && !v.carregando && (
        <div className="remarcar-resultado" role="status">
          {d.ok && <p className="aviso aviso-ok">Horário livre para todos os {t.participantes.filter((p) => p.situacao === 'convocado').length} participantes.</p>}
          {d.fora_do_prazo && <p className="aviso aviso-erro">Esta data passa do limite de {limite}.</p>}
          {d.passado && <p className="aviso aviso-erro">Escolha uma data e um horário futuros.</p>}
          {d.antes_da_admissao && <p className="aviso aviso-erro">Esta data é anterior à admissão de {d.antes_da_admissao}.</p>}
          {d.igual && <p className="aviso aviso-info">Este já é o horário do treinamento.</p>}
          {!!d.indisponiveis.length && (
            <div className="aviso aviso-erro">
              <strong>Indisponíveis neste horário ({new Set(d.indisponiveis.map((i) => i.nome)).size}):</strong>
              <ul>{d.indisponiveis.map((i) => <li key={`${i.nome}${i.treinamento}${i.inicio}`}>{i.nome}: {i.treinamento}, {i.inicio} às {i.fim}{i.confirmada ? '' : ' (aguardando confirmação)'}</li>)}</ul>
            </div>
          )}
          {!!d.instrutor.length && <p className="aviso aviso-erro">Você já tem {d.instrutor.map((i) => `${i.treinamento}, ${i.inicio} às ${i.fim}`).join('; ')}.</p>}
          {!!d.sala.length && <p className="aviso aviso-erro">A sala {t.sala} está ocupada: {d.sala.map((i) => `${i.treinamento}, ${i.inicio} às ${i.fim}`).join('; ')}.</p>}
        </div>
      )}
      {v.erro && <p className="aviso aviso-erro">{v.erro}</p>}
      <Campo rotulo="Motivo"><textarea required rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
      <p className="apoio">Gente e Gestão recebe um aviso. Se o treinamento já está no seu Outlook, atualize o evento depois de remarcar.</p>
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
  const podeMudar = t.etapa === 'presenca';
  const [tipo, setTipo] = useState(concluida ? 'correcao_presenca' : podeMudar ? 'alteracao' : 'cancelamento');
  const [data, setData] = useState(''); const [h, setH] = useState(''); const [motivo, setMotivo] = useState('');
  return (
    <FormDialogo titulo={concluida ? 'Solicitar correção' : podeMudar ? 'Solicitar alteração' : 'Solicitar cancelamento'} rotulo="Enviar a Gente e Gestão" aoFechar={aoFechar} desabilitar={!motivo.trim()}
      aoEnviar={async () => { await rpc('solicitar_alteracao', { p_turma: t.id, p_tipo: tipo, p_motivo: motivo, p_proposta: tipo === 'alteracao' ? { ...(data ? { data } : {}), ...(h ? { hora: h } : {}) } : {} }); aoSalvar(); }}>
      {!concluida && <Campo rotulo="O que você precisa?"><select value={tipo} onChange={(e) => setTipo(e.target.value)}>{podeMudar && <option value="alteracao">Mudar data ou horário</option>}<option value="cancelamento">Cancelar a turma</option></select></Campo>}
      {tipo === 'alteracao' && <div className="grade-2"><Campo rotulo="Nova data"><input type="date" value={data} onChange={(e) => setData(e.target.value)} /></Campo><Campo rotulo="Novo horário"><input type="time" value={h} onChange={(e) => setH(e.target.value)} /></Campo></div>}
      <Campo rotulo="Motivo"><textarea required rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} /></Campo>
    </FormDialogo>
  );
}
