import type { ReactNode } from 'react';
import { Topo } from './Topo';

export function Pagina({ titulo, apoio, acoes, children }: { titulo: string; apoio?: ReactNode; acoes?: ReactNode; children: ReactNode }) {
  return (
    <div className="pagina">
      <Topo />
      <main className="conteudo">
        <section className="cabecalho cabecalho-com-acoes">
          <div>
            <h1>{titulo}</h1>
            {apoio && <p className="apoio">{apoio}</p>}
          </div>
          {acoes && <div className="cabecalho-acoes">{acoes}</div>}
        </section>
        {children}
      </main>
    </div>
  );
}

export function Mensagem({ tipo, children, aoFechar }: { tipo: 'ok' | 'erro'; children: ReactNode; aoFechar?: () => void }) {
  return (
    <div className={`aviso aviso-${tipo} aviso-faixa`} role={tipo === 'erro' ? 'alert' : 'status'}>
      <span>{children}</span>
      {aoFechar && (
        <button type="button" className="botao botao-discreto" onClick={aoFechar}>
          Fechar
        </button>
      )}
    </div>
  );
}
