import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Dialogo } from '../componentes/Dialogo';
import { Campo, Farol, FormDialogo, SeloSituacao } from '../componentes/Pecas';
import { dataBR, nomesAcao, rpc, textoErro, useDados, type SituacaoColaborador } from '../lib/api';
import { gerarF109, gerarGrade, gerarTermoDispensa } from '../lib/documentos';
import { supabase } from '../lib/supabase';
import { useSessao } from '../lib/sessao';

type Linha = { id: string; nome: string; cargo: string | null; departamento: string | null; ativo: boolean; data_referencia: string | null; total: number; realizados: number; agendados: number; pendentes: number; classificar: boolean; farol: string; motivo: string };

export function Colaboradores() {
  const { usuario } = useSessao();
  const admin = usuario?.perfil === 'admin';
  const lista = useDados(() => rpc<Linha[]>('painel_colaboradores'));
  const [busca, setBusca] = useState('');
  const [farol, setFarol] = useState('todos');
  const [dep, setDep] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  const q = busca.trim().toLowerCase();
  const linhas = (lista.dados ?? []).filter((c) => (farol === 'todos' || c.farol === farol) && (!dep || c.departamento === dep) && (!q || `${c.nome} ${c.cargo}`.toLowerCase().includes(q)));
  const deps = [...new Set((lista.dados ?? []).map((c) => c.departamento).filter(Boolean))] as string[];
  const conta = (f: string) => (lista.dados ?? []).filter((c) => c.farol === f).length;
  return (
    <Pagina titulo={usuario?.perfil === 'gestor' ? 'Minha equipe' : 'Colaboradores'} apoio="Situação de cada pessoa em relação à própria matriz." acoes={admin ? <button className="botao" type="button" onClick={() => setNovo(true)}>Novo colaborador</button> : undefined}>
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {lista.carregando && !lista.dados && <Carregando />}
      <div className="chips chips-filtro" role="group" aria-label="Filtrar por farol">
        <button type="button" className="chip" aria-pressed={farol === 'todos'} onClick={() => setFarol('todos')}>Todos<small>{lista.dados?.length ?? 0}</small></button>
        <button type="button" className="chip" aria-pressed={farol === 'vermelho'} onClick={() => setFarol('vermelho')}>Sem turma<small>{conta('vermelho')}</small></button>
        <button type="button" className="chip" aria-pressed={farol === 'amarelo'} onClick={() => setFarol('amarelo')}>Em andamento<small>{conta('amarelo')}</small></button>
        <button type="button" className="chip" aria-pressed={farol === 'verde'} onClick={() => setFarol('verde')}>Em dia<small>{conta('verde')}</small></button>
      </div>
      <div className="linha-botoes" style={{ marginBottom: 12 }}>
        <label className="campo campo-busca"><span>Buscar</span><input type="search" value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Nome ou cargo" /></label>
        <label className="campo"><span>Departamento</span><select value={dep} onChange={(e) => setDep(e.target.value)}><option value="">Todos</option>{deps.map((d) => <option key={d}>{d}</option>)}</select></label>
      </div>
      <div className="lista-turmas">
        {lista.dados && !linhas.length && <p className="vazio">Ninguém nesta lista.</p>}
        {linhas.map((c) => (
          <button key={c.id} type="button" className="item-lista" onClick={() => setSel(c.id)}>
            <Farol cor={c.farol === 'inativo' ? 'cinza' : c.farol} rotulo={c.farol} />
            <span><strong>{c.nome}</strong><small>{c.cargo} · {c.departamento}</small><small>{c.motivo}</small></span>
            <small>{c.realizados} de {c.total}</small>
          </button>
        ))}
      </div>
      {sel && <Dialogo aberto titulo="Prontuário" largura="larga" aoFechar={() => { setSel(null); void lista.recarregar(); }}><Prontuario id={sel} admin={admin} /></Dialogo>}
      {novo && <EditarColaborador aoFechar={() => setNovo(false)} aoSalvar={() => void lista.recarregar()} />}
    </Pagina>
  );
}

