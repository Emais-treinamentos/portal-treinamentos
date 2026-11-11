import { useEffect } from 'react';
import { NavLink, useNavigate } from 'react-router-dom';
import { useSessao, nomesPerfil } from '../lib/sessao';
import { rpc, useDados } from '../lib/api';
import { Icone, Rosto, type NomeIcone } from './Pecas';

function AvisoAvaliacoes() {
  const d = useDados(async () => {
    const [av, as] = await Promise.all([rpc<unknown[]>('minhas_avaliacoes'), rpc<{ status: string }[]>('minhas_assinaturas')]);
    return av.length + as.filter((x) => x.status === 'pendente').length;
  });
  const n = d.dados ?? 0;
  return n ? <span className="contador" aria-label={`${n} pendência(s)`}>{n}</span> : null;
}

// Avisa o menu para recontar as notificações depois de uma decisão.
export const avisarNotificacoes = () => window.dispatchEvent(new Event('notificacoes-mudaram'));

function ContadorNotificacoes() {
  const d = useDados(() => rpc<number>('contar_notificacoes'), []);
  const { recarregar } = d;
  useEffect(() => {
    const f = () => void recarregar();
    window.addEventListener('notificacoes-mudaram', f);
    const t = window.setInterval(f, 120000);
    return () => { window.removeEventListener('notificacoes-mudaram', f); window.clearInterval(t); };
  }, [recarregar]);
  const n = d.dados ?? 0;
  return n ? <span className="contador" aria-label={`${n} notificação(ões)`}>{n}</span> : null;
}

export function Topo() {
  const { usuario, perfilAtivo, opcoesPerfil, escolherPerfil, sair } = useSessao();
  const navegar = useNavigate();
  const p = perfilAtivo;
  const admin = p === 'admin';
  const instrutor = p === 'instrutor';
  const itens: [string, string, NomeIcone, boolean][] = [
    ['/', 'Dashboard', 'inicio', admin],
    ['/notificacoes', 'Notificações', 'sino', admin],
    ['/cadastros', 'Cadastros', 'cadastros', admin],
    ['/calendario-geral', 'Calendário', 'turmas', admin],
    ['/planejar', 'Planejar Treinamentos', 'planejar', admin],
    ['/formalizar', 'Formalizar Convites', 'turmas', admin],
    ['/acompanhar', 'Acompanhar Treinamentos', 'minhas', admin],
    ['/lista-presenca', 'Lista de Presença', 'lista', admin],
    ['/eficacia', 'Avaliação de Eficácia', 'eficacia', admin],
    ['/reciclagem', 'Reciclagem', 'movimentacoes', admin],
    ['/satisfacao', 'Satisfação', 'estrela', admin],
    ['/agenda', 'Confirmar Agenda', 'minhas', instrutor],
    ['/calendario', 'Calendário', 'turmas', instrutor],
    ['/presenca', 'Presença', 'lista', instrutor],
    ['/colaboradores', 'Minha equipe', 'pessoas', p === 'gestor'],
    ['/meu-calendario', 'Meu Calendário', 'turmas', p === 'gestor' || p === 'colaborador'],
    ['/meu-perfil', 'Meu Perfil', 'perfil', p === 'gestor' || p === 'colaborador'],
  ];
  const apoio: [string, string, NomeIcone][] = [['/acessos', 'Acessos', 'acessos'], ['/envios', 'Envios', 'envios']];
  return (
    <aside className="lateral">
      <div className="lateral-marca">
        <img src={`${import.meta.env.BASE_URL}logo-emais.png`} alt="Emais" />
        <span>Portal de Treinamentos</span>
      </div>
      <nav className="menu" aria-label="Seções do portal">
        {itens.filter((i) => i[3]).map(([para, rotulo, icone]) => (
          <NavLink key={rotulo} to={para} end={para === '/'}><Icone nome={icone} />{rotulo}{para === '/meu-perfil' && <AvisoAvaliacoes />}{para === '/notificacoes' && <ContadorNotificacoes />}</NavLink>
        ))}
        {admin && <hr className="menu-divisao" />}
        {admin && apoio.map(([para, rotulo, icone]) => <NavLink key={rotulo} to={para}><Icone nome={icone} />{rotulo}</NavLink>)}
      </nav>
      {usuario && (
        <div className="lateral-usuario">
          <Rosto nome={usuario.nome} className="rosto-menta rosto-menor" />
          <span className="lateral-nome">{usuario.nome}<small>{p ? nomesPerfil[p] : ''}</small>{opcoesPerfil.length > 1 && <button className="lateral-trocar" type="button" onClick={() => { escolherPerfil(null); navegar('/', { replace: true }); }}>Trocar perfil</button>}</span>
          <button className="botao botao-discreto" type="button" onClick={sair}>Sair</button>
        </div>
      )}
    </aside>
  );
}
