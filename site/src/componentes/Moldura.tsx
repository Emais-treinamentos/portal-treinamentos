import type { ReactNode } from 'react';

const rostos: [string, string, string][] = [
  ['AL', '#006666', '#ffffff'], ['BR', '#8ed973', '#123b33'], ['CM', '#ffffff', '#0b4a44'], ['DS', '#0b4f4f', '#ffffff'], ['EF', '#c4ebd3', '#0b4a44'],
];

export function Moldura({ children }: { children: ReactNode }) {
  return (
    <div className="moldura">
      <main className="moldura-conteudo">
        <div className="moldura-coluna">
          <img className="moldura-logo" src={`${import.meta.env.BASE_URL}logo-emais.png`} alt="Emais" />
          {children}
        </div>
      </main>
      <aside className="moldura-marca">
        <div className="moldura-rostos" aria-hidden="true">
          {rostos.map(([t, fundo, cor]) => <span key={t} style={{ background: fundo, color: cor }}>{t}</span>)}
        </div>
        <p className="moldura-frase">Cada pessoa com o treinamento certo, no momento certo.</p>
        <p>Portal de Treinamentos de Gente e Gestão</p>
      </aside>
    </div>
  );
}