export function MeusTreinamentos() {
  const { usuario } = useSessao();
  const meu = useDados(async () => (await supabase.from('usuarios').select('colaborador_id').eq('id', usuario!.id).single()).data?.colaborador_id as string | null);
  return (
    <Pagina titulo="Meus treinamentos" apoio="Sua situação, suas turmas e seus documentos.">
      {meu.carregando && <Carregando />}
      {meu.dados ? <Prontuario id={meu.dados} admin={false} /> : !meu.carregando && <p className="vazio">Seu acesso ainda não está ligado a um colaborador. Fale com Gente e Gestão.</p>}
    </Pagina>
  );
}

function Prontuario({ id, admin }: { id: string; admin: boolean }) {
  const d = useDados(() => rpc<SituacaoColaborador>('situacao_colaborador', { p_colaborador: id }), [id]);
  const [erro, setErro] = useState<string | null>(null);
  const [janela, setJanela] = useState<'editar' | 'mover' | null>(null);
  const s = d.dados;
  if (!s) return d.erro ? <Mensagem tipo="erro">{d.erro}</Mensagem> : <Carregando />;
  const doc = async (f: () => Promise<void>) => { setErro(null); try { await f(); } catch (e) { setErro(textoErro(e)); } };
  const c = s.colaborador;
  return (
    <div className="detalhe">
      <div>
        <h2>{c.nome}</h2>
        <dl className="dados">
          <div><dt>Cargo</dt><dd>{c.cargo}</dd></div>
          <div><dt>Departamento</dt><dd>{c.departamento}</dd></div>
          <div><dt>Admissão</dt><dd>{dataBR(c.data_admissao)}</dd></div>
          <div><dt>Data de referência</dt><dd>{dataBR(c.data_referencia)}</dd></div>
        </dl>
      </div>
      {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
      <div className="linha-acoes">
        <button className="botao botao-secundario" type="button" onClick={() => void doc(() => gerarF109(s))}>F.109</button>
        <button className="botao botao-secundario" type="button" onClick={() => void doc(() => gerarGrade(s))}>Grade de treinamentos</button>
        {s.decisao?.acao_final === 'dispensa' && <button className="botao botao-secundario" type="button" onClick={() => void doc(() => gerarTermoDispensa(s))}>Termo de Dispensa</button>}
        {admin && c.ativo && <button className="botao botao-secundario" type="button" onClick={() => setJanela('mover')}>Registrar movimentação</button>}
        {admin && <button className="botao botao-discreto" type="button" onClick={() => setJanela('editar')}>Editar cadastro</button>}
      </div>
      {s.decisao && <p className="aviso aviso-info">Reciclagem: {nomesAcao[s.decisao.acao_final]}, decidida em {dataBR(s.decisao.decidido_em)}.</p>}
      <section>
        <p className="grupo-titulo">Treinamentos obrigatórios</p>
        {!s.itens.length && <p className="apoio">Nada na matriz para este cargo.</p>}
        {s.itens.map((i) => (
          <div className="pessoa" key={i.treinamento_id}>
            <span>{i.treinamento}<small>{i.ultima ? `Realizado em ${dataBR(i.ultima)}` : i.data_turma ? `Turma em ${dataBR(i.data_turma)}` : ''}</small></span>
            <span className="linha-acoes"><SeloSituacao situacao={i.situacao} />{admin && i.turma_id && <Link className="link" to={`/turmas?turma=${i.turma_id}`}>Ver turma</Link>}</span>
          </div>
        ))}
      </section>
      {!!s.movimentacoes.length && (
        <section>
          <p className="grupo-titulo">Histórico de cargos</p>
          {s.movimentacoes.map((m, i) => <div className="pessoa" key={i}><span>{m.cargo}<small>{m.tipo}</small></span><small>{dataBR(m.data_inicio)}{m.data_fim ? ` a ${dataBR(m.data_fim)}` : ' até hoje'}</small></div>)}
        </section>
      )}
      {janela === 'editar' && <EditarColaborador atual={s} aoFechar={() => setJanela(null)} aoSalvar={() => void d.recarregar()} />}
      {janela === 'mover' && <Mover s={s} aoFechar={() => setJanela(null)} aoSalvar={() => void d.recarregar()} />}
    </div>
  );
}

const useCargos = () => useDados(async () => (await supabase.from('cargos').select('id, nome, departamentos(nome)').eq('ativo', true).order('nome')).data ?? []);

function EditarColaborador({ atual, aoFechar, aoSalvar }: { atual?: SituacaoColaborador; aoFechar: () => void; aoSalvar: () => void }) {
  const cargos = useCargos();
  const c = atual?.colaborador;
  const [nome, setNome] = useState(c?.nome ?? ''); const [email, setEmail] = useState(c?.email ?? ''); const [cargo, setCargo] = useState(c?.cargo_id ?? '');
  const [adm, setAdm] = useState(c?.data_admissao ?? ''); const [ativo, setAtivo] = useState(c?.ativo ?? true);
  return (
    <FormDialogo titulo={c ? 'Editar cadastro' : 'Novo colaborador'} rotulo="Salvar" aoFechar={aoFechar} aoEnviar={async () => { await rpc('salvar_colaborador', { p_id: c?.id ?? null, p_nome: nome, p_email: email, p_cargo: cargo, p_data_admissao: adm || null, p_ativo: ativo }); aoSalvar(); }}>
      <Campo rotulo="Nome"><input required value={nome} onChange={(e) => setNome(e.target.value)} /></Campo>
      <Campo rotulo="E-mail"><input type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Campo>
      {!c && <Campo rotulo="Cargo"><select required value={cargo} onChange={(e) => setCargo(e.target.value)}><option value="">Escolha</option>{(cargos.dados ?? []).map((g) => <option key={g.id} value={g.id}>{g.nome}</option>)}</select></Campo>}
      <Campo rotulo="Data de admissão"><input type="date" required value={adm} onChange={(e) => setAdm(e.target.value)} /></Campo>
      {c && <label className="opcao"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} />Ativo</label>}
    </FormDialogo>
  );
}

