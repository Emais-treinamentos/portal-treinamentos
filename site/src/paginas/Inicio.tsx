import { Link, Navigate } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Icone, Rosto, type NomeIcone } from '../componentes/Pecas';
import { rpc, useDados } from '../lib/api';
import { useSessao } from '../lib/sessao';

type ItemFila = { grupo: string; urgente: boolean; titulo: string; detalhe: string | null; turma_id: string | null; colaborador_id: string | null; solicitacao_id: string | null };
type Planejar = { treinamento_id: string; treinamento: string; pessoas: { colaborador_id: string; nome: string }[]; cargos: { cargo_id: string }[] };
type Ind = { verde: number; amarelo: number; vermelho: number; obrigatorios: number; realizados: number };

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
  if (i.grupo === 'movimentacao') return `/movimentacoes?colaborador=${i.colaborador_id}`;
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
  const erro = fila.erro ?? planejar.erro ?? ind.erro;
  const pronto = fila.dados && planejar.dados && ind.dados;
  const aguardam = (fila.dados ?? []).filter((i) => ordem.includes(i.grupo)).sort((a, b) => ordem.indexOf(a.grupo) - ordem.indexOf(b.grupo));
  const comInstrutor = (fila.dados ?? []).filter((i) => i.grupo === 'sem_resposta');
  return (
    <Pagina titulo={`${saudacao()}, ${nome.split(' ')[0]}`} apoio={pronto ? resumo(ind.dados!.vermelho, aguardam.length) : undefined}>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      {!pronto && !erro && <Carregando />}
      {pronto && (
        <>
          <Situacao d={ind.dados!} />
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
        </>
      )}
    </Pagina>
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
