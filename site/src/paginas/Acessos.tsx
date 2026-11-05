import { useEffect, useState } from 'react';
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

const abas = [['usuarios', 'Usuários'], ['regras', 'Regras'], ['emails', 'E-mails']] as const;
type Aba = (typeof abas)[number][0];
const apoios: Record<Aba, string> = {
  usuarios: 'Quem entra no portal e com qual perfil. Ninguém se cadastra sozinho.',
  regras: 'Prazos e critérios do portal. A mudança vale daqui para frente e fica registrada no histórico.',
  emails: 'Os textos que o n8n envia. Os dados entram sozinhos nos campos entre chaves.',
};

export function Acessos() {
  const [aba, setAba] = useState<Aba>('usuarios');
  const [novo, setNovo] = useState(false);
  return (
    <Pagina titulo="Acessos" apoio={apoios[aba]} acoes={aba === 'usuarios' ? <button className="botao" type="button" onClick={() => setNovo(true)}>Novo acesso</button> : undefined}>
      <div className="chips chips-filtro" role="group" aria-label="Acessos">
        {abas.map(([a, nome]) => <button key={a} type="button" className="chip" aria-pressed={aba === a} onClick={() => setAba(a)}>{nome}</button>)}
      </div>
      {aba === 'usuarios' && <Usuarios novo={novo} aoFecharNovo={() => setNovo(false)} />}
      {aba === 'regras' && <Regras />}
      {aba === 'emails' && <ModelosEmail />}
    </Pagina>
  );
}

function Usuarios({ novo, aoFecharNovo }: { novo: boolean; aoFecharNovo: () => void }) {
  const l = useDados(async () => (await supabase.from('usuarios').select('id, nome, email, perfil, ativo, colaborador_id').order('nome')).data ?? []);
  const cols = useDados(async () => (await supabase.from('colaboradores').select('id, nome, email, ativo').order('nome')).data ?? []);
  const [editar, setEditar] = useState<Acesso | null>(null);
  const [link, setLink] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  return (
    <>
      {erro && <Mensagem tipo="erro" aoFechar={() => setErro(null)}>{erro}</Mensagem>}
      {link && <div className="aviso aviso-ok aviso-faixa"><span>Envie este link à pessoa para definir a senha: <input readOnly value={link} onFocus={(e) => e.target.select()} style={{ width: '100%' }} /></span><button className="botao botao-discreto" type="button" onClick={() => setLink(null)}>Fechar</button></div>}
      {l.carregando && !l.dados && <Carregando />}
      <div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Nome</th><th>E-mail</th><th>Perfil</th><th>Colaborador</th><th>Situação</th><th /></tr></thead>
        <tbody>{(l.dados ?? []).map((u) => (
          <tr key={u.id} className={u.ativo ? undefined : 'linha-inativa'}><td>{u.nome}</td><td>{u.email}</td><td>{textoPerfil(u.perfil as Perfil)}</td><td>{cols.dados?.find((c) => c.id === u.colaborador_id)?.nome ?? 'Sem vínculo'}</td><td>{u.ativo ? 'Ativo' : 'Inativo'}</td>
            <td className="linha-acoes">
              <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => setEditar(u as Acesso)}>Editar</button>
              <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void chamar({ acao: 'link', usuario_id: u.id }).then((r) => setLink(r.link ?? null)).catch((e) => setErro(textoErro(e)))}>Gerar link</button>
              <button className="botao botao-discreto botao-pequeno" type="button" onClick={() => void chamar({ acao: 'ativar', usuario_id: u.id, ativo: !u.ativo }).then(() => l.recarregar()).catch((e) => setErro(textoErro(e)))}>{u.ativo ? 'Desativar' : 'Reativar'}</button>
            </td></tr>
        ))}</tbody></table></div>
      {editar && <EditarAcesso u={editar} colaboradores={cols.dados ?? []} aoFechar={() => setEditar(null)} aoSalvar={() => void l.recarregar()} />}
      {novo && <NovoAcesso aoFechar={aoFecharNovo} aoCriar={(k) => { setLink(k); void l.recarregar(); }} />}
    </>
  );
}

type Acesso = { id: string; nome: string; email: string; perfil: Perfil; ativo: boolean; colaborador_id: string | null };
// Gestor e Gente e Gestão também entram como instrutor, escolhendo o perfil ao entrar.
const textoPerfil = (p: Perfil) => (p === 'admin' || p === 'gestor' ? `${nomesPerfil[p]} e Instrutor` : nomesPerfil[p]);

