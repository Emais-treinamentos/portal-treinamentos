import { Link, Navigate } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Icone, Rosto, type NomeIcone } from '../componentes/Pecas';
import { dataBR, nomesStatus, rpc, useDados } from '../lib/api';
import { useSessao } from '../lib/sessao';

type ItemFila = { grupo: string; urgente: boolean; titulo: string; detalhe: string | null; turma_id: string | null; colaborador_id: string | null; solicitacao_id: string | null };
type Planejar = { treinamento_id: string; treinamento: string; pessoas: { colaborador_id: string; nome: string }[]; cargos: { cargo_id: string }[] };
type Ind = { verde: number; amarelo: number; vermelho: number; obrigatorios: number; realizados: number; colaboradores: number; horas_homem: number; por_departamento: { departamento: string; obrigatorios: number; realizados: number }[]; por_mes: { mes: string; turmas: number; presentes: number }[] };
type TurmaResumo = { id: string; treinamento: string; status: string; etapa: string; data: string | null; hora: string | null };
type PessoaResumo = { cargo: string | null; ativo: boolean; pendentes: number };

const acoes: Record<string, string> = { solicitacao: 'Decidir', replanejar: 'Replanejar', envio: 'Ver', presenca: 'Ver turma', formalizar: 'Formalizar', movimentacao: 'Classificar', sem_resposta: 'Ver turma' };
const ordem = ['solicitacao', 'replanejar', 'envio', 'presenca', 'formalizar', 'movimentacao'];

export function Inicio() {
  const { usuario } = useSessao();
  if (usuario?.perfil === 'gestor') return <Navigate to="/colaboradores" replace />;
  if (usuario?.perfil === 'colaborador') return <Navigate to="/meus-treinamentos" replace />;
  if (usuario?.perfil === 'instrutor') return <Navigate to="/minhas-turmas" replace />;
  return <Painel nome={usuario?.nome ?? ''} />;
}

function destino(i: ItemFila) {
  if (i.grupo === 'envio') return '/envios';
  if (i.turma_id) return `/turmas?turma=${i.turma_id}`;
  if (i.grupo === 'movimentacao') return `/reciclagem?colaborador=${i.colaborador_id}`;
  return '/turmas?etapa=a_planejar';
}

function saudacao() {
  const h = new Date().getHours();
  return h < 12 ? 'Bom dia' : h < 18 ? 'Boa tarde' : 'Boa noite';
}

function resumo(semTurma: number, assuntos: number) {
  if (!semTurma && !assuntos) return 'Tudo em dia por aqui.';
  const a = semTurma ? (semTurma === 1 ? '1 pessoa está sem turma' : `${semTurma} pessoas estão sem turma`) : '';
  const b = assuntos ? (assuntos === 1 ? '1 assunto aguarda você' : `${assuntos} assuntos aguardam você`) : '';
  return `${[a, b].filter(Boolean).join(' e ')}.`;
}

