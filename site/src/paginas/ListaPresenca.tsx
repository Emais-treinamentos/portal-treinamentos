import { useState } from 'react';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { SeloSituacao } from '../componentes/Pecas';
import { cargaTexto, dataBR, rpc, textoErro, useDados, type SituacaoColaborador } from '../lib/api';
import { gerarF109, gerarGrade, gerarTermoDispensa } from '../lib/documentos';

type Linha = { id: string; nome: string; cargo: string | null; departamento: string | null; ativo: boolean; data_referencia: string | null; total: number; realizados: number; pendentes: number; motivo: string };

const JANELA_ATIVOS = 30;
const diasDesde = (d: string | null) => (d ? Math.floor((Date.now() - new Date(`${d.slice(0, 10)}T00:00:00`).getTime()) / 86400000) : null);
const recente = (d: string | null) => { const n = diasDesde(d); return n !== null && n >= 0 && n <= JANELA_ATIVOS; };

export function ListaPresenca() {
  const lista = useDados(() => rpc<Linha[]>('painel_colaboradores'));
  const [aba, setAba] = useState<'ativos' | 'historico'>('ativos');
  const [busca, setBusca] = useState('');
  const [periodo, setPeriodo] = useState('');
  const [dep, setDep] = useState('');
  const [sel, setSel] = useState<string | null>(null);

  if (sel) return <Documento id={sel} aoVoltar={() => setSel(null)} />;

  const q = busca.trim().toLowerCase();
  const pessoas = (lista.dados ?? []).filter((c) => c.ativo && (!q || `${c.nome} ${c.cargo ?? ''}`.toLowerCase().includes(q)));
  const ativos = pessoas.filter((c) => recente(c.data_referencia));
  const historico = pessoas.filter((c) => !recente(c.data_referencia)).filter((c) => {
    const n = diasDesde(c.data_referencia);
    return (!dep || c.departamento === dep) && (!periodo || (n !== null && n <= Number(periodo)));
  });
  const linhas = aba === 'ativos' ? ativos : historico;
  const deps = [...new Set((lista.dados ?? []).map((c) => c.departamento).filter(Boolean))].sort() as string[];

  return (
    <Pagina titulo="Lista de presença" apoio="Selecione um colaborador para ver o documento oficial.">
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      <label className="campo campo-busca lista-busca"><span className="sr">Buscar</span><input type="search" placeholder="Buscar por nome ou cargo" value={busca} onChange={(e) => setBusca(e.target.value)} /></label>
      <div className="chips chips-filtro" role="group" aria-label="Colaboradores">
        <button type="button" className="chip" aria-pressed={aba === 'ativos'} onClick={() => setAba('ativos')}>Ativos<small>{ativos.length}</small></button>
        <button type="button" className="chip" aria-pressed={aba === 'historico'} onClick={() => setAba('historico')}>Histórico<small>{historico.length}</small></button>
      </div>
      {aba === 'historico' && (
        <div className="filtros">
          <label className="campo"><span>Período</span><select value={periodo} onChange={(e) => setPeriodo(e.target.value)}><option value="">Todos</option><option value="60">Últimos 60 dias</option><option value="90">Últimos 90 dias</option><option value="180">Últimos 180 dias</option></select></label>
          <label className="campo"><span>Departamento</span><select value={dep} onChange={(e) => setDep(e.target.value)}><option value="">Todos os departamentos</option>{deps.map((d) => <option key={d}>{d}</option>)}</select></label>
        </div>
      )}
      {lista.carregando && !lista.dados && <Carregando />}
      {lista.dados && (
        <div className="tabela-rolagem">
          <table className="tabela">
            <thead><tr><th>Colaborador</th><th>Cargo</th><th>Total</th><th>Realizados</th><th>Pendentes</th><th>Documento</th></tr></thead>
            <tbody>
              {!linhas.length && <tr><td colSpan={6}>{aba === 'ativos' ? `Nenhum colaborador com admissão ou movimentação nos últimos ${JANELA_ATIVOS} dias.` : 'Nenhum colaborador no histórico.'}</td></tr>}
              {linhas.map((c) => (
                <tr key={c.id}>
                  <td>{c.nome}</td>
                  <td>{c.cargo}</td>
                  <td>{c.total}</td>
                  <td>{c.realizados}</td>
                  <td>{c.motivo === 'Termo de Dispensa emitido' ? 'Termo emitido' : c.pendentes}</td>
                  <td><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => setSel(c.id)}>Ver</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Pagina>
  );
}

function Documento({ id, aoVoltar }: { id: string; aoVoltar: () => void }) {
  const d = useDados(() => rpc<SituacaoColaborador>('situacao_colaborador', { p_colaborador: id }), [id]);
  const [erro, setErro] = useState<string | null>(null);
  const s = d.dados;
  const doc = async (f: () => Promise<void>) => { setErro(null); try { await f(); } catch (e) { setErro(textoErro(e)); } };
  const dispensa = s?.decisao?.acao_final === 'dispensa';
  const feitos = (s?.historico ?? []).filter((h) => h.situacao === 'presente');
  const abertos = (s?.itens ?? []).filter((i) => !['realizado', 'dispensado'].includes(i.situacao));
  return (
    <Pagina titulo={s?.colaborador.nome ?? 'Lista de presença'} apoio="Documento oficial de treinamentos do colaborador.">
      {d.erro && <Mensagem tipo="erro">{d.erro}</Mensagem>}
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      <div className="linha-acoes doc-acoes">
        <button className="botao botao-discreto" type="button" onClick={aoVoltar}>Voltar à lista</button>
        {s && !dispensa && <button className="botao" type="button" onClick={() => void doc(() => gerarF109(s))}>Exportar PDF</button>}
        {s && <button className="botao botao-secundario" type="button" onClick={() => void doc(() => gerarGrade(s))}>Grade de treinamentos</button>}
        {s && dispensa && <button className="botao botao-secundario" type="button" onClick={() => void doc(() => gerarTermoDispensa(s))}>Termo de Dispensa</button>}
      </div>
      {!s && !d.erro && <Carregando />}
      {s && abertos.length > 0 && (
        <section className="doc-pendencias">
          <h2>Ainda em aberto</h2>
          {abertos.map((i) => (
            <div className="pessoa" key={i.treinamento_id}>
              <span>{i.treinamento}{i.data_turma && <small>Turma em {dataBR(i.data_turma)}</small>}</span>
              <SeloSituacao situacao={i.situacao} />
            </div>
          ))}
        </section>
      )}
      {s && dispensa && <p className="vazio">Colaborador com dispensa confirmada: não há lista de treinamentos, apenas o Termo de Dispensa.</p>}
      {s && !dispensa && (
        <div className="tabela-rolagem">
          <article className="doc-f109">
            <header className="doc-cabecalho">
              <img src={`${import.meta.env.BASE_URL}logo-emais.png`} alt="Emais" />
              <div><strong>Sistema de Gestão da Qualidade</strong><strong>Lista de Treinamento Onboarding</strong></div>
              <dl><dt>Código</dt><dd>F.109</dd><dt>Revisão</dt><dd>01</dd><dt>Data ver.:</dt><dd>07/2026</dd></dl>
            </header>
            <table className="doc-dados"><tbody>
              <tr><th>Colaborador</th><td colSpan={3}>{s.colaborador.nome}</td></tr>
              <tr><th>Cargo</th><td>{s.colaborador.cargo}</td><th>Data Admissão</th><td>{dataBR(s.colaborador.data_referencia ?? s.colaborador.data_admissao)}</td></tr>
              <tr><th>Setor / Área</th><td colSpan={3}>{s.colaborador.departamento}</td></tr>
            </tbody></table>
            <table className="doc-treinamentos">
              <thead><tr><th>#</th><th>Treinamento</th><th>C.H.</th><th>Data</th><th>Status</th><th>Cód. Registro da Turma</th></tr></thead>
              <tbody>
                {!feitos.length && <tr><td colSpan={6}>Nenhum treinamento registrado</td></tr>}
                {feitos.map((h, i) => <tr key={h.turma_id}><td>{i + 1}</td><td>{h.treinamento}</td><td>{cargaTexto(h.carga_minutos)}</td><td>{dataBR(h.data)}</td><td><strong>Realizado</strong></td><td>{h.turma_id.slice(0, 8).toUpperCase()}</td></tr>)}
              </tbody>
            </table>
            <p className="doc-total">Carga Horária Total: {cargaTexto(feitos.reduce((a, h) => a + h.carga_minutos, 0))}</p>
            <div className="doc-assinatura">
              <strong>Declaro que participei dos treinamentos acima descritos.</strong>
              <div><span>Nome do Colaborador<b>{s.colaborador.nome}</b></span><span>Assinatura<b>&nbsp;</b></span><span>Data<b>____/____/________</b></span></div>
            </div>
            <div className="doc-assinatura doc-eficacia">
              <strong>Avaliação de Eficácia</strong>
              <small>(Preencher após 90 dias da conclusão dos treinamentos)</small>
              <table><tbody>
                <tr><th>Data da Avaliação</th><td>&nbsp;</td></tr><tr><th>Avaliador</th><td>&nbsp;</td></tr><tr><th>Resultado</th><td>&nbsp;</td></tr><tr><th>Observações</th><td className="doc-obs">&nbsp;</td></tr>
              </tbody></table>
            </div>
          </article>
        </div>
      )}
    </Pagina>
  );
}