function EditarAcesso({ u, colaboradores, aoFechar, aoSalvar }: { u: Acesso; colaboradores: { id: string; nome: string; ativo: boolean }[]; aoFechar: () => void; aoSalvar: () => void }) {
  const deps = useDados(async () => (await supabase.from('departamentos').select('id, nome').order('nome')).data ?? []);
  const atuais = useDados(async () => (await supabase.from('usuarios_departamentos').select('departamento_id').eq('usuario_id', u.id)).data ?? []);
  const [nome, setNome] = useState(u.nome); const [email, setEmail] = useState(u.email); const [perfil, setPerfil] = useState<Perfil>(u.perfil); const [col, setCol] = useState(u.colaborador_id ?? ''); const [sel, setSel] = useState<string[] | null>(null);
  const marcados = sel ?? (atuais.dados ?? []).map((d) => d.departamento_id as string);
  const opcoes = colaboradores.filter((c) => c.ativo || c.id === u.colaborador_id);
  return (
    <FormDialogo titulo="Editar acesso" rotulo="Salvar" aoFechar={aoFechar} desabilitar={atuais.carregando} aoEnviar={async () => { await chamar({ acao: 'editar', usuario_id: u.id, nome, email, perfil, colaborador_id: col || null, departamentos: marcados }); aoSalvar(); }}>
      <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
      <Campo rotulo="E-mail"><input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
      {email.trim().toLowerCase() !== u.email && <p className="apoio">A pessoa passa a entrar com o novo e-mail. As turmas em que ela é instrutora acompanham a troca.</p>}
      <Campo rotulo="Perfil"><select value={perfil} onChange={(e) => setPerfil(e.target.value as Perfil)}>{Object.entries(nomesPerfil).map(([k, v]) => <option key={k} value={k}>{textoPerfil(k as Perfil) === v ? v : `${v} (também entra como Instrutor)`}</option>)}</select></Campo>
      <Campo rotulo="Colaborador"><select value={col} onChange={(e) => setCol(e.target.value)}><option value="">Sem vínculo</option>{opcoes.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}</select></Campo>
      {perfil === 'gestor' && <fieldset className="campo-grupo"><legend>Departamentos</legend>{(deps.dados ?? []).map((d) => <label className="opcao" key={d.id}><input type="checkbox" checked={marcados.includes(d.id)} onChange={(e) => setSel(e.target.checked ? [...marcados, d.id] : marcados.filter((x) => x !== d.id))} />{d.nome}</label>)}</fieldset>}
    </FormDialogo>
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

type Regra = { chave: string; valor: string; descricao: string; rotulo: string | null; grupo: string | null; tipo: 'inteiro' | 'data' | 'url' | 'lista'; minimo: number | null; maximo: number | null; unidade: string | null; ordem: number };

function Regras() {
  const l = useDados(async () => ((await supabase.from('parametros').select('*').order('ordem')).data ?? []) as Regra[]);
  const editaveis = (l.dados ?? []).filter((r) => r.tipo !== 'lista' && r.grupo);
  const grupos = ['Planejamento', 'Reciclagem', 'Avaliação de Eficácia', 'Colaboradores', 'E-mails'].filter((g) => editaveis.some((r) => r.grupo === g));
  return (
    <div className="regras">
      {l.erro && <Mensagem tipo="erro">{l.erro}</Mensagem>}
      {l.carregando && !l.dados && <Carregando />}
      {grupos.map((g) => (
        <section key={g} className="regras-grupo">
          <h2>{g}</h2>
          {editaveis.filter((r) => r.grupo === g).map((r) => <LinhaRegra key={r.chave} r={r} aoSalvar={() => void l.recarregar()} />)}
        </section>
      ))}
    </div>
  );
}

function LinhaRegra({ r, aoSalvar }: { r: Regra; aoSalvar: () => void }) {
  const [valor, setValor] = useState(r.valor);
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null);
  const [salvando, setSalvando] = useState(false);
  useEffect(() => setValor(r.valor), [r.valor]);
  async function salvar() {
    setSalvando(true); setMsg(null);
    const { error } = await supabase.from('parametros').update({ valor: valor.trim() }).eq('chave', r.chave);
    setSalvando(false);
    if (error) { setMsg({ tipo: 'erro', texto: error.message }); return; }
    setMsg({ tipo: 'ok', texto: 'Salvo.' });
    aoSalvar();
  }
  const id = `regra-${r.chave}`;
  return (
    <div className="regra">
      <div className="regra-texto"><label htmlFor={id}>{r.rotulo ?? r.chave}</label><small>{r.descricao}</small></div>
      <div className="regra-campo">
        <input id={id} type={r.tipo === 'inteiro' ? 'number' : r.tipo === 'data' ? 'date' : 'url'} min={r.minimo ?? undefined} max={r.maximo ?? undefined} value={valor} onChange={(e) => { setValor(e.target.value); setMsg(null); }} />
        {r.unidade && <span>{r.unidade}</span>}
        <button className="botao botao-secundario botao-pequeno" type="button" style={{ visibility: valor.trim() === r.valor ? 'hidden' : 'visible' }} disabled={salvando} onClick={() => void salvar()}>Salvar</button>
      </div>
      {msg && <p className={msg.tipo === 'ok' ? 'regra-ok' : 'regra-erro'} role={msg.tipo === 'erro' ? 'alert' : 'status'}>{msg.texto}</p>}
    </div>
  );
}

type Modelo = { tipo: string; nome: string; quando: string; para: string; assunto: string; corpo: string; ativo: boolean; ordem: number };
const campos: [string, string][] = [['{treinamento}', 'Código de Ética'], ['{data}', '25/11/2026'], ['{horario}', '09:00 às 10:00'], ['{inicio}', '09:00'], ['{sala}', 'Time Forte'], ['{participantes}', 'Analista - Maria Silva\nAssistente - João Souza'], ['{link}', '[Acessar o portal]']];
const preencher = (t: string) => campos.reduce((s, [c, v]) => s.split(c).join(v), t);

function ModelosEmail() {
  const l = useDados(async () => ((await supabase.from('modelos_email').select('*').order('ordem')).data ?? []) as Modelo[]);
  const [sel, setSel] = useState<string | null>(null);
  const atual = (l.dados ?? []).find((m) => m.tipo === sel) ?? l.dados?.[0];
  return (
    <>
      {l.erro && <Mensagem tipo="erro">{l.erro}</Mensagem>}
      {l.carregando && !l.dados && <Carregando />}
      {!!l.dados?.length && atual && (
        <div className="mestre-detalhe">
          <div className="lista-turmas">
            {l.dados.map((m) => (
              <button key={m.tipo} type="button" className="item-lista item-modelo" aria-current={atual.tipo === m.tipo} onClick={() => setSel(m.tipo)}>
                <span><strong>{m.nome}</strong><small>Para: {m.para}. {m.quando}.</small></span>
                {!m.ativo && <small>Desligado</small>}
              </button>
            ))}
          </div>
          <FormModelo key={atual.tipo} m={atual} aoSalvar={() => void l.recarregar()} />
        </div>
      )}
    </>
  );
}

function FormModelo({ m, aoSalvar }: { m: Modelo; aoSalvar: () => void }) {
  const [assunto, setAssunto] = useState(m.assunto);
  const [corpo, setCorpo] = useState(m.corpo);
  const [ativo, setAtivo] = useState(m.ativo);
  const [msg, setMsg] = useState<{ tipo: 'ok' | 'erro'; texto: string } | null>(null);
  const [salvando, setSalvando] = useState(false);
  const mudou = assunto !== m.assunto || corpo !== m.corpo || ativo !== m.ativo;
  async function salvar() {
    setSalvando(true); setMsg(null);
    const { error } = await supabase.from('modelos_email').update({ assunto, corpo, ativo }).eq('tipo', m.tipo);
    setSalvando(false);
    if (error) { setMsg({ tipo: 'erro', texto: error.message }); return; }
    setMsg({ tipo: 'ok', texto: 'Salvo. O próximo envio já usa este texto.' });
    aoSalvar();
  }
  return (
    <div className="modelo-form">
      {msg && <Mensagem tipo={msg.tipo} aoFechar={() => setMsg(null)}>{msg.texto}</Mensagem>}
      <label className="opcao"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} /> Enviar este e-mail</label>
      <Campo rotulo="Assunto"><input value={assunto} onChange={(e) => setAssunto(e.target.value)} /></Campo>
      <Campo rotulo="Texto"><textarea rows={14} value={corpo} onChange={(e) => setCorpo(e.target.value)} /></Campo>
      <p className="modelo-campos">Campos: {campos.map(([c]) => <code key={c}>{c}</code>)}</p>
      <div className="linha-acoes"><button className="botao" type="button" disabled={salvando || !mudou} onClick={() => void salvar()}>Salvar</button></div>
      <section className="modelo-previa" aria-label="Exemplo do e-mail">
        <h2>Exemplo</h2>
        <p><strong>{preencher(assunto)}</strong></p>
        <p className="modelo-corpo">{preencher(corpo)}</p>
      </section>
    </div>
  );
}
