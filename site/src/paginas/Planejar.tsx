import { useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { rpc, useDados } from '../lib/api';
import { supabase } from '../lib/supabase';

type Item = { chave: string; treinamento_id: string; treinamento: string; tipo: string; individual: boolean; cargos: { cargo_id: string; nome: string }[]; pessoas: { colaborador_id: string; nome: string; motivo: string }[] };
type Agenda = { data: string; hora_1: string; hora_2: string; email: string };
const vazio: Agenda = { data: '', hora_1: '', hora_2: '', email: '' };

export function Planejar() {
  const [params] = useSearchParams();
  const depts = useDados(async () => (await supabase.from('departamentos').select('id, nome').order('nome')).data ?? []);
  const cargos = useDados(async () => (await supabase.from('cargos').select('id, nome, departamento_id').eq('ativo', true).order('nome')).data ?? []);
  const [selDepts, setSelDepts] = useState<string[]>([]);
  const [selCargos, setSelCargos] = useState<string[]>(() => (params.get('cargos') ?? '').split(',').filter(Boolean));
  const [agendas, setAgendas] = useState<Record<string, Agenda>>({});
  const [marcas, setMarcas] = useState<Record<string, boolean>>({});
  const [erros, setErros] = useState<string[]>([]);
  const [confirmar, setConfirmar] = useState(false);
  const [aceite, setAceite] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const plano = useDados(() => rpc<Item[]>('planejar_treinamentos', { p_cargos: selCargos }), [selCargos.join(',')]);

  // Quem chega com cargos já escolhidos vê os departamentos deles marcados.
  const preparado = useRef(false);
  useEffect(() => {
    if (preparado.current || !cargos.dados) return;
    preparado.current = true;
    const ds = cargos.dados.filter((c) => selCargos.includes(c.id)).map((c) => c.departamento_id);
    if (ds.length) setSelDepts([...new Set(ds)]);
  }, [cargos.dados, selCargos]);

  const visiveis = (cargos.dados ?? []).filter((c) => selDepts.includes(c.departamento_id));
  function alternarDept(id: string, marcar: boolean) {
    setSelDepts(marcar ? [...selDepts, id] : selDepts.filter((x) => x !== id));
    if (!marcar) {
      const saem = (cargos.dados ?? []).filter((c) => c.departamento_id === id).map((c) => c.id);
      setSelCargos(selCargos.filter((x) => !saem.includes(x)));
    }
  }

  const itens = plano.dados ?? [];
  const marcado = (i: Item) => marcas[i.chave] ?? (i.pessoas.length > 0);
  const dosCargos = (i: Item) => i.cargos.some((c) => selCargos.includes(c.cargo_id));
  const reciclagem = itens.filter((i) => i.tipo === 'reciclagem' && !dosCargos(i));
  const principais = itens.filter((i) => dosCargos(i) && (i.pessoas.length > 0 || i.tipo === 'reciclagem'));
  const consolidados = principais.filter((i) => !i.individual && i.cargos.length > 1);
  const individuais = principais.filter((i) => i.individual || i.cargos.length === 1);
  const semPessoas = itens.filter((i) => dosCargos(i) && !i.pessoas.length && i.tipo !== 'reciclagem');
  const escolhidos = itens.filter(marcado);

  function validar() {
    const falta: string[] = [];
    escolhidos.forEach((i) => {
      const a = agendas[i.chave] ?? vazio;
      const f = [!a.data && 'data', !a.hora_1 && !a.hora_2 && 'horário', !a.email.trim() && 'e-mail do instrutor'].filter(Boolean);
      if (f.length) falta.push(`${i.treinamento}: falta ${f.join(', ')}`);
    });
    setErros(falta);
    if (!falta.length) { setAceite(false); setConfirmar(true); }
  }

  async function enviar() {
    const r = await rpc<{ criadas: number; consolidadas: number }>('enviar_planejamento', {
      p_itens: escolhidos.map((i) => ({ treinamento_id: i.treinamento_id, tipo: i.tipo, cargos: i.cargos.map((c) => c.cargo_id), ...(agendas[i.chave] ?? vazio) })),
    });
    const partes = [r.criadas && `${r.criadas} turma(s) criada(s), com aviso na fila de envio`, r.consolidadas && `${r.consolidadas} consolidada(s) em turma já aberta`].filter(Boolean);
    setMsg(`${partes.join('. ')}.`);
    setSelCargos([]); setSelDepts([]); setAgendas({}); setMarcas({}); setErros([]);
  }

  const cartao = (i: Item) => <CartaoPlano key={i.chave} i={i} marcado={marcado(i)} agenda={agendas[i.chave] ?? vazio}
    aoMarcar={(v) => setMarcas({ ...marcas, [i.chave]: v })}
    aoMudar={(a) => setAgendas({ ...agendas, [i.chave]: a })} />;

  return (
    <Pagina titulo="Planejar treinamentos" apoio="Selecione departamentos e cargos para consolidar os treinamentos e enviar as sugestões de agenda.">
      {msg && <Mensagem tipo="ok" aoFechar={() => setMsg(null)}>{msg} <Link className="link" to="/turmas?etapa=aguardando_instrutor">Ver turmas</Link></Mensagem>}
      {plano.erro && <Mensagem tipo="erro">{plano.erro}</Mensagem>}

      <section className="plano-etapa">
        <h2>1. Selecione os departamentos</h2>
        <div className="plano-opcoes">{(depts.dados ?? []).map((d) => (
          <label className="opcao" key={d.id}><input type="checkbox" checked={selDepts.includes(d.id)} onChange={(e) => alternarDept(d.id, e.target.checked)} />{d.nome}</label>
        ))}</div>
      </section>

      {selDepts.length > 0 && (
        <section className="plano-etapa">
          <h2>2. Selecione os cargos</h2>
          {!visiveis.length && <p className="apoio">Nenhum cargo nos departamentos selecionados.</p>}
          <div className="plano-opcoes">{visiveis.map((c) => (
            <label className="opcao" key={c.id}><input type="checkbox" checked={selCargos.includes(c.id)} onChange={(e) => setSelCargos(e.target.checked ? [...selCargos, c.id] : selCargos.filter((x) => x !== c.id))} />{c.nome}</label>
          ))}</div>
        </section>
      )}

      {plano.carregando && !plano.dados && <Carregando />}

      {selCargos.length > 0 && plano.dados && !principais.length && !semPessoas.length && <p className="vazio">Nenhum treinamento vinculado aos cargos selecionados.</p>}

      {consolidados.length > 0 && (
        <section className="plano-etapa">
          <h2>Treinamentos consolidados <small>{consolidados.length}</small></h2>
          <p className="apoio">Aparecem em mais de um cargo selecionado.</p>
          {consolidados.map(cartao)}
        </section>
      )}
      {individuais.length > 0 && (
        <section className="plano-etapa">
          <h2>Treinamentos individuais <small>{individuais.length}</small></h2>
          <p className="apoio">De apenas um cargo, ou com agenda separada por cargo.</p>
          {individuais.map(cartao)}
        </section>
      )}
      {reciclagem.length > 0 && (
        <section className="plano-etapa">
          <h2>Reciclagem pendente <small>{reciclagem.length}</small></h2>
          <p className="apoio">Preencha a agenda antes de enviar ao instrutor.</p>
          {reciclagem.map(cartao)}
        </section>
      )}
      {semPessoas.length > 0 && (
        <details className="plano-etapa plano-recolhido">
          <summary>Na matriz, sem ninguém para convocar agora <small>{semPessoas.length}</small></summary>
          <p className="apoio">Já realizados, já em turma ou fora da janela de convocação. Marque só se quiser abrir turma mesmo assim.</p>
          {semPessoas.map(cartao)}
        </details>
      )}

      {erros.length > 0 && <Mensagem tipo="erro">{erros.slice(0, 4).join('. ')}{erros.length > 4 ? ` e mais ${erros.length - 4}.` : '.'}</Mensagem>}

      {itens.length > 0 && (
        <div className="plano-envio">
          <button className="botao" type="button" disabled={!escolhidos.length} onClick={validar}>Enviar sugestão de agenda ({escolhidos.length})</button>
        </div>
      )}

      {confirmar && (
        <FormDialogo titulo="Confirmar envio da sugestão de agenda" rotulo="Confirmar e enviar" desabilitar={!aceite} aoFechar={() => setConfirmar(false)} aoEnviar={enviar}>
          <p className="apoio">{escolhidos.length} treinamento(s) serão enviados aos instrutores.</p>
          <label className="opcao opcao-termo"><input type="checkbox" checked={aceite} onChange={(e) => setAceite(e.target.checked)} />Confirmo que todos os participantes estão com cadastros ativos e treinamentos atualizados.</label>
        </FormDialogo>
      )}
    </Pagina>
  );
}

function CartaoPlano({ i, marcado, agenda, aoMarcar, aoMudar }: { i: Item; marcado: boolean; agenda: Agenda; aoMarcar: (v: boolean) => void; aoMudar: (a: Agenda) => void }) {
  const nomes = i.pessoas.map((p) => p.nome).join(', ');
  return (
    <div className="plano-cartao">
      <div className="plano-cartao-topo">
        <label className="opcao"><input type="checkbox" checked={marcado} onChange={(e) => aoMarcar(e.target.checked)} /><strong>{i.treinamento}</strong></label>
        {i.tipo === 'reciclagem' && <span className="selo-urgente">Reciclagem</span>}
        <small>{i.pessoas.length === 1 ? '1 pessoa' : `${i.pessoas.length} pessoas`}</small>
      </div>
      <p className="plano-cartao-apoio">Cargos: {i.cargos.map((c) => c.nome).join(', ')}{nomes && <><br />Pessoas: {nomes}</>}</p>
      {marcado && (
        <div className="plano-campos">
          <Campo rotulo="Data sugerida"><input type="date" value={agenda.data} onChange={(e) => aoMudar({ ...agenda, data: e.target.value })} /></Campo>
          <Campo rotulo="Horário opção 1"><input type="time" value={agenda.hora_1} onChange={(e) => aoMudar({ ...agenda, hora_1: e.target.value })} /></Campo>
          <Campo rotulo="Horário opção 2"><input type="time" value={agenda.hora_2} onChange={(e) => aoMudar({ ...agenda, hora_2: e.target.value })} /></Campo>
          <Campo rotulo="E-mail do instrutor"><input type="email" value={agenda.email} onChange={(e) => aoMudar({ ...agenda, email: e.target.value })} /></Campo>
        </div>
      )}
    </div>
  );
}
