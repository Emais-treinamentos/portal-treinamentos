import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { dataBR, rpc, textoErro, useDados } from '../lib/api';
import { gerarF109, nomesResultado, type DocumentoEficacia } from '../lib/documentos';
import { useSessao } from '../lib/sessao';

type Linha = { colaborador_id: string; nome: string; cargo: string | null; departamento: string | null; data_conclusao: string; data_prevista: string; situacao: 'a_avaliar' | 'aguardando' | 'avaliada'; avaliacao_id: string | null; data_avaliacao: string | null; avaliador: string | null; resultado: string | null; observacoes: string | null };
const abas: [Linha['situacao'], string][] = [['a_avaliar', 'A avaliar'], ['aguardando', 'Aguardando 90 dias'], ['avaliada', 'Avaliadas']];

export function Eficacia() {
  const lista = useDados(() => rpc<Linha[]>('eficacia_painel'));
  const [params, setParams] = useSearchParams();
  const [aba, setAba] = useState<Linha['situacao']>('a_avaliar');
  const [busca, setBusca] = useState('');
  const [sel, setSel] = useState<Linha | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  useEffect(() => {
    const l = lista.dados?.find((x) => x.colaborador_id === params.get('colaborador') && x.situacao === 'a_avaliar');
    if (l) { setSel(l); setParams({}, { replace: true }); }
  }, [lista.dados, params, setParams]);
  const q = busca.trim().toLowerCase();
  const conta = (s: Linha['situacao']) => (lista.dados ?? []).filter((x) => x.situacao === s).length;
  const linhas = (lista.dados ?? []).filter((x) => x.situacao === aba && (!q || `${x.nome} ${x.cargo ?? ''}`.toLowerCase().includes(q)));
  async function baixar(l: Linha) {
    setErro(null);
    try {
      const d = await rpc<DocumentoEficacia>('eficacia_documento', { p_id: l.avaliacao_id });
      await gerarF109(d.assinatura?.conteudo ?? d.conteudo, d.assinatura ?? undefined, d);
    } catch (e) { setErro(textoErro(e)); }
  }
  return (
    <Pagina titulo="Avaliação de Eficácia" apoio="Preencha depois de 90 dias da conclusão dos treinamentos e baixe o F.109 para arquivamento.">
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {erro && <Mensagem tipo="erro" aoFechar={() => setErro(null)}>{erro}</Mensagem>}
      {msg && <Mensagem tipo="ok" aoFechar={() => setMsg(null)}>{msg}</Mensagem>}
      <label className="campo campo-busca lista-busca"><span className="sr">Buscar</span><input type="search" placeholder="Buscar por nome ou cargo" value={busca} onChange={(e) => setBusca(e.target.value)} /></label>
      <div className="chips chips-filtro" role="group" aria-label="Situação">
        {abas.map(([a, nome]) => <button key={a} type="button" className="chip" aria-pressed={aba === a} onClick={() => setAba(a)}>{nome}<small>{conta(a)}</small></button>)}
      </div>
      {lista.carregando && !lista.dados && <Carregando />}
      {lista.dados && (
        <div className="tabela-rolagem">
          <table className="tabela">
            <thead><tr><th>Colaborador</th><th>Concluiu em</th>{aba === 'avaliada' ? <><th>Avaliado em</th><th>Resultado</th><th>Avaliador</th></> : <th>Avaliar a partir de</th>}{aba !== 'aguardando' && <th>Ações</th>}</tr></thead>
            <tbody>
              {!linhas.length && <tr><td colSpan={6}>Ninguém nesta situação.</td></tr>}
              {linhas.map((l) => (
                <tr key={l.avaliacao_id ?? l.colaborador_id}>
                  <td><strong className="celula-nome">{l.nome}</strong><small className="celula-apoio">{l.cargo}</small></td>
                  <td>{dataBR(l.data_conclusao)}</td>
                  {aba === 'avaliada' ? <><td>{dataBR(l.data_avaliacao)}</td><td>{nomesResultado[l.resultado ?? '']}</td><td>{l.avaliador}</td></> : <td>{dataBR(l.data_prevista)}</td>}
                  {aba === 'a_avaliar' && <td><button className="botao botao-pequeno" type="button" onClick={() => setSel(l)}>Avaliar</button></td>}
                  {aba === 'avaliada' && <td><span className="linha-acoes"><button className="botao botao-pequeno" type="button" onClick={() => void baixar(l)}>Baixar PDF</button><button className="botao botao-discreto botao-pequeno" type="button" onClick={() => setSel(l)}>Corrigir</button></span></td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {sel && <Formulario l={sel} aoFechar={() => setSel(null)} aoSalvar={() => { setMsg('Avaliação salva.'); setAba('avaliada'); void lista.recarregar(); }} />}
    </Pagina>
  );
}

function hojeLocal() { const a = new Date(); return new Date(a.getTime() - a.getTimezoneOffset() * 60000).toISOString().slice(0, 10); }

function Formulario({ l, aoFechar, aoSalvar }: { l: Linha; aoFechar: () => void; aoSalvar: () => void }) {
  const { usuario } = useSessao();
  const [data, setData] = useState(l.data_avaliacao?.slice(0, 10) ?? hojeLocal());
  const [avaliador, setAvaliador] = useState(l.avaliador ?? usuario?.nome ?? '');
  const [resultado, setResultado] = useState(l.resultado ?? '');
  const [obs, setObs] = useState(l.observacoes ?? '');
  return (
    <FormDialogo titulo={`Avaliação de Eficácia: ${l.nome}`} rotulo="Salvar avaliação" aoFechar={aoFechar}
      aoEnviar={async () => { await rpc('salvar_eficacia', { p_colaborador: l.colaborador_id, p_data: data, p_avaliador: avaliador, p_resultado: resultado, p_observacoes: obs || null, p_id: l.avaliacao_id }); aoSalvar(); }}>
      <p className="apoio">{l.cargo}. Treinamentos concluídos em {dataBR(l.data_conclusao)}.</p>
      <div className="grade-2">
        <Campo rotulo="Data da avaliação"><input type="date" required value={data} onChange={(e) => setData(e.target.value)} /></Campo>
        <Campo rotulo="Avaliador"><input required value={avaliador} onChange={(e) => setAvaliador(e.target.value)} /></Campo>
      </div>
      <Campo rotulo="Resultado"><select required value={resultado} onChange={(e) => setResultado(e.target.value)}><option value="">Escolha</option>{Object.entries(nomesResultado).map(([v, n]) => <option key={v} value={v}>{n}</option>)}</select></Campo>
      <Campo rotulo={resultado && resultado !== 'eficaz' ? 'Observações (obrigatório)' : 'Observações'}><textarea rows={4} value={obs} onChange={(e) => setObs(e.target.value)} /></Campo>
    </FormDialogo>
  );
}
