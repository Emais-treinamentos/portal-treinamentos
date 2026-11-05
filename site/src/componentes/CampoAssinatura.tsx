import { useEffect, useRef, useState, type PointerEvent } from 'react';

// Campo para desenhar a assinatura com dedo, caneta ou mouse. Devolve uma imagem PNG.
export function CampoAssinatura({ aoMudar }: { aoMudar: (imagem: string | null) => void }) {
  const tela = useRef<HTMLCanvasElement>(null);
  const riscando = useRef(false);
  const [vazio, setVazio] = useState(true);

  function preparar() {
    const c = tela.current!; const x = c.getContext('2d')!;
    c.width = 900; c.height = 300;
    x.fillStyle = '#ffffff'; x.fillRect(0, 0, c.width, c.height);
    x.strokeStyle = '#10233f'; x.lineWidth = 5; x.lineCap = 'round'; x.lineJoin = 'round';
  }
  useEffect(preparar, []);

  const ponto = (e: PointerEvent<HTMLCanvasElement>) => { const c = tela.current!; const r = c.getBoundingClientRect(); return [(e.clientX - r.left) * (c.width / r.width), (e.clientY - r.top) * (c.height / r.height)] as const; };
  function comecar(e: PointerEvent<HTMLCanvasElement>) { e.currentTarget.setPointerCapture(e.pointerId); riscando.current = true; const [a, b] = ponto(e); const x = tela.current!.getContext('2d')!; x.beginPath(); x.moveTo(a, b); x.lineTo(a + 0.1, b + 0.1); x.stroke(); }
  function riscar(e: PointerEvent<HTMLCanvasElement>) { if (!riscando.current) return; const [a, b] = ponto(e); const x = tela.current!.getContext('2d')!; x.lineTo(a, b); x.stroke(); }
  function terminar() { if (!riscando.current) return; riscando.current = false; setVazio(false); aoMudar(tela.current!.toDataURL('image/png')); }
  function limpar() { preparar(); setVazio(true); aoMudar(null); }

  return (
    <div className="assinatura-campo">
      <canvas ref={tela} role="img" aria-label="Campo para desenhar a assinatura" onPointerDown={comecar} onPointerMove={riscar} onPointerUp={terminar} onPointerCancel={terminar} />
      <div className="assinatura-rodape">
        <small>{vazio ? 'Desenhe sua assinatura no quadro acima.' : 'Assinatura desenhada.'}</small>
        <button className="botao botao-discreto botao-pequeno" type="button" disabled={vazio} onClick={limpar}>Limpar</button>
      </div>
    </div>
  );
}
