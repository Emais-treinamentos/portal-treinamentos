import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Topo } from './Topo';

// No celular a tabela vira cartões e perde o cabeçalho: cada célula recebe o nome da sua coluna.
function rotularTabelas(raiz: HTMLElement) {
  raiz.querySelectorAll('table.tabela').forEach((tabela) => {
    const titulos = [...tabela.querySelectorAll('thead th')].map((th) => th.textContent?.trim() ?? '');
    const principal = titulos.findIndex(Boolean);
    tabela.querySelectorAll('tbody tr').forEach((tr) => {
      [...tr.children].forEach((celula, i) => {
        const rotulo = (celula as HTMLTableCellElement).colSpan > 1 || i === principal ? '' : titulos[i] ?? '';
        if (celula.getAttribute('data-rotulo') !== rotulo) celula.setAttribute('data-rotulo', rotulo);
        celula.classList.toggle('celula-principal', i === principal);
      });
    });
  });
}

export function Pagina({ titulo, apoio, acoes, children }: { titulo: string; apoio?: ReactNode; acoes?: ReactNode; children: ReactNode }) {
  const conteudo = useRef<HTMLElement>(null);
  useEffect(() => {
    const raiz = conteudo.current;
    if (!raiz) return;
    rotularTabelas(raiz);
    const observador = new MutationObserver(() => rotularTabelas(raiz));
    observador.observe(raiz, { childList: true, subtree: true });
    return () => observador.disconnect();
  }, []);
  return (
    <div className="pagina">
      <Topo />
      <main className="conteudo" ref={conteudo}>
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

// No celular a lista dá lugar ao detalhe: este botão leva de volta, para o mesmo ponto da lista.
export function VoltarLista({ aoVoltar }: { aoVoltar: () => void }) {
  const [posicao] = useState(() => window.scrollY);
  useEffect(() => {
    if (window.matchMedia('(max-width: 860px)').matches) window.scrollTo({ top: 0 });
  }, []);
  return (
    <button type="button" className="botao botao-discreto voltar-lista" onClick={() => { aoVoltar(); requestAnimationFrame(() => window.scrollTo({ top: posicao })); }}>
      Voltar para a lista
    </button>
  );
}
