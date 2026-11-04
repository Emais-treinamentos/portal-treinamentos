import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { rpc, useDados } from '../lib/api';

type Ind = { colaboradores: number; verde: number; amarelo: number; vermelho: number; obrigatorios: number; realizados: number; agendados: number; pendentes: number; dispensados: number; horas_homem: number; turmas_abertas: number; turmas_realizadas: number; por_departamento: { departamento: string; obrigatorios: number; realizados: number }[]; por_mes: { mes: string; turmas: number; presentes: number }[] };
const pct = (a: number, b: number) => (b ? `${Math.round((a / b) * 100)}%` : '0%');

function Cartao({ rotulo, valor, apoio }: { rotulo: string; valor: string | number; apoio?: string }) {
  return <div className="cartao"><span className="cartao-rotulo">{rotulo}</span><strong className="cartao-valor">{valor}</strong>{apoio && <span className="cartao-apoio">{apoio}</span>}</div>;
}

export function Indicadores() {
  const { dados: d, erro, carregando } = useDados(() => rpc<Ind>('indicadores'));
  return (
    <Pagina titulo="Indicadores" apoio="Calculados por pessoa e pela matriz individual de cada uma.">
      {erro && <Mensagem tipo="erro">{erro}</Mensagem>}
      {carregando && !d && <Carregando />}
      {d && (
        <>
          <p className="grupo-titulo">Estado atual</p>
          <div className="cartoes">
            <Cartao rotulo="Turmas abertas" valor={d.turmas_abertas} />
            <Cartao rotulo="Em dia" valor={d.verde} apoio="pessoas" />
            <Cartao rotulo="Em andamento" valor={d.amarelo} apoio="pessoas" />
            <Cartao rotulo="Sem turma" valor={d.vermelho} apoio="pessoas" />
          </div>
          <p className="grupo-titulo">Conformidade</p>
          <div className="cartoes">
            <Cartao rotulo="Conformidade" valor={pct(d.realizados, d.obrigatorios)} apoio={`${d.realizados} de ${d.obrigatorios} obrigatórios`} />
            <Cartao rotulo="Agendados" valor={d.agendados} />
            <Cartao rotulo="Pendentes" valor={d.pendentes} />
            <Cartao rotulo="Dispensados" valor={d.dispensados} />
          </div>
          <p className="grupo-titulo">Tendência</p>
          <div className="cartoes">
            <Cartao rotulo="Turmas realizadas" valor={d.turmas_realizadas} />
            <Cartao rotulo="Hora-homem" valor={Math.round(d.horas_homem)} apoio="horas" />
            <Cartao rotulo="Colaboradores ativos" valor={d.colaboradores} />
          </div>
          <section className="bloco">
            <h2 className="bloco-titulo">Por departamento</h2>
            <div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Departamento</th><th>Obrigatórios</th><th>Realizados</th><th>Conformidade</th></tr></thead>
              <tbody>{d.por_departamento.map((x) => <tr key={x.departamento}><td>{x.departamento}</td><td>{x.obrigatorios}</td><td>{x.realizados}</td><td>{pct(x.realizados, x.obrigatorios)}</td></tr>)}</tbody></table></div>
          </section>
          {!!d.por_mes.length && <section className="bloco">
            <h2 className="bloco-titulo">Últimos 12 meses</h2>
            <div className="tabela-rolagem"><table className="tabela"><thead><tr><th>Mês</th><th>Turmas</th><th>Presenças</th></tr></thead>
              <tbody>{d.por_mes.map((x) => <tr key={x.mes}><td>{x.mes.split('-').reverse().join('/')}</td><td>{x.turmas}</td><td>{x.presentes}</td></tr>)}</tbody></table></div>
          </section>}
        </>
      )}
    </Pagina>
  );
}
