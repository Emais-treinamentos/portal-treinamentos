import { useSessao } from '../lib/sessao';
import { Moldura } from '../componentes/Moldura';

export function AcessoBloqueado({ motivo }: { motivo: 'sem_cadastro' | 'inativo' }) {
  const { sessao, sair } = useSessao();
  return (
    <Moldura>
      <div className="formulario">
        <h1>{motivo === 'inativo' ? 'Acesso desativado' : 'Acesso ainda não liberado'}</h1>
        <p className="apoio">
          {motivo === 'inativo'
            ? `O acesso de ${sessao?.user.email} foi desativado pelo administrativo da Emais.`
            : `O e-mail ${sessao?.user.email} entrou, mas ainda não tem acesso ao portal.`}{' '}
          Fale com Gente e Gestão para liberar.
        </p>
        <button className="botao botao-secundario" type="button" onClick={sair}>
          Sair
        </button>
      </div>
    </Moldura>
  );
}
