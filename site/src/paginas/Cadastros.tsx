import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { CadastroColaboradores } from './Colaboradores';
import { Matriz } from './Matriz';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { cargaTexto, rpc, textoErro, useDados } from '../lib/api';
import { supabase } from '../lib/supabase';

type Treinamento = { id: string; nome: string; carga_minutos: number; eh_politica: boolean; individual_por_colaborador: boolean; ativo: boolean };

const abas = [['colaboradores', 'Colaboradores'], ['cargos', 'Cargos'], ['treinamentos', 'Treinamentos'], ['matriz', 'Matriz'], ['departamentos', 'Departamentos'], ['salas', 'Salas']] as const;
type Aba = (typeof abas)[number][0];

export function Cadastros() {
  const [params] = useSearchParams();
  const [aba, setAba] = useState<Aba>((params.get('aba') as Aba) ?? 'colaboradores');
  return (
    <Pagina titulo="Cadastros" apoio="Gerencie colaboradores, cargos, treinamentos e a matriz de obrigatoriedade.">
      <div className="chips chips-filtro" role="group" aria-label="Cadastros">
        {abas.map(([a, nome]) => <button key={a} type="button" className="chip" aria-pressed={aba === a} onClick={() => setAba(a)}>{nome}</button>)}
      </div>
      {aba === 'colaboradores' && <CadastroColaboradores />}
      {aba === 'cargos' && <Cargos />}
      {aba === 'treinamentos' && <Treinamentos />}
      {aba === 'matriz' && <Matriz />}
      {aba === 'departamentos' && <Departamentos />}
      {aba === 'salas' && <Salas />}
    </Pagina>
  );
}

const useVinculos = () => useDados(() => rpc<{ cargo_id: string; treinamento_id: string }[]>('matriz_vigente_hoje'));

async function ok<T extends { error: { message: string } | null }>(p: PromiseLike<T>) {
  const r = await p;
  if (r.error) throw new Error(/duplicate|unique/i.test(r.error.message) ? 'Já existe um cadastro com este nome' : r.error.message);
  return r;
}

function Treinamentos() {
  const l = useDados(async () => ((await supabase.from('treinamentos').select('*').order('nome')).data ?? []) as Treinamento[]);
  const v = useVinculos();
  const [ed, setEd] = useState<Treinamento | 'novo' | null>(null);
  const [busca, setBusca] = useState(''); const [status, setStatus] = useState('');
  const q = busca.trim().toLowerCase();
  const linhas = (l.dados ?? []).filter((t) => (!q || t.nome.toLowerCase().includes(q)) && (!status || (status === 'ativos') === t.ativo));
  return (
    <>
      <div className="filtros cadastro-topo">
        <Campo rotulo="Pesquisar"><input type="search" value={busca} onChange={(e) => setBusca(e.target.value)} /></Campo>
        <Campo rotulo="Status"><select value={status} onChange={(e) => setStatus(e.target.value)}><option value="">Todos</option><option value="ativos">Ativos</option><option value="inativos">Inativos</option></select></Campo>
        <button className="botao" type="button" onClick={() => setEd('novo')}>Novo treinamento</button>
      </div>
      <div className="tabela-rolagem">
        <table className="tabela"><thead><tr><th>Treinamento</th><th>Carga horária</th><th>Cargos vinculados</th><th>Status</th><th>Ações</th></tr></thead>
          <tbody>{linhas.map((t) => <tr key={t.id}><td>{t.nome}</td><td>{cargaTexto(t.carga_minutos)}</td><td>{(v.dados ?? []).filter((x) => x.treinamento_id === t.id).length}</td><td>{t.ativo ? 'Ativo' : 'Inativo'}</td><td><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => setEd(t)}>Editar</button></td></tr>)}</tbody>
        </table>
      </div>
      {ed && <EditarTreinamento t={ed === 'novo' ? null : ed} aoFechar={() => setEd(null)} aoSalvar={() => void l.recarregar()} />}
    </>
  );
}

function EditarTreinamento({ t, aoFechar, aoSalvar }: { t: Treinamento | null; aoFechar: () => void; aoSalvar: () => void }) {
  const [nome, setNome] = useState(t?.nome ?? ''); const [carga, setCarga] = useState(t ? cargaTexto(t.carga_minutos) : '01:00');
  const [pol, setPol] = useState(t?.eh_politica ?? false); const [ind, setInd] = useState(t?.individual_por_colaborador ?? false); const [ativo, setAtivo] = useState(t?.ativo ?? true);
  return (
    <FormDialogo titulo={t ? 'Editar treinamento' : 'Novo treinamento'} rotulo="Salvar" aoFechar={aoFechar} aoEnviar={async () => {
      const [h, m] = carga.split(':').map(Number); const corpo = { nome: nome.trim(), carga_minutos: h * 60 + m, eh_politica: pol, individual_por_colaborador: ind, ativo };
      if (!corpo.carga_minutos) throw new Error('Informe a carga horária');
      await ok(t ? supabase.from('treinamentos').update(corpo).eq('id', t.id) : supabase.from('treinamentos').insert(corpo));
      aoSalvar();
    }}>
      <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
      <Campo rotulo="Carga horária"><input type="time" required value={carga} onChange={(e) => setCarga(e.target.value)} /></Campo>
      <label className="opcao"><input type="checkbox" checked={pol} onChange={(e) => setPol(e.target.checked)} />É política</label>
      <label className="opcao"><input type="checkbox" checked={ind} onChange={(e) => setInd(e.target.checked)} />Uma turma por cargo, sem consolidar</label>
      <label className="opcao"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} />Ativo</label>
    </FormDialogo>
  );
}

