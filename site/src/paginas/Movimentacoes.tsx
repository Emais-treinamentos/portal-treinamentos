import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, Farol } from '../componentes/Pecas';
import { dataBR, nomesAcao, nomesMovimentacao, rpc, textoErro, useDados, type SituacaoColaborador } from '../lib/api';
import { gerarTermoDispensa } from '../lib/documentos';

type Linha = { colaborador_id: string; nome: string; cargo_atual: string; cargo_anterior: string; data_movimentacao: string; decisao: string | null; decidido_em: string | null };
type Sugestao = { acao_sugerida: string; treinamentos_parcial: string[]; tempo_empresa_meses: number; movimentacao_recente: boolean; matriz_atual: { id: string; nome: string; eh_politica: boolean }[] };

export function Movimentacoes() {
  const lista = useDados(() => rpc<Linha[]>('movimentacoes_pendentes'));
  const [params] = useSearchParams();
  const [sel, setSel] = useState<string | null>(params.get('colaborador'));
  const pendentes = (lista.dados ?? []).filter((l) => !l.decisao);
  const feitas = (lista.dados ?? []).filter((l) => l.decisao);
  const linha = lista.dados?.find((l) => l.colaborador_id === sel);
  const item = (l: Linha) => (
    <button key={l.colaborador_id} type="button" className="item-lista" aria-current={sel === l.colaborador_id} onClick={() => setSel(l.colaborador_id)}>
      <Farol cor={l.decisao ? 'verde' : 'amarelo'} />
      <span><strong>{l.nome}</strong><small>{l.cargo_anterior} para {l.cargo_atual}</small></span>
      <small>{l.decisao ? nomesAcao[l.decisao] : dataBR(l.data_movimentacao)}</small>
    </button>
  );
  return (
    <Pagina titulo="Movimentações" apoio="Quem mudou de cargo: classifique, confira a sugestão e confirme. Total e parcial vão para A planejar em Turmas.">
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {lista.carregando && !lista.dados && <Carregando />}
      <div className="mestre-detalhe">
        <div>
          <p className="grupo-titulo">A classificar ({pendentes.length})</p>
          <div className="lista-turmas">{pendentes.map(item)}{lista.dados && !pendentes.length && <p className="vazio">Nada a classificar.</p>}</div>
          {!!feitas.length && <><p className="grupo-titulo">Classificadas ({feitas.length})</p><div className="lista-turmas">{feitas.map(item)}</div></>}
        </div>
        {linha ? <Classificar key={linha.colaborador_id} l={linha} aoMudar={() => void lista.recarregar()} /> : <p className="vazio">Escolha uma pessoa.</p>}
      </div>
    </Pagina>
  );
}

function Classificar({ l, aoMudar }: { l: Linha; aoMudar: () => void }) {
  const [tipo, setTipo] = useState('');
  const [sug, setSug] = useState<Sugestao | null>(null);
  const [acao, setAcao] = useState('');
  const [parcial, setParcial] = useState<string[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  async function escolher(t: string) {
    setTipo(t); setSug(null); setErro(null); setOk(null);
    if (!t) return;
    try {
      const s = await rpc<Sugestao>('sugerir_reciclagem', { p_colaborador: l.colaborador_id, p_tipo: t });
      setSug(s); setAcao(s.acao_sugerida); setParcial(s.treinamentos_parcial);
    } catch (e) { setErro(textoErro(e)); }
  }
  async function confirmar() {
    setErro(null);
    try {
      await rpc('confirmar_reciclagem', { p_colaborador: l.colaborador_id, p_tipo: tipo, p_acao: acao, p_treinamentos: parcial });
      setOk(acao === 'dispensa' ? 'Dispensa confirmada. Baixe o Termo para assinatura.' : 'Confirmado. Os treinamentos entraram em A planejar.');
      aoMudar();
    } catch (e) { setErro(textoErro(e)); }
  }
  return (
    <aside className="painel">
      <h2>{l.nome}</h2>
      <dl className="dados">
        <div><dt>Cargo anterior</dt><dd>{l.cargo_anterior}</dd></div>
        <div><dt>Cargo atual</dt><dd>{l.cargo_atual}</dd></div>
        <div><dt>Movimentação</dt><dd>{dataBR(l.data_movimentacao)}</dd></div>
      </dl>
      {l.decisao && <p className="aviso aviso-info">Decisão atual: {nomesAcao[l.decisao]}, em {dataBR(l.decidido_em)}. Uma nova confirmação substitui esta.</p>}
      <Campo rotulo="Tipo de movimentação"><select value={tipo} onChange={(e) => void escolher(e.target.value)}><option value="">Escolha</option>{Object.entries(nomesMovimentacao).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
      {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
      {ok && <p className="aviso aviso-ok" role="status">{ok}</p>}
      {sug && (
        <>
          <p className="aviso aviso-info">Sugestão do sistema: <strong>{nomesAcao[sug.acao_sugerida]}</strong>. {sug.tempo_empresa_meses} meses de empresa, movimentação {sug.movimentacao_recente ? 'recente' : 'não recente'}.</p>
          <Campo rotulo="Ação final"><select value={acao} onChange={(e) => setAcao(e.target.value)}>{Object.entries(nomesAcao).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
          {acao === 'parcial' && (
            <fieldset className="campo-grupo"><legend>Treinamentos da reciclagem</legend>
              {sug.matriz_atual.map((t) => <label className="opcao" key={t.id}><input type="checkbox" checked={parcial.includes(t.id)} onChange={(e) => setParcial(e.target.checked ? [...parcial, t.id] : parcial.filter((x) => x !== t.id))} />{t.nome}{t.eh_politica ? ' (política)' : ''}</label>)}
            </fieldset>
          )}
          <div className="linha-acoes"><button className="botao" type="button" onClick={() => void confirmar()}>Confirmar classificação</button></div>
        </>
      )}
      {l.decisao === 'dispensa' && <div className="linha-acoes"><button className="botao botao-secundario" type="button" onClick={() => void rpc<SituacaoColaborador>('situacao_colaborador', { p_colaborador: l.colaborador_id }).then(gerarTermoDispensa).catch((e) => setErro(textoErro(e)))}>Baixar Termo de Dispensa</button></div>}
    </aside>
  );
}
