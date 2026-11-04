import { NavLink } from 'react-router-dom';
import { useSessao, nomesPerfil } from '../lib/sessao';

export function Topo() {
  const { usuario, sair } = useSessao();
  const p = usuario?.perfil;
  return (
    <header className="topo">
      <div className="topo-linha">
        <div className="topo-marca">
          <img src={`${import.meta.env.BASE_URL}icone.svg`} alt="" width={28} height={28} />
          <span>Portal de Treinamentos</span>
        </div>
        {usuario && (
          <div className="topo-usuario">
            <span className="topo-nome">
              {usuario.nome}
              <small>{nomesPerfil[usuario.perfil]}</small>
            </span>
            <button className="botao botao-discreto" type="button" onClick={sair}>Sair</button>
          </div>
        )}
      </div>
      <nav className="menu" aria-label="Seções do portal">
        {p === 'admin' && <NavLink to="/" end>Início</NavLink>}
        {p === 'admin' && <NavLink to="/turmas">Turmas</NavLink>}
        <NavLink to="/minhas-turmas">Minhas turmas</NavLink>
        {p === 'admin' && <NavLink to="/colaboradores">Colaboradores</NavLink>}
        {p === 'gestor' && <NavLink to="/colaboradores">Minha equipe</NavLink>}
        {p !== 'admin' && p !== 'instrutor' && <NavLink to="/meus-treinamentos">Meus treinamentos</NavLink>}
        {p === 'admin' && <NavLink to="/movimentacoes">Movimentações</NavLink>}
        {p === 'admin' && <NavLink to="/matriz">Matriz</NavLink>}
        {p === 'admin' && <NavLink to="/cadastros">Cadastros</NavLink>}
        {p === 'admin' && <NavLink to="/indicadores">Indicadores</NavLink>}
        {p === 'admin' && <NavLink to="/acessos">Acessos</NavLink>}
        {p === 'admin' && <NavLink to="/envios">Envios</NavLink>}
      </nav>
    </header>
  );
}
