import { Moldura } from '../componentes/Moldura';
import { nomesPerfil, useSessao, type Perfil } from '../lib/sessao';

const descricao: Record<Perfil, string> = {
  admin: 'Planejar, acompanhar e administrar os treinamentos.',
  gestor: 'Ver a sua equipe, o seu calendário e o seu perfil.',
  instrutor: 'Confirmar a agenda, ver o calendário e registrar a presença.',
  colaborador: '',
};

export function EscolherPerfil() {
  const { usuario, opcoesPerfil, escolherPerfil, sair } = useSessao();
  return (
    <Moldura>
      <div className="formulario">
        <h1>Como você quer entrar?</h1>
        <p className="apoio-formulario">Olá, {usuario?.nome.split(' ')[0]}. Escolha o perfil. Você pode trocar depois sem sair do portal.</p>
        <div className="perfis-opcoes">
          {opcoesPerfil.map((p) => (
            <button key={p} type="button" className="perfil-opcao" onClick={() => escolherPerfil(p)}>
              <strong>{nomesPerfil[p]}</strong>
              <small>{descricao[p]}</small>
            </button>
          ))}
        </div>
        <button className="botao botao-discreto" type="button" onClick={sair}>Sair</button>
      </div>
    </Moldura>
  );
}
