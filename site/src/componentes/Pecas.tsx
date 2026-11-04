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

const icones = {
  inicio: 'M3 11l9-8 9 8v10h-6v-6H9v6H3z',
  planejar: 'M9 3h6v4H9zM9 5H5v16h14V5h-4M8 12h8M8 16h5',
  turmas: 'M4 5h16v16H4zM4 10h16M8 3v4M16 3v4',
  minhas: 'M4 4h16v16H4zM8 12l3 3 5-6',
  treinamentos: 'M4 5a2 2 0 0 1 2-2h14v16H6a2 2 0 0 0-2 2zM4 21a2 2 0 0 1 2-2h14',
  pessoas: 'M16 20v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 10a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM22 20v-2a4 4 0 0 0-3-3.9M16 2.1a4 4 0 0 1 0 7.8',
  movimentacoes: 'M7 4L3 8l4 4M3 8h14M17 12l4 4-4 4M21 16H7',
  matriz: 'M4 4h7v7H4zM13 4h7v7h-7zM4 13h7v7H4zM13 13h7v7h-7z',
  indicadores: 'M5 20V10M12 20V4M19 20v-7',
  cadastros: 'M3 6h6l2 3h10v10H3z',
  acessos: 'M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z',
  envios: 'M4 6h16v12H4zM4 7l8 6 8-6',
};
export type NomeIcone = keyof typeof icones;

export function Icone({ nome }: { nome: NomeIcone }) {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={icones[nome]} />
    </svg>
  );
}

export function iniciais(nome: string) {
  const p = nome.trim().split(/\s+/).filter((x) => x.length > 2 || x === x.toUpperCase());
  const u = p.length ? p : [nome];
  return ((u[0]?.[0] ?? '') + (u.length > 1 ? u[u.length - 1][0] : '')).toUpperCase();
}

export function Rosto({ nome, className = '', children }: { nome?: string; className?: string; children?: ReactNode }) {
  return <span className={`rosto ${className}`} aria-hidden="true" title={nome}>{children ?? iniciais(nome ?? '')}</span>;
}