function Cargos() {
  const l = useDados(async () => (await supabase.from('cargos').select('id, nome, ativo, departamento_id, departamentos(nome)').order('nome')).data ?? []);
  const deps = useDados(async () => (await supabase.from('departamentos').select('id, nome, ativo').order('nome')).data ?? []);
  const v = useVinculos();
  const [novo, setNovo] = useState(false); const [nome, setNome] = useState(''); const [dep, setDep] = useState('');
  const [editando, setEditando] = useState<{ id: string; nome: string; departamento_id: string } | null>(null);
  const [filtro, setFiltro] = useState(''); const [ativos, setAtivos] = useState(true);
  const [erro, setErro] = useState<string | null>(null);
  const todos = l.dados ?? [];
  const linhas = todos.filter((c) => c.ativo === ativos && (!filtro || c.departamento_id === filtro));
  return (
    <>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      <div className="filtros cadastro-topo">
        <Campo rotulo="Departamento"><select value={filtro} onChange={(e) => setFiltro(e.target.value)}><option value="">Todos</option>{(deps.dados ?? []).map((d) => <option key={d.id} value={d.id}>{d.nome}</option>)}</select></Campo>
        <div className="chips" role="group" aria-label="Situação do cargo">
          <button type="button" className="chip" aria-pressed={ativos} onClick={() => setAtivos(true)}>Ativos<small>{todos.filter((c) => c.ativo).length}</small></button>
          <button type="button" className="chip" aria-pressed={!ativos} onClick={() => setAtivos(false)}>Inativos<small>{todos.filter((c) => !c.ativo).length}</small></button>
        </div>
        <button className="botao" type="button" onClick={() => setNovo(true)}>Novo cargo</button>
      </div>
      <div className="tabela-rolagem">
        <table className="tabela"><thead><tr><th>Cargo</th><th>Departamento</th><th>Treinamentos</th><th>Status</th><th>Ações</th></tr></thead>
          <tbody>{linhas.map((c) => { const d = c.departamentos as unknown as { nome: string } | null; return <tr key={c.id}><td>{c.nome}</td><td>{d?.nome}</td><td>{(v.dados ?? []).filter((x) => x.cargo_id === c.id).length}</td><td>{c.ativo ? 'Ativo' : 'Inativo'}</td><td><span className="linha-acoes"><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => setEditando({ id: c.id, nome: c.nome, departamento_id: c.departamento_id })}>Editar</button><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => void ok(supabase.from('cargos').update({ ativo: !c.ativo }).eq('id', c.id)).then(() => l.recarregar()).catch((e) => setErro(textoErro(e)))}>{c.ativo ? 'Inativar' : 'Reativar'}</button></span></td></tr>; })}</tbody>
        </table>
      </div>
      {novo && <FormDialogo titulo="Novo cargo" rotulo="Salvar" aoFechar={() => setNovo(false)} aoEnviar={async () => { await ok(supabase.from('cargos').insert({ nome: nome.trim(), departamento_id: dep })); setNome(''); void l.recarregar(); }}>
        <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        <Campo rotulo="Departamento"><select required value={dep} onChange={(e) => setDep(e.target.value)}><option value="">Escolha</option>{(deps.dados ?? []).filter((d) => d.ativo).map((d) => <option key={d.id} value={d.id}>{d.nome}</option>)}</select></Campo>
      </FormDialogo>}
      {editando && <EditarCargo c={editando} deps={deps.dados ?? []} aoFechar={() => setEditando(null)} aoSalvar={() => void l.recarregar()} />}
    </>
  );
}

function EditarCargo({ c, deps, aoFechar, aoSalvar }: { c: { id: string; nome: string; departamento_id: string }; deps: { id: string; nome: string; ativo: boolean }[]; aoFechar: () => void; aoSalvar: () => void }) {
  const [nome, setNome] = useState(c.nome); const [dep, setDep] = useState(c.departamento_id);
  return (
    <FormDialogo titulo="Editar cargo" rotulo="Salvar" aoFechar={aoFechar} desabilitar={!nome.trim() || !dep} aoEnviar={async () => { await ok(supabase.from('cargos').update({ nome: nome.trim(), departamento_id: dep }).eq('id', c.id)); aoSalvar(); }}>
      <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
      <Campo rotulo="Departamento"><select required value={dep} onChange={(e) => setDep(e.target.value)}>{deps.filter((d) => d.ativo || d.id === c.departamento_id).map((d) => <option key={d.id} value={d.id}>{d.nome}</option>)}</select></Campo>
      <p className="apoio">O novo nome vale em todo o portal. Os treinamentos do cargo não mudam.</p>
      {dep !== c.departamento_id && <p className="apoio">Os colaboradores deste cargo passam para o novo departamento.</p>}
    </FormDialogo>
  );
}

