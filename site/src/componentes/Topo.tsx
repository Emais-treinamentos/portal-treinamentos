import { NavLink } from 'react-router-dom';
import { useSessao, nomesPerfil } from '../lib/sessao';
import { rpc, useDados } from '../lib/api';
import { Icone, Rosto, type NomeIcone } from './Pecas';

function AvisoAvaliacoes() {
  const d = useDados(() => rpc<unknown[]>('minhas_avaliacoes'));
  const n = d.dados?.length ?? 0;
  return n ? <span className="contador" aria-label={`${n} avaliação(ões) pendente(s)`}>{n}</span> : null;
}

export function Topo() {
  const { usuario, sair } = useSessao();
  const p = usuario?.perfil;
  const admin = p === 'admin';
  const instrutor = p === 'instrutor';
  const itens: [string, string, NomeIcone, boolean][] = [
    ['/', 'Dashboard', 'inicio', admin],
    ['/cadastros', 'Cadastros', 'cadastros', admin],
    ['/planejar', 'Planejar Treinamentos', 'planejar', admin],
    ['/formalizar', 'Formalizar Convites', 'turmas', admin],
    ['/acompanhar', 'Acompanhar Treinamentos', 'minhas', admin],
    ['/lista-presenca', 'Lista de Presença', 'lista', admin],
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
          <NavLink key={rotulo} to={para} end={para === '/'}><Icone nome={icone} />{rotulo}{para === '/meu-perfil' && <AvisoAvaliacoes />}</NavLink>
        ))}
        {admin && <hr className="menu-divisao" />}
        {admin && apoio.map(([para, rotulo, icone]) => <NavLink key={rotulo} to={para}><Icone nome={icone} />{rotulo}</NavLink>)}
      </nav>
      {usuario && (
        <div className="lateral-usuario">
          <Rosto nome={usuario.nome} className="rosto-menta rosto-menor" />
          <span className="lateral-nome">{usuario.nome}<small>{nomesPerfil[usuario.perfil]}</small></span>
          <button className="botao botao-discreto" type="button" onClick={sair}>Sair</button>
        </div>
      )}
    </aside>
  );
}
