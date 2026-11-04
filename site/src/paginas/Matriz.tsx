import { useState } from 'react';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { dataBR, rpc, textoErro, useDados } from '../lib/api';
import { supabase } from '../lib/supabase';

type Item = { treinamento_id: string; treinamento: string; marcado: boolean; vigente: boolean };

export function Matriz() {
  const revisoes = useDados(async () => (await supabase.from('matriz_revisoes').select('id, numero, status, descricao, data_inicio_vigencia').order('criado_em', { ascending: false })).data ?? []);
  const cargos = useDados(async () => (await supabase.from('cargos').select('id, nome, departamentos(nome)').eq('ativo', true).order('nome')).data ?? []);
  const [cargo, setCargo] = useState('');
  const quadro = useDados(() => (cargo ? rpc<Item[]>('matriz_do_cargo', { p_cargo: cargo }) : Promise.resolve([] as Item[])), [cargo]);
  const [erro, setErro] = useState<string | null>(null);
  const [janela, setJanela] = useState<'iniciar' | 'publicar' | null>(null);
  const aberta = revisoes.dados?.find((r) => r.status === 'aberta');
  async function acao(f: () => Promise<unknown>) {
    setErro(null);
    try { await f(); } catch (e) { setErro(textoErro(e)); }
    void revisoes.recarregar(); void quadro.recarregar();
  }
  const mudancas = (quadro.dados ?? []).filter((i) => i.marcado !== i.vigente);
  return (
    <Pagina titulo="Matriz" apoio="Cargo por treinamento, sempre por revisão. O que vale só muda quando a revisão é publicada."
      acoes={aberta ? (<><button className="botao" type="button" onClick={() => setJanela('publicar')}>Publicar {aberta.numero}</button><button className="botao botao-discreto" type="button" onClick={() => void acao(() => rpc('cancelar_revisao'))}>Cancelar revisão</button></>) : <button className="botao" type="button" onClick={() => setJanela('iniciar')}>Iniciar revisão</button>}>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      {aberta ? <p className="aviso aviso-alerta aviso-faixa">Revisão {aberta.numero} aberta: {aberta.descricao}</p> : <p className="aviso aviso-info aviso-faixa">Matriz travada. Inicie uma revisão para alterar.</p>}
      <Campo rotulo="Cargo"><select value={cargo} onChange={(e) => setCargo(e.target.value)}><option value="">Escolha um cargo</option>{(cargos.dados ?? []).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></Campo>
      {quadro.carregando && cargo && <Carregando />}
      {cargo && !!quadro.dados?.length && (
        <>
          {!!mudancas.length && <p className="apoio">{mudancas.length} mudança(s) nesta revisão para este cargo: {mudancas.map((m) => `${m.marcado ? 'entra' : 'sai'} ${m.treinamento}`).join('; ')}.</p>}
          <div className="quadro-matriz" style={{ marginTop: 12 }}>
            {quadro.dados.map((i) => <label className="opcao" key={i.treinamento_id}><input type="checkbox" disabled={!aberta} checked={i.marcado} onChange={(e) => void acao(() => rpc('alternar_vinculo', { p_cargo: cargo, p_treinamento: i.treinamento_id, p_marcar: e.target.checked }))} />{i.treinamento}</label>)}
          </div>
        </>
      )}
      <section className="bloco">
        <h2 className="bloco-titulo">Revisões</h2>
        {(revisoes.dados ?? []).map((r) => <div className="pessoa" key={r.id}><span>{r.numero}<small>{r.descricao}</small></span><small>{r.status}{r.data_inicio_vigencia ? `, desde ${dataBR(r.data_inicio_vigencia)}` : ''}</small></div>)}
      </section>
      {janela === 'iniciar' && <Iniciar aoFechar={() => setJanela(null)} aoSalvar={() => void revisoes.recarregar()} />}
      {janela === 'publicar' && <Publicar aoFechar={() => setJanela(null)} aoSalvar={() => { void revisoes.recarregar(); void quadro.recarregar(); }} />}
    </Pagina>
  );
}

function Iniciar({ aoFechar, aoSalvar }: { aoFechar: () => void; aoSalvar: () => void }) {
  const [d, setD] = useState('');
  return <FormDialogo titulo="Iniciar revisão" rotulo="Iniciar" aoFechar={aoFechar} aoEnviar={async () => { await rpc('iniciar_revisao', { p_descricao: d }); aoSalvar(); }}><Campo rotulo="O que muda nesta revisão"><textarea required rows={3} value={d} onChange={(e) => setD(e.target.value)} /></Campo></FormDialogo>;
}

function Publicar({ aoFechar, aoSalvar }: { aoFechar: () => void; aoSalvar: () => void }) {
  const [d, setD] = useState('');
  return <FormDialogo titulo="Publicar revisão" rotulo="Publicar" aoFechar={aoFechar} aoEnviar={async () => { await rpc('publicar_revisao', { p_vigencia: d || null }); aoSalvar(); }}><Campo rotulo="Vale a partir de (vazio para hoje)"><input type="date" value={d} onChange={(e) => setD(e.target.value)} /></Campo></FormDialogo>;
}
