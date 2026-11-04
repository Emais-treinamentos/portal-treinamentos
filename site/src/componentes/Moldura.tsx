import type { ReactNode } from 'react';

export function Moldura({ children }: { children: ReactNode }) {
  return (
    <div className="moldura">
      <aside className="moldura-marca">
        <div className="marca-topo">
          <img src={`${import.meta.env.BASE_URL}icone.svg`} alt="" width={36} height={36} />
          <span>Grupo Emais</span>
        </div>
        <div className="marca-texto">
          <h1>Portal de Treinamentos</h1>
          <p>Planejamento, turmas, presença e reciclagem dos colaboradores.</p>
        </div>
        <div className="faixa-obra" aria-hidden="true" />
      </aside>
      <main className="moldura-conteudo">{children}</main>
    </div>
  );
}
