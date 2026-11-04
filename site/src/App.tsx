import { useEffect, type ReactNode } from 'react';
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom';
import { useSessao, type Perfil } from './lib/sessao';
import { Carregando } from './componentes/Carregando';
import { Entrar } from './paginas/Entrar';
import { EsqueciSenha } from './paginas/EsqueciSenha';
import { NovaSenha } from './paginas/NovaSenha';
import { AcessoBloqueado } from './paginas/AcessoBloqueado';
import { Inicio } from './paginas/Inicio';
import { Turmas } from './paginas/Turmas';
import { Planejar } from './paginas/Planejar';
import { MinhasTurmas } from './paginas/MinhasTurmas';
import { Colaboradores, MeusTreinamentos } from './paginas/Colaboradores';
import { Movimentacoes } from './paginas/Movimentacoes';
import { Matriz } from './paginas/Matriz';
import { Cadastros } from './paginas/Cadastros';
import { Indicadores } from './paginas/Indicadores';
import { Acessos } from './paginas/Acessos';
import { Envios } from './paginas/Envios';

export function App() {
  const { recuperandoSenha } = useSessao();
  const navegar = useNavigate();
  useEffect(() => { if (recuperandoSenha) navegar('/nova-senha', { replace: true }); }, [recuperandoSenha, navegar]);
  const gestao: Perfil[] = ['admin'];
  return (
    <Routes>
      <Route path="/entrar" element={<SoForaDoLogin><Entrar /></SoForaDoLogin>} />
      <Route path="/esqueci-senha" element={<SoForaDoLogin><EsqueciSenha /></SoForaDoLogin>} />
      <Route path="/nova-senha" element={<NovaSenha />} />
      <Route path="/" element={<ComLogin><Inicio /></ComLogin>} />
      <Route path="/planejar" element={<SoPerfil perfil={['admin']}><Planejar /></SoPerfil>} />
      <Route path="/turmas" element={<SoPerfil perfil={gestao}><Turmas /></SoPerfil>} />
      <Route path="/minhas-turmas" element={<ComLogin><MinhasTurmas /></ComLogin>} />
      <Route path="/colaboradores" element={<SoPerfil perfil={[...gestao, 'gestor']}><Colaboradores /></SoPerfil>} />
      <Route path="/meus-treinamentos" element={<ComLogin><MeusTreinamentos /></ComLogin>} />
      <Route path="/movimentacoes" element={<SoPerfil perfil={['admin']}><Movimentacoes /></SoPerfil>} />
      <Route path="/matriz" element={<SoPerfil perfil={['admin']}><Matriz /></SoPerfil>} />
      <Route path="/cadastros" element={<SoPerfil perfil={['admin']}><Cadastros /></SoPerfil>} />
      <Route path="/indicadores" element={<SoPerfil perfil={gestao}><Indicadores /></SoPerfil>} />
      <Route path="/acessos" element={<SoPerfil perfil={['admin']}><Acessos /></SoPerfil>} />
      <Route path="/envios" element={<SoPerfil perfil={['admin']}><Envios /></SoPerfil>} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

function ComLogin({ children }: { children: ReactNode }) {
  const { situacao } = useSessao();
  if (situacao === 'carregando') return <Carregando />;
  if (situacao === 'fora') return <Navigate to="/entrar" replace />;
  if (situacao === 'sem_cadastro' || situacao === 'inativo') return <AcessoBloqueado motivo={situacao} />;
  return <>{children}</>;
}

function SoPerfil({ perfil, children }: { perfil: Perfil[]; children: ReactNode }) {
  const { usuario } = useSessao();
  return <ComLogin>{usuario && perfil.includes(usuario.perfil) ? children : <Navigate to="/" replace />}</ComLogin>;
}

function SoForaDoLogin({ children }: { children: ReactNode }) {
  const { situacao } = useSessao();
  if (situacao === 'carregando') return <Carregando />;
  if (situacao === 'fora') return <>{children}</>;
  return <Navigate to="/" replace />;
}
