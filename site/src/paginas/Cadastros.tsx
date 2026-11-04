import { useState } from 'react';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { cargaTexto, textoErro, useDados } from '../lib/api';
import { supabase } from '../lib/supabase';

type Treinamento = { id: string; nome: string; carga_minutos: number; eh_politica: boolean; individual_por_colaborador: boolean; ativo: boolean };

export function Cadastros() {
  const [aba, setAba] = useState<'treinamentos' | 'cargos' | 'departamentos' | 'salas'>('treinamentos');
  return (
    <Pagina titulo="Cadastros" apoio="Colaboradores ficam na tela Colaboradores, e a matriz, na tela Matriz.">
      <div className="chips chips-filtro" role="group">
        {(['treinamentos', 'cargos', 'departamentos', 'salas'] as const).map((a) => <button key={a} type="button" className="chip" aria-pressed={aba === a} onClick={() => setAba(a)}>{a[0].toUpperCase() + a.slice(1)}</button>)}
      </div>
      {aba === 'treinamentos' && <Treinamentos />}
      {aba === 'cargos' && <Cargos />}
      {aba === 'departamentos' && <Departamentos />}
      {aba === 'salas' && <Salas />}
    </Pagina>
  );
}

async function ok<T extends { error: { message: string } | null }>(p: PromiseLike<T>) {
  const r = await p;
  if (r.error) throw new Error(/duplicate|unique/i.test(r.error.message) ? 'Já existe um cadastro com este nome' : r.error.message);
  return r;
}

function Treinamentos() {
  const l = useDados(async () => ((await supabase.from('treinamentos').select('*').order('nome')).data ?? []) as Treinamento[]);
  const [ed, setEd] = useState<Treinamento | 'novo' | null>(null);
  return (
    <>
      <button className="botao" type="button" onClick={() => setEd('novo')}>Novo treinamento</button>
      <div className="tabela-rolagem" style={{ marginTop: 12 }}>
        <table className="tabela"><thead><tr><th>Treinamento</th><th>Carga</th><th>Política</th><th>Individual</th><th>Situação</th><th /></tr></thead>
          <tbody>{(l.dados ?? []).map((t) => <tr key={t.id}><td>{t.nome}</td><td>{cargaTexto(t.carga_minutos)}</td><td>{t.eh_politica ? 'Sim' : 'Não'}</td><td>{t.individual_por_colaborador ? 'Sim' : 'Não'}</td><td>{t.ativo ? 'Ativo' : 'Inativo'}</td><td><button className="botao botao-discreto botao-pequeno" type="button" onClick={() => setEd(t)}>Editar</button></td></tr>)}</tbody>
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
  const deps = useDados(async () => (await supabase.from('departamentos').select('id, nome').order('nome')).data ?? []);
  const [novo, setNovo] = useState(false); const [nome, setNome] = useState(''); const [dep, setDep] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  return (
    <>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      <button className="botao" type="button" onClick={() => setNovo(true)}>Novo cargo</button>
      <div className="tabela-rolagem" style={{ marginTop: 12 }}>
        <table className="tabela"><thead><tr><th>Cargo</th><th>Departamento</th><th>Situação</th><th /></tr></thead>
          <tbody>{(l.dados ?? []).map((c) => { const d = c.departamentos as unknown as { nome: string } | null; return <tr key={c.id}><td>{c.nome}</td><td>{d?.nome}</td><td>{c.ativo ? 'Ativo' : 'Inativo'}</td><td><button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void ok(supabase.from('cargos').update({ ativo: !c.ativo }).eq('id', c.id)).then(() => l.recarregar()).catch((e) => setErro(textoErro(e)))}>{c.ativo ? 'Inativar' : 'Reativar'}</button></td></tr>; })}</tbody>
        </table>
      </div>
      {novo && <FormDialogo titulo="Novo cargo" rotulo="Salvar" aoFechar={() => setNovo(false)} aoEnviar={async () => { await ok(supabase.from('cargos').insert({ nome: nome.trim(), departamento_id: dep })); setNome(''); void l.recarregar(); }}>
        <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        <Campo rotulo="Departamento"><select required value={dep} onChange={(e) => setDep(e.target.value)}><option value="">Escolha</option>{(deps.dados ?? []).map((d) => <option key={d.id} value={d.id}>{d.nome}</option>)}</select></Campo>
      </FormDialogo>}
    </>
  );
}

function Departamentos() {
  const l = useDados(async () => (await supabase.from('departamentos').select('id, nome').order('nome')).data ?? []);
  const [nome, setNome] = useState(''); const [erro, setErro] = useState<string | null>(null);
  return (
    <>
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      <form className="linha-botoes" onSubmit={(e) => { e.preventDefault(); void ok(supabase.from('departamentos').insert({ nome: nome.trim() })).then(() => { setNome(''); setErro(null); return l.recarregar(); }).catch((x) => setErro(textoErro(x))); }}>
        <Campo rotulo="Novo departamento"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
        <button className="botao" type="submit">Incluir</button>
      </form>
      {(l.dados ?? []).map((d) => <div className="pessoa" key={d.id}><span>{d.nome}</span></div>)}
    </>
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