function Painel({ nome }: { nome: string }) {
  const fila = useDados(() => rpc<ItemFila[]>('fila_inicio'));
  const planejar = useDados(() => rpc<Planejar[]>('a_planejar'));
  const ind = useDados(() => rpc<Ind>('indicadores'));
  const turmas = useDados(() => rpc<TurmaResumo[]>('listar_turmas'));
  const pessoas = useDados(() => rpc<PessoaResumo[]>('painel_colaboradores'));
  const erro = fila.erro ?? planejar.erro ?? ind.erro ?? turmas.erro ?? pessoas.erro;
  const pronto = fila.dados && planejar.dados && ind.dados && turmas.dados && pessoas.dados;
  const aguardam = (fila.dados ?? []).filter((i) => ordem.includes(i.grupo)).sort((a, b) => ordem.indexOf(a.grupo) - ordem.indexOf(b.grupo));
  const comInstrutor = (fila.dados ?? []).filter((i) => i.grupo === 'sem_resposta');
  return (
    <Pagina titulo={`${saudacao()}, ${nome.split(' ')[0]}`} apoio={pronto ? resumo(ind.dados!.vermelho, aguardam.length) : undefined}>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      {!pronto && !erro && <Carregando />}
      {pronto && (
        <>
          <Situacao d={ind.dados!} />
          <Numeros d={ind.dados!} atraso={emAtraso(turmas.dados ?? []).length} />
          <div className="inicio-colunas">
            <div className="inicio-coluna">
              <h2>Quem aguarda você</h2>
              {aguardam.length === 0 && <p className="vazio">Nada pendente. Bom trabalho.</p>}
              {aguardam.map((i, n) => <Tarefa i={i} key={n} />)}
              {comInstrutor.length > 0 && <h2>Aguardando instrutor</h2>}
              {comInstrutor.map((i, n) => <Tarefa i={i} key={n} />)}
            </div>
            <div className="inicio-coluna">
              <h2>Pessoas esperando turma</h2>
              {planejar.dados!.length === 0 && <p className="vazio">Ninguém esperando turma.</p>}
              {planejar.dados!.map((p) => (
                <div className="cartao-pessoa" key={p.treinamento_id}>
                  <span className="cartao-pessoa-texto">
                    <strong>{p.treinamento}</strong>
                    <small>{p.pessoas.length === 1 ? '1 pessoa' : `${p.pessoas.length} pessoas`}</small>
                  </span>
                  <span className="rostos">{p.pessoas.slice(0, 3).map((x) => <Rosto nome={x.nome} key={x.colaborador_id} />)}</span>
                  <Link to={`/planejar?cargos=${p.cargos.map((c) => c.cargo_id).join(',')}`}>Planejar</Link>
                </div>
              ))}
            </div>
          </div>
          <Quadros d={ind.dados!} turmas={turmas.dados ?? []} pessoas={pessoas.dados ?? []} />
        </>
      )}
    </Pagina>
  );
}

const hojeISO = () => { const a = new Date(); return new Date(a.getTime() - a.getTimezoneOffset() * 60000).toISOString().slice(0, 10); };
const fechada = (t: TurmaResumo) => ['realizada', 'encerrada', 'cancelada'].includes(t.status);
const emAtraso = (l: TurmaResumo[]) => l.filter((t) => !fechada(t) && !!t.data && (t.etapa === 'presenca' || t.data < hojeISO())).sort((a, b) => (a.data ?? '').localeCompare(b.data ?? ''));
const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '0%');

function Numeros({ d, atraso }: { d: Ind; atraso: number }) {
  const itens: [string, string | number, string][] = [
    ['Hora-Homem Total', Math.round(d.horas_homem), 'horas realizadas'],
    ['Realizados / Previstos', `${d.realizados} / ${d.obrigatorios}`, 'treinamentos obrigatórios'],
    ['Pendências Críticas', atraso, 'treinamentos em atraso'],
    ['Colaboradores Ativos', d.colaboradores, 'pessoas'],
  ];
  return (
    <div className="cartoes">
      {itens.map(([r, v, a]) => <div className="cartao" key={r}><span className="cartao-rotulo">{r}</span><strong className="cartao-valor">{v}</strong><span className="cartao-apoio">{a}</span></div>)}
    </div>
  );
}

