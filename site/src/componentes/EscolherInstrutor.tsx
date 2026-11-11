import { useState } from 'react';
import { rpc, useDados } from '../lib/api';
import { Campo } from './Pecas';

export type SugestaoInstrutor = { treinamento_id: string; email: string; nome: string; papel: 'titular' | 'substituto'; ativo: boolean };

// Titulares e substitutos cadastrados em Acessos, de todos os treinamentos.
export function useInstrutores() {
  return useDados(() => rpc<SugestaoInstrutor[]>('instrutores_dos_treinamentos', {}), []);
}

export const sugestoesDe = (todas: SugestaoInstrutor[] | null, treinamento: string) => (todas ?? []).filter((s) => s.treinamento_id === treinamento);

// Primeiro titular ativo; sem titular ativo, o primeiro substituto ativo.
export const sugestaoPadrao = (lista: SugestaoInstrutor[]) => lista.find((s) => s.ativo && s.papel === 'titular')?.email ?? lista.find((s) => s.ativo)?.email ?? '';

const OUTRO = '__outro';

export function EscolherInstrutor({ sugestoes, valor, aoMudar, rotulo = 'Instrutor' }: { sugestoes: SugestaoInstrutor[]; valor: string; aoMudar: (email: string) => void; rotulo?: string }) {
  const conhecido = sugestoes.some((s) => s.email === valor);
  const [outro, setOutro] = useState(!!valor && !conhecido);
  const modoOutro = outro || !sugestoes.length;
  const titulares = sugestoes.filter((s) => s.papel === 'titular');
  const substitutos = sugestoes.filter((s) => s.papel === 'substituto');
  const opcao = (s: SugestaoInstrutor) => <option key={s.email} value={s.email}>{s.nome}{s.ativo ? '' : ' (acesso inativo)'}</option>;
  return (
    <>
      {sugestoes.length > 0 && (
        <Campo rotulo={rotulo}>
          <select value={modoOutro ? OUTRO : valor} onChange={(e) => { if (e.target.value === OUTRO) { setOutro(true); aoMudar(''); } else { setOutro(false); aoMudar(e.target.value); } }}>
            {!valor && !modoOutro && <option value="">Escolha</option>}
            {titulares.length > 0 && <optgroup label="Aplica o treinamento">{titulares.map(opcao)}</optgroup>}
            {substitutos.length > 0 && <optgroup label="Substituto">{substitutos.map(opcao)}</optgroup>}
            <option value={OUTRO}>Outro e-mail</option>
          </select>
        </Campo>
      )}
      {modoOutro && <Campo rotulo={sugestoes.length ? 'E-mail do instrutor' : `${rotulo} (e-mail)`}><input type="email" value={valor} onChange={(e) => aoMudar(e.target.value)} placeholder={sugestoes.length ? '' : 'Ninguém cadastrado para este treinamento em Acessos'} /></Campo>}
    </>
  );
}
