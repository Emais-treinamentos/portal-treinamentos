import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from './supabase';

export type Perfil = 'admin' | 'gestor' | 'colaborador' | 'instrutor';

export type Usuario = {
  id: string;
  nome: string;
  email: string;
  perfil: Perfil;
  ativo: boolean;
};

// carregando: ainda lendo a sessão; fora: sem login; sem_cadastro: tem login mas não está em public.usuarios;
// inativo: cadastro desativado por Gente e Gestão; ok: pode usar o portal.
export type Situacao = 'carregando' | 'fora' | 'sem_cadastro' | 'inativo' | 'ok';

type ValorSessao = {
  situacao: Situacao;
  sessao: Session | null;
  usuario: Usuario | null;
  // Perfil com que a pessoa está usando o portal agora. Null enquanto ela não escolheu.
  perfilAtivo: Perfil | null;
  opcoesPerfil: Perfil[];
  escolherPerfil: (p: Perfil | null) => void;
  recuperandoSenha: boolean;
  concluirRecuperacao: () => void;
  sair: () => Promise<void>;
};

const Contexto = createContext<ValorSessao | null>(null);

export const nomesPerfil: Record<Perfil, string> = {
  admin: 'Gente e Gestão',
  gestor: 'Gestor',
  colaborador: 'Colaborador',
  instrutor: 'Instrutor',
};

// Gestor e Gente e Gestão também podem ser instrutores: escolhem com qual perfil entrar.
const opcoesDe = (p: Perfil | undefined): Perfil[] => {
  if (p === 'admin') return ['admin', 'instrutor'];
  if (p === 'gestor') return ['gestor', 'instrutor'];
  return p ? [p] : [];
};

const CHAVE_PERFIL = 'portal-treinamentos-perfil';
function lerEscolha(uid: string): Perfil | null {
  try {
    const v = JSON.parse(sessionStorage.getItem(CHAVE_PERFIL) ?? 'null') as { uid: string; perfil: Perfil } | null;
    return v?.uid === uid ? v.perfil : null;
  } catch {
    return null;
  }
}
function gravarEscolha(uid: string | null, perfil: Perfil | null) {
  try {
    if (uid && perfil) sessionStorage.setItem(CHAVE_PERFIL, JSON.stringify({ uid, perfil }));
    else sessionStorage.removeItem(CHAVE_PERFIL);
  } catch {
    // Sem armazenamento, a escolha vale enquanto a página estiver aberta.
  }
}

export function ProvedorSessao({ children }: { children: ReactNode }) {
  const [sessaoLida, setSessaoLida] = useState(false);
  const [sessao, setSessao] = useState<Session | null>(null);
  const [usuario, setUsuario] = useState<Usuario | null>(null);
  const [situacao, setSituacao] = useState<Situacao>('carregando');
  const [recuperandoSenha, setRecuperandoSenha] = useState(false);
  const [escolhido, setEscolhido] = useState<Perfil | null>(null);

  useEffect(() => {
    const { data } = supabase.auth.onAuthStateChange((evento, novaSessao) => {
      if (evento === 'PASSWORD_RECOVERY') setRecuperandoSenha(true);
      setSessao(novaSessao);
      setSessaoLida(true);
    });
    supabase.auth.getSession().then(({ data: d }) => {
      setSessao(d.session);
      setSessaoLida(true);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const uid = sessao?.user.id ?? null;

  useEffect(() => {
    if (!sessaoLida) return;
    if (!uid) {
      setUsuario(null);
      setSituacao('fora');
      return;
    }
    let cancelado = false;
    setSituacao('carregando');
    supabase
      .from('usuarios')
      .select('id, nome, email, perfil, ativo')
      .eq('id', uid)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelado) return;
        if (error || !data) {
          setUsuario(null);
          setSituacao('sem_cadastro');
          return;
        }
        setUsuario(data as Usuario);
        setEscolhido(lerEscolha(data.id));
        setSituacao(data.ativo ? 'ok' : 'inativo');
      });
    return () => {
      cancelado = true;
    };
  }, [sessaoLida, uid]);

  const opcoesPerfil = opcoesDe(usuario?.perfil);
  const perfilAtivo = opcoesPerfil.length === 1 ? opcoesPerfil[0] : escolhido && opcoesPerfil.includes(escolhido) ? escolhido : null;

  const valor: ValorSessao = {
    situacao,
    sessao,
    usuario,
    perfilAtivo,
    opcoesPerfil,
    escolherPerfil: (p) => {
      setEscolhido(p);
      gravarEscolha(usuario?.id ?? null, p);
    },
    recuperandoSenha,
    concluirRecuperacao: () => setRecuperandoSenha(false),
    sair: async () => {
      gravarEscolha(null, null);
      setEscolhido(null);
      await supabase.auth.signOut();
      setRecuperandoSenha(false);
    },
  };

  return <Contexto.Provider value={valor}>{children}</Contexto.Provider>;
}

export function useSessao(): ValorSessao {
  const v = useContext(Contexto);
  if (!v) throw new Error('useSessao precisa estar dentro de ProvedorSessao');
  return v;
}