function Quadros({ d, turmas, pessoas }: { d: Ind; turmas: TurmaResumo[]; pessoas: PessoaResumo[] }) {
  const hoje = hojeISO();
  const proximos = turmas.filter((t) => !fechada(t) && !!t.data && t.data >= hoje && t.etapa !== 'presenca').sort((a, b) => (a.data ?? '').localeCompare(b.data ?? '')).slice(0, 5);
  const atrasados = emAtraso(turmas).slice(0, 5);
  const porCargo = new Map<string, { pendentes: number; pessoas: number }>();
  pessoas.filter((p) => p.ativo && p.pendentes > 0 && p.cargo).forEach((p) => { const a = porCargo.get(p.cargo!) ?? { pendentes: 0, pessoas: 0 }; porCargo.set(p.cargo!, { pendentes: a.pendentes + Number(p.pendentes), pessoas: a.pessoas + 1 }); });
  const cargos = [...porCargo.entries()].sort((a, b) => b[1].pendentes - a[1].pendentes).slice(0, 10);
  const tabelaTurmas = (l: TurmaResumo[], vazio: string) => (
    <div className="tabela-rolagem"><table className="tabela">
      <thead><tr><th>Treinamento</th><th>Data</th><th>Status</th></tr></thead>
      <tbody>{!l.length && <tr><td colSpan={3}>{vazio}</td></tr>}{l.map((t) => <tr key={t.id}><td><Link className="link" to={`/turmas?turma=${t.id}`}>{t.treinamento}</Link></td><td>{dataBR(t.data)}</td><td>{nomesStatus[t.status as keyof typeof nomesStatus] ?? t.status}</td></tr>)}</tbody>
    </table></div>
  );
  return (
    <div className="painel-grade">
      <section><h2>Próximos Treinamentos</h2>{tabelaTurmas(proximos, 'Nenhum treinamento futuro agendado.')}</section>
      <section><h2>Treinamentos em Atraso</h2>{tabelaTurmas(atrasados, 'Nenhum treinamento em atraso.')}</section>
      <section><h2>Cargos com Maior Pendência</h2><div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Cargo</th><th>Pendentes</th><th>Pessoas</th></tr></thead>
        <tbody>{!cargos.length && <tr><td colSpan={3}>Nenhuma pendência encontrada.</td></tr>}{cargos.map(([c, v]) => <tr key={c}><td>{c}</td><td>{v.pendentes}</td><td>{v.pessoas}</td></tr>)}</tbody></table></div></section>
      <section><h2>Conformidade por Departamento</h2><div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Departamento</th><th>Realizados</th><th>Conformidade</th></tr></thead>
        <tbody>{d.por_departamento.map((x) => <tr key={x.departamento}><td>{x.departamento}</td><td>{x.realizados} de {x.obrigatorios}</td><td>{pct(x.realizados, x.obrigatorios)}</td></tr>)}</tbody></table></div></section>
      {!!d.por_mes.length && <section><h2>Últimos 12 Meses</h2><div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Mês</th><th>Turmas</th><th>Presenças</th></tr></thead>
        <tbody>{d.por_mes.map((x) => <tr key={x.mes}><td>{x.mes.split('-').reverse().join('/')}</td><td>{x.turmas}</td><td>{x.presentes}</td></tr>)}</tbody></table></div></section>}
    </div>
  );
}

function Situacao({ d }: { d: Ind }) {
  const pct = d.obrigatorios ? Math.round((d.realizados / d.obrigatorios) * 100) : 0;
  const faixas: [string, number, string][] = [['cor-dia', d.verde, 'em dia'], ['cor-andamento', d.amarelo, 'em andamento'], ['cor-sem', d.vermelho, 'sem turma']];
  return (
    <section className="situacao" aria-label="Situação das pessoas">
      <div className="situacao-numero">
        <span>Conformidade da equipe</span>
        <strong>{pct}%</strong>
        <span>{d.realizados} de {d.obrigatorios} treinamentos obrigatórios</span>
      </div>
      <div className="situacao-pessoas">
        <div className="situacao-barra" aria-hidden="true">
          {faixas.map(([c, v]) => (v ? <i className={c} style={{ flex: v }} key={c} /> : null))}
        </div>
        <div className="situacao-legenda">
          {faixas.map(([c, v, r]) => <span key={c}><i className={c} aria-hidden="true" /><strong>{v}</strong> {r}</span>)}
        </div>
      </div>
    </section>
  );
}

function Tarefa({ i }: { i: ItemFila }) {
  const corte = i.titulo.indexOf(': ');
  const titulo = corte > 0 ? i.titulo.slice(0, corte) : i.titulo;
  const acao = corte > 0 ? i.titulo.slice(corte + 2) : '';
  const texto = [acao && acao[0].toUpperCase() + acao.slice(1), i.detalhe].filter(Boolean).join(' · ');
  const icone: NomeIcone = i.grupo === 'envio' ? 'envios' : 'turmas';
  return (
    <div className="cartao-pessoa">
      {i.grupo === 'movimentacao' ? <Rosto nome={titulo} /> : <Rosto><Icone nome={icone} /></Rosto>}
      <span className="cartao-pessoa-texto">
        <strong>{titulo}{i.urgente && <span className="selo-urgente">Urgente</span>}</strong>
        <small>{texto}</small>
      </span>
      <Link to={destino(i)}>{acoes[i.grupo]}</Link>
    </div>
  );
}