function Mover({ s, aoFechar, aoSalvar }: { s: SituacaoColaborador; aoFechar: () => void; aoSalvar: () => void }) {
  const cargos = useCargos();
  const [cargo, setCargo] = useState(''); const [data, setData] = useState(''); const [tipo, setTipo] = useState('promocao');
  return (
    <FormDialogo titulo="Registrar movimentação" rotulo="Registrar" aoFechar={aoFechar} aoEnviar={async () => { await rpc('registrar_movimentacao', { p_colaborador: s.colaborador.id, p_cargo: cargo, p_data: data || null, p_tipo: tipo }); aoSalvar(); }}>
      <p className="apoio">A pessoa entra na fila de Movimentações para classificar a reciclagem.</p>
      <Campo rotulo="Novo cargo"><select required value={cargo} onChange={(e) => setCargo(e.target.value)}><option value="">Escolha</option>{(cargos.dados ?? []).filter((g) => g.id !== s.colaborador.cargo_id).map((g) => <option key={g.id} value={g.id}>{g.nome}</option>)}</select></Campo>
      <div className="grade-2">
        <Campo rotulo="Data"><input type="date" required value={data} onChange={(e) => setData(e.target.value)} /></Campo>
        <Campo rotulo="Tipo"><select value={tipo} onChange={(e) => setTipo(e.target.value)}><option value="promocao">Promoção</option><option value="transferencia">Transferência</option></select></Campo>
      </div>
    </FormDialogo>
  );
}
