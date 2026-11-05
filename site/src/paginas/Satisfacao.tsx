import { useState } from 'react';
import { Pagina, Mensagem, VoltarLista } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo } from '../componentes/Pecas';
import { rpc, useDados } from '../lib/api';

type Item = { id: string; nome: string; respostas: number; participantes: number; oculto: boolean; satisfeitos?: number; media?: number; horario?: number; ate_15?: number; mais_15?: number; conteudo?: number; instrutor?: number; tempo?: number; local_material?: number; melhorias?: { nome: string; n: number }[]; comentarios?: string[] };
type Dados = { instrutores: string[]; respostas: number; participantes: number; satisfeitos: number; no_horario: number; treinamentos: Item[] };
const pct = (a: number | undefined, b: number) => (b ? Math.round(((a ?? 0) / b) * 100) : 0);

export function Satisfacao() {
  const [meses, setMeses] = useState(12);
  const [instrutor, setInstrutor] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const d = useDados(() => rpc<Dados>('satisfacao', { p_meses: meses, p_instrutor: instrutor || null }), [meses, instrutor]);
  const x = d.dados;
  const t = x?.treinamentos.find((i) => i.id === sel && !i.oculto);
  const poucas = !x || x.respostas < 3;
  const resumo: [string, string, string][] = x ? [
    ['Satisfação geral', poucas ? 'Oculto' : `${pct(x.satisfeitos, x.respostas)}%`, 'notas 4 e 5'],
    ['Respostas', `${pct(x.respostas, x.participantes)}%`, `${x.respostas} de ${x.participantes} participantes`],
    ['Começou no horário', poucas ? 'Oculto' : `${pct(x.no_horario, x.respostas)}%`, poucas ? 'menos de 3 respostas' : `${100 - pct(x.no_horario, x.respostas)}% relataram atraso`],
  ] : [];
  return (
    <Pagina titulo="Satisfação" apoio="Respostas anônimas dos colaboradores, sempre em conjunto.">
      {d.erro && <Mensagem tipo="erro">{d.erro}</Mensagem>}
      {d.carregando && !x && <Carregando />}
      {x && (
        <>
          <div className="cartoes cartoes-3">{resumo.map(([r, v, a]) => <div className="cartao" key={r}><span className="cartao-rotulo">{r}</span><strong className="cartao-valor">{v}</strong><span className="cartao-apoio">{a}</span></div>)}</div>
          <div className="filtros">
            <Campo rotulo="Período"><select value={meses} onChange={(e) => setMeses(Number(e.target.value))}><option value={3}>Últimos 3 meses</option><option value={6}>Últimos 6 meses</option><option value={12}>Últimos 12 meses</option></select></Campo>
            <Campo rotulo="Instrutor"><select value={instrutor} onChange={(e) => setInstrutor(e.target.value)}><option value="">Todos</option>{x.instrutores.map((i) => <option key={i}>{i}</option>)}</select></Campo>
          </div>
          <div className={`mestre-detalhe ${t ? 'com-selecao' : 'sem-selecao'}`}>
            <div className="lista-turmas">
              {!x.treinamentos.length && <p className="vazio">Nenhuma avaliação recebida neste período.</p>}
              {x.treinamentos.map((i) => (
                <button key={i.id} type="button" className="item-lista" aria-current={sel === i.id} disabled={i.oculto} onClick={() => setSel(i.id)}>
                  <span /><span><strong>{i.nome}</strong><small>{i.respostas} resposta(s)</small></span>
                  <strong className="sat-indicador">{i.oculto ? 'Oculto' : `${pct(i.satisfeitos, i.respostas)}%`}</strong>
                </button>
              ))}
              {x.treinamentos.some((i) => i.oculto) && <p className="apoio">Com menos de 3 respostas o resultado fica oculto, para proteger quem respondeu.</p>}
            </div>
            {t ? <div><VoltarLista key={t.id} aoVoltar={() => setSel(null)} /><Detalhe t={t} /></div> : <p className="vazio">Escolha um treinamento para ver a análise.</p>}
          </div>
        </>
      )}
    </Pagina>
  );
}

function Detalhe({ t }: { t: Item }) {
  const n = t.respostas;
  const topicos: [string, number | undefined][] = [['O conteúdo será útil no dia a dia', t.conteudo], ['O instrutor explicou com clareza', t.instrutor], ['O tempo foi suficiente', t.tempo], ['A sala e o material estavam adequados', t.local_material]];
  const faixas: [string, number | undefined, string][] = [['sat-1', t.horario, 'no horário'], ['sat-2', t.ate_15, 'atraso até 15 min'], ['sat-3', t.mais_15, 'atraso maior']];
  return (
    <aside className="painel" aria-label="Análise do treinamento">
      <div><h2>{t.nome}</h2><p className="apoio">{n} respostas de {t.participantes} participantes ({pct(n, t.participantes)}%)</p></div>
      <div className="sat-numeros">
        <div><strong>{pct(t.satisfeitos, n)}%</strong><small>satisfeitos (notas 4 e 5)</small></div>
        <div><strong>{String(t.media).replace('.', ',')}</strong><small>nota média, de 1 a 5</small></div>
      </div>
      <div>
        <h3>Pontualidade</h3>
        <div className="situacao-barra" aria-hidden="true">{faixas.map(([c, v]) => (v ? <i className={c} style={{ flex: v }} key={c} /> : null))}</div>
        <div className="situacao-legenda sat-legenda">{faixas.map(([c, v, r]) => <span key={c}><i className={c} aria-hidden="true" /><strong>{pct(v, n)}%</strong> {r}</span>)}</div>
      </div>
      <div>
        <h3>O que foi avaliado <small>(% de "Sim")</small></h3>
        {topicos.map(([r, v]) => (
          <div className="sat-topico" key={r}>
            <div><span>{r}</span><strong>{pct(v, n)}%</strong></div>
            <div className="sat-trilho"><i style={{ width: `${pct(v, n)}%` }} /></div>
          </div>
        ))}
      </div>
      <div>
        <h3>O que pode melhorar <small>(% de quem citou)</small></h3>
        {!t.melhorias?.length && <p className="apoio">Ninguém marcou pontos a melhorar.</p>}
        {t.melhorias?.map((m) => <div className="pessoa" key={m.nome}><span>{m.nome}</span><strong>{pct(m.n, n)}%</strong></div>)}
      </div>
      {!!t.comentarios?.length && <div><h3>Comentários</h3>{t.comentarios.map((c, i) => <p className="sat-comentario" key={i}>{c}</p>)}</div>}
    </aside>
  );
}
