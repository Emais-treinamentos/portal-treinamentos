import { useState } from 'react';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Campo, FormDialogo } from '../componentes/Pecas';
import { textoErro, useDados } from '../lib/api';
import { enderecoDoSite, supabase } from '../lib/supabase';
import { nomesPerfil, type Perfil } from '../lib/sessao';

async function chamar(corpo: Record<string, unknown>) {
  const { data, error } = await supabase.functions.invoke('gerenciar-acesso', { body: { ...corpo, destino: enderecoDoSite } });
  if (error) {
    const r = (error as { context?: Response }).context;
    const j = r ? await r.json().catch(() => null) : null;
    throw new Error(j?.erro ?? 'Não foi possível concluir.');
  }
  return data as { link?: string };
}

export function Acessos() {
  const l = useDados(async () => (await supabase.from('usuarios').select('id, nome, email, perfil, ativo').order('nome')).data ?? []);
  const [novo, setNovo] = useState(false);
  const [link, setLink] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  return (
    <Pagina titulo="Acessos" apoio="Quem entra no portal e com qual perfil. Ninguém se cadastra sozinho." acoes={<button className="botao" type="button" onClick={() => setNovo(true)}>Novo acesso</button>}>
      {erro && <Mensagem tipo="erro" aoFechar={() => setErro(null)}>{erro}</Mensagem>}
      {link && <div className="aviso aviso-ok aviso-faixa"><span>Envie este link à pessoa para definir a senha: <input readOnly value={link} onFocus={(e) => e.target.select()} style={{ width: '100%' }} /></span><button className="botao botao-discreto" type="button" onClick={() => setLink(null)}>Fechar</button></div>}
      {l.carregando && !l.dados && <Carregando />}
      <div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Nome</th><th>E-mail</th><th>Perfil</th><th>Situação</th><th /></tr></thead>
        <tbody>{(l.dados ?? []).map((u) => (
          <tr key={u.id} className={u.ativo ? undefined : 'linha-inativa'}><td>{u.nome}</td><td>{u.email}</td><td>{nomesPerfil[u.perfil as Perfil]}</td><td>{u.ativo ? 'Ativo' : 'Inativo'}</td>
            <td className="linha-acoes">
              <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void chamar({ acao: 'link', usuario_id: u.id }).then((r) => setLink(r.link ?? null)).catch((e) => setErro(textoErro(e)))}>Gerar link</button>
              <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void chamar({ acao: 'ativar', usuario_id: u.id, ativo: !u.ativo }).then(() => l.recarregar()).catch((e) => setErro(textoErro(e)))}>{u.ativo ? 'Desativar' : 'Reativar'}</button>
            </td></tr>
        ))}</tbody></table></div>
      {novo && <NovoAcesso aoFechar={() => setNovo(false)} aoCriar={(k) => { setLink(k); void l.recarregar(); }} />}
    </Pagina>
  );
}

function NovoAcesso({ aoFechar, aoCriar }: { aoFechar: () => void; aoCriar: (link: string | null) => void }) {
  const cols = useDados(async () => (await supabase.from('colaboradores').select('id, nome, email').eq('ativo', true).order('nome')).data ?? []);
  const deps = useDados(async () => (await supabase.from('departamentos').select('id, nome').order('nome')).data ?? []);
  const [nome, setNome] = useState(''); const [email, setEmail] = useState(''); const [perfil, setPerfil] = useState('colaborador'); const [col, setCol] = useState(''); const [sel, setSel] = useState<string[]>([]);
  return (
    <FormDialogo titulo="Novo acesso" rotulo="Criar acesso" aoFechar={aoFechar} aoEnviar={async () => { const r = await chamar({ acao: 'criar', nome, email, perfil, colaborador_id: col || null, departamentos: sel }); aoCriar(r.link ?? null); }}>
      <Campo rotulo="Colaborador (opcional)"><select value={col} onChange={(e) => { const c = cols.dados?.find((x) => x.id === e.target.value); setCol(e.target.value); if (c) { setNome(c.nome); setEmail(c.email ?? ''); } }}><option value="">Sem vínculo</option>{(cols.dados ?? []).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></Campo>
      <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
      <Campo rotulo="E-mail"><input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
      <Campo rotulo="Perfil"><select value={perfil} onChange={(e) => setPerfil(e.target.value)}>{Object.entries(nomesPerfil).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Campo>
      {perfil === 'gestor' && <fieldset className="campo-grupo"><legend>Departamentos</legend>{(deps.dados ?? []).map((d) => <label className="opcao" key={d.id}><input type="checkbox" checked={sel.includes(d.id)} onChange={(e) => setSel(e.target.checked ? [...sel, d.id] : sel.filter((x) => x !== d.id))} />{d.nome}</label>)}</fieldset>}
    </FormDialogo>
  );
}
