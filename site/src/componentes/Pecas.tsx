import { useState, type FormEvent, type ReactNode } from 'react';
import { Dialogo } from './Dialogo';
import { corSituacao, nomesSituacao, textoErro } from '../lib/api';

export function Farol({ cor, rotulo }: { cor: string; rotulo?: string }) {
  return <span className={`farol farol-${cor}`} {...(rotulo ? { role: 'img', 'aria-label': rotulo } : { 'aria-hidden': true })} />;
}

export function SeloSituacao({ situacao }: { situacao: string }) {
  const cor = corSituacao[situacao] ?? 'cinza';
  return <span className={`selo-farol selo-farol-${cor}`}><Farol cor={cor} />{nomesSituacao[situacao] ?? situacao}</span>;
}

// Janela com formulário: mostra o erro do banco ali mesmo e só fecha quando deu certo.
export function FormDialogo({ titulo, rotulo, aoFechar, aoEnviar, children, largura, perigo, desabilitar }: {
  titulo: string; rotulo: string; aoFechar: () => void; aoEnviar: () => Promise<void>; children: ReactNode; largura?: 'normal' | 'larga'; perigo?: boolean; desabilitar?: boolean;
}) {
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  async function enviar(e: FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setErro(null);
    try {
      await aoEnviar();
      aoFechar();
    } catch (x) {
      setErro(textoErro(x));
    } finally {
      setEnviando(false);
    }
  }
  return (
    <Dialogo aberto titulo={titulo} aoFechar={aoFechar} largura={largura}>
      <form className="formulario-largo detalhe" onSubmit={enviar}>
        {children}
        {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
        <div className="linha-acoes">
          <button className={`botao${perigo ? ' botao-secundario' : ''}`} type="submit" disabled={enviando || desabilitar}>{enviando ? 'Salvando' : rotulo}</button>
          <button className="botao botao-discreto" type="button" onClick={aoFechar}>Voltar</button>
        </div>
      </form>
    </Dialogo>
  );
}

export function Campo({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return <label className="campo"><span>{rotulo}</span>{children}</label>;
}
