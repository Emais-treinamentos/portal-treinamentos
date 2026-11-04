import { Link, Navigate } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { rpc, useDados } from '../lib/api';
import { useSessao } from '../lib/sessao';

type ItemFila = { grupo: string; urgente: boolean; titulo: string; detalhe: string | null; turma_id: string | null; colaborador_id: string | null; solicitacao_id: string | null };
const grupos: [string, string, string][] = [
  ['solicitacao', 'Solicitações dos instrutores', 'Decidir'], ['replanejar', 'Turmas para replanejar', 'Replanejar'], ['envio', 'Falhas de envio', 'Ver'],
  ['presenca', 'Presença não registrada', 'Ver turma'], ['formalizar', 'Prontas para formalizar', 'Formalizar'], ['movimentacao', 'Movimentações a classificar', 'Classificar'],
  ['a_planejar', 'A planejar', 'Planejar'], ['sem_resposta', 'Aguardando instrutor', 'Ver turma'],
];

export function Inicio() {
  const { usuario } = useSessao();
  if (usuario?.perfil === 'seguranca') return <Navigate to="/turmas" replace />;
  if (usuario?.perfil === 'gestor') return <Navigate to="/colaboradores" replace />;
  if (usuario?.perfil === 'colaborador') return <Navigate to="/meus-treinamentos" replace />;
  if (usuario?.perfil === 'instrutor') return <Navigate to="/minhas-turmas" replace />;
  return <Fila />;
}

function destino(i: ItemFila) {
  if (i.grupo === 'envio') return '/envios';
  if (i.turma_id) return `/turmas?turma=${i.turma_id}`;
  if (i.grupo === 'movimentacao') return `/movimentacoes?colaborador=${i.colaborador_id}`;
  return '/turmas?etapa=a_planejar';
}

function Fila() {
  const { dados, erro, carregando } = useDados(() => rpc<ItemFila[]>('fila_inicio'));
  return (
    <Pagina titulo="O que fazer hoje" apoio="Tudo que está parado, com o atalho para resolver.">
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      {carregando && !dados && <Carregando />}
      {dados && dados.length === 0 && <p className="vazio">Nada pendente. Bom trabalho.</p>}
      {dados && grupos.map(([g, nome, acao]) => {
        const itens = dados.filter((i) => i.grupo === g);
        if (!itens.length) return null;
        return (
          <section key={g}>
            <p className="grupo-titulo">{nome} ({itens.length})</p>
            {itens.map((i, n) => (
              <div className={`tarefa-fila${i.urgente ? ' tarefa-urgente' : ''}`} key={n}>
                <span><strong>{i.titulo}</strong><small>{i.detalhe}</small></span>
                <Link className="botao botao-pequeno" to={destino(i)}>{acao}</Link>
              </div>
            ))}
          </section>
        );
      })}
    </Pagina>
  );
}
