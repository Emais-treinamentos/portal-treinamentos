import { useEffect, useRef, useState } from 'react';
import { dataBR, hora } from '../lib/api';

export type EventoCal = { id: string; titulo: string; data: string; hora?: string | null; cor: 'confirmado' | 'aguardando' | 'presenca' | 'feito' | 'cancelado'; detalhe?: string };
const semana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];
const meses = ['Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho', 'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'];
const iso = (a: number, m: number, d: number) => `${a}-${String(m + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

export function Calendario({ eventos: brutos, aoAbrir, legenda }: { eventos: EventoCal[]; aoAbrir: (id: string) => void; legenda: [EventoCal['cor'], string][] }) {
  const eventos = brutos.map((e) => ({ ...e, data: e.data.slice(0, 10) }));
  const hoje = new Date();
  const hojeIso = iso(hoje.getFullYear(), hoje.getMonth(), hoje.getDate());
  const [mes, setMes] = useState({ a: hoje.getFullYear(), m: hoje.getMonth() });
  // Abre no mês do próximo treinamento quando o mês atual está vazio.
  const pronto = useRef(false);
  useEffect(() => {
    if (pronto.current || !eventos.length) return;
    pronto.current = true;
    const prefixo = hojeIso.slice(0, 7);
    if (eventos.some((e) => e.data.startsWith(prefixo))) return;
    const prox = [...eventos].sort((a, b) => a.data.localeCompare(b.data)).find((e) => e.data >= hojeIso);
    if (prox) setMes({ a: Number(prox.data.slice(0, 4)), m: Number(prox.data.slice(5, 7)) - 1 });
  }, [brutos]); // eslint-disable-line react-hooks/exhaustive-deps
  const andar = (n: number) => { const d = new Date(mes.a, mes.m + n, 1); setMes({ a: d.getFullYear(), m: d.getMonth() }); };
  const vazios = new Date(mes.a, mes.m, 1).getDay();
  const dias = new Date(mes.a, mes.m + 1, 0).getDate();
  const doDia = (d: number) => eventos.filter((e) => e.data === iso(mes.a, mes.m, d)).sort((x, y) => (x.hora ?? '').localeCompare(y.hora ?? ''));
  const doMes = eventos.filter((e) => e.data.startsWith(iso(mes.a, mes.m, 1).slice(0, 7))).sort((x, y) => `${x.data}${x.hora}`.localeCompare(`${y.data}${y.hora}`));
  return (
    <section className="cal" aria-label="Calendário de treinamentos">
      <div className="cal-topo">
        <h2>{meses[mes.m]} de {mes.a}</h2>
        <div className="linha-acoes">
          <button className="botao botao-discreto" type="button" onClick={() => andar(-1)}>Anterior</button>
          <button className="botao botao-discreto" type="button" onClick={() => setMes({ a: hoje.getFullYear(), m: hoje.getMonth() })}>Hoje</button>
          <button className="botao botao-discreto" type="button" onClick={() => andar(1)}>Próximo</button>
        </div>
      </div>
      <div className="cal-grade">
        {semana.map((s) => <div className="cal-semana" key={s}>{s}</div>)}
        {Array.from({ length: vazios }).map((_, i) => <div className="cal-dia cal-fora" key={`v${i}`} />)}
        {Array.from({ length: dias }).map((_, i) => {
          const d = i + 1;
          return (
            <div className={`cal-dia${iso(mes.a, mes.m, d) === hojeIso ? ' cal-hoje' : ''}`} key={d}>
              <span className="cal-numero">{d}</span>
              {doDia(d).map((e) => <button key={e.id} type="button" className={`cal-evento cal-${e.cor}`} title={e.detalhe ? `${e.titulo} · ${e.detalhe}` : e.titulo} onClick={() => aoAbrir(e.id)}><b>{hora(e.hora)}</b> <span>{e.titulo}</span></button>)}
            </div>
          );
        })}
      </div>
      <div className="cal-legenda">{legenda.map(([c, t]) => <span key={c}><i className={`cal-${c}`} aria-hidden="true" />{t}</span>)}</div>
      <div className="cal-lista">
        {!doMes.length && <p className="apoio">Nenhum treinamento neste mês.</p>}
        {doMes.map((e) => <button key={e.id} type="button" className="item-lista" onClick={() => aoAbrir(e.id)}><i className={`cal-ponto cal-${e.cor}`} aria-hidden="true" /><span><strong>{e.titulo}</strong><small>{dataBR(e.data)} {hora(e.hora)}{e.detalhe ? ` · ${e.detalhe}` : ''}</small></span><small>Ver</small></button>)}
      </div>
    </section>
  );
}
