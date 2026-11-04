import { NavLink } from 'react-router-dom';
import { useSessao, nomesPerfil } from '../lib/sessao';
import { Icone, Rosto, type NomeIcone } from './Pecas';

export function Topo() {
  const { usuario, sair } = useSessao();
  const p = usuario?.perfil;
  const admin = p === 'admin';
  const itens: [string, string, NomeIcone, boolean][] = [
    ['/', 'Início', 'inicio', admin],
    ['/colaboradores', 'Colaboradores', 'pessoas', admin],
    ['/colaboradores', 'Minha equipe', 'pessoas', p === 'gestor'],
    ['/planejar', 'Planejar', 'planejar', admin],
    ['/turmas', 'Turmas', 'turmas', admin],
    ['/minhas-turmas', 'Minhas turmas', 'minhas', true],
    ['/meus-treinamentos', 'Meus treinamentos', 'treinamentos', p !== 'admin' && p !== 'instrutor'],
    ['/movimentacoes', 'Movimentações', 'movimentacoes', admin],
    ['/matriz', 'Matriz', 'matriz', admin],
    ['/indicadores', 'Indicadores', 'indicadores', admin],
    ['/cadastros', 'Cadastros', 'cadastros', admin],
    ['/acessos', 'Acessos', 'acessos', admin],
    ['/envios', 'Envios', 'envios', admin],
  ];
  return (
    <aside className="lateral">
      <div className="lateral-marca">
        <img src={`${import.meta.env.BASE_URL}logo-emais.png`} alt="Emais" />
        <span>Portal de Treinamentos</span>
      </div>
      <nav className="menu" aria-label="Seções do portal">
        {itens.filter((i) => i[3]).map(([para, rotulo, icone]) => (
          <NavLink key={rotulo} to={para} end={para === '/'}><Icone nome={icone} />{rotulo}</NavLink>
        ))}
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