function Departamentos() {
  const l = useDados(async () => (await supabase.from('departamentos').select('id, nome, ativo').order('nome')).data ?? []);
  const cargos = useDados(async () => (await supabase.from('cargos').select('departamento_id, ativo')).data ?? []);
  const pessoas = useDados(async () => (await supabase.from('colaboradores').select('departamento_id, ativo')).data ?? []);
  const [nome, setNome] = useState(''); const [erro, setErro] = useState<string | null>(null);
  const [ativos, setAtivos] = useState(true);
  const [editando, setEditando] = useState<{ id: string; nome: string } | null>(null);
  const todos = l.dados ?? [];
  const linhas = todos.filter((d) => d.ativo === ativos);
  const conta = (lista: { departamento_id: string | null; ativo: boolean }[] | null, id: string) => (lista ?? []).filter((x) => x.departamento_id === id && x.ativo).length;
  const alternar = (d: { id: string; ativo: boolean }) => {
    setErro(null);
    void ok(supabase.from('departamentos').update({ ativo: !d.ativo }).eq('id', d.id)).then(() => l.recarregar()).catch((x) => setErro(textoErro(x)));
  };
  return (
    <>
      {erro && <Mensagem tipo="erro" aoFechar={() => setErro(null)}>{erro}</Mensagem>}
      <form className="filtros cadastro-topo" onSubmit={(e) => { e.preventDefault(); void ok(supabase.from('departamentos').insert({ nome: nome.trim() })).then(() => { setNome(''); setErro(null); return l.recarregar(); }).catch((x) => setErro(textoErro(x))); }}>
        <Campo rotulo="Novo departamento"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        <button className="botao" type="submit">Incluir</button>
      </form>
      <div className="chips chips-filtro" role="group" aria-label="Situação do departamento">
        <button type="button" className="chip" aria-pressed={ativos} onClick={() => setAtivos(true)}>Ativos<small>{todos.filter((d) => d.ativo).length}</small></button>
        <button type="button" className="chip" aria-pressed={!ativos} onClick={() => setAtivos(false)}>Inativos<small>{todos.filter((d) => !d.ativo).length}</small></button>
      </div>
      <div className="tabela-rolagem">
        <table className="tabela"><thead><tr><th>Departamento</th><th>Cargos ativos</th><th>Colaboradores ativos</th><th>Ações</th></tr></thead>
          <tbody>
            {l.dados && !linhas.length && <tr><td colSpan={4}>{ativos ? 'Nenhum departamento ativo.' : 'Nenhum departamento inativo.'}</td></tr>}
            {linhas.map((d) => <tr key={d.id}><td>{d.nome}</td><td>{conta(cargos.dados, d.id)}</td><td>{conta(pessoas.dados, d.id)}</td><td><span className="linha-acoes"><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => setEditando(d)}>Editar</button><button className="botao botao-secundario botao-pequeno" type="button" onClick={() => alternar(d)}>{d.ativo ? 'Inativar' : 'Reativar'}</button></span></td></tr>)}
          </tbody>
        </table>
      </div>
      {editando && <EditarDepartamento d={editando} aoFechar={() => setEditando(null)} aoSalvar={() => void l.recarregar()} />}
    </>
  );
}

function EditarDepartamento({ d, aoFechar, aoSalvar }: { d: { id: string; nome: string }; aoFechar: () => void; aoSalvar: () => void }) {
  const [nome, setNome] = useState(d.nome);
  return (
    <FormDialogo titulo="Editar departamento" rotulo="Salvar" aoFechar={aoFechar} desabilitar={!nome.trim()} aoEnviar={async () => { await ok(supabase.from('departamentos').update({ nome: nome.trim() }).eq('id', d.id)); aoSalvar(); }}>
      <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
      <p className="apoio">O novo nome vale em todo o portal. Cargos e colaboradores continuam ligados a este departamento.</p>
    </FormDialogo>
  );
}

function Salas() {
  const l = useDados(async () => JSON.parse((await supabase.from('parametros').select('valor').eq('chave', 'salas').single()).data?.valor ?? '[]') as string[]);
  const [nome, setNome] = useState(''); const [erro, setErro] = useState<string | null>(null);
  const salvar = (salas: string[]) => ok(supabase.from('parametros').update({ valor: JSON.stringify(salas) }).eq('chave', 'salas')).then(() => { setNome(''); setErro(null); return l.recarregar(); }).catch((x) => setErro(textoErro(x)));
  return (
    <>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      <form className="linha-botoes" onSubmit={(e) => { e.preventDefault(); void salvar([...(l.dados ?? []), nome.trim()]); }}>
        <Campo rotulo="Nova sala"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        <button className="botao" type="submit">Incluir</button>
      </form>
      {(l.dados ?? []).map((s) => <div className="pessoa" key={s}><span>{s}</span><button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void salvar((l.dados ?? []).filter((x) => x !== s))}>Retirar</button></div>)}
    </>
  );
}
