import { useEffect, type ReactNode } from 'react';
import { Navigate, Route, Routes, useNavigate } from 'react-router-dom';
import { useSessao, type Perfil } from './lib/sessao';
import { Carregando } from './componentes/Carregando';
import { Entrar } from './paginas/Entrar';
import { EsqueciSenha } from './paginas/EsqueciSenha';
import { NovaSenha } from './paginas/NovaSenha';
import { AcessoBloqueado } from './paginas/AcessoBloqueado';
import { EscolherPerfil } from './paginas/EscolherPerfil';
import { Inicio } from './paginas/Inicio';
import { Acompanhar, Formalizar, IrParaTurma, CalendarioGeral } from './paginas/Turmas';
import { Planejar } from './paginas/Planejar';
import { ListaPresenca } from './paginas/ListaPresenca';
import { CalendarioInstrutor, ConfirmarAgenda, MinhasTurmas, PresencaInstrutor } from './paginas/MinhasTurmas';
import { MeuCalendario, MeuPerfil } from './paginas/Colaborador';
import { Satisfacao } from './paginas/Satisfacao';
import { Eficacia } from './paginas/Eficacia';
import { Colaboradores } from './paginas/Colaboradores';
import { Movimentacoes } from './paginas/Movimentacoes';
import { Cadastros } from './paginas/Cadastros';
import { Acessos } from './paginas/Acessos';
import { Notificacoes } from './paginas/Notificacoes';

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
      <Route path="/calendario-geral" element={<SoPerfil perfil={['admin']}><CalendarioGeral /></SoPerfil>} />
      <Route path="/planejar" element={<SoPerfil perfil={['admin']}><Planejar /></SoPerfil>} />
      <Route path="/turmas" element={<SoPerfil perfil={gestao}><IrParaTurma /></SoPerfil>} />
      <Route path="/formalizar" element={<SoPerfil perfil={gestao}><Formalizar /></SoPerfil>} />
      <Route path="/acompanhar" element={<SoPerfil perfil={gestao}><Acompanhar /></SoPerfil>} />
      <Route path="/minhas-turmas" element={<SoPerfil perfil={['admin']}><MinhasTurmas /></SoPerfil>} />
      <Route path="/colaboradores" element={<SoPerfil perfil={['gestor']}><Colaboradores /></SoPerfil>} />
      <Route path="/meus-treinamentos" element={<Navigate to="/meu-perfil" replace />} />
      <Route path="/meu-calendario" element={<SoPerfil perfil={['colaborador', 'gestor']}><MeuCalendario /></SoPerfil>} />
      <Route path="/meu-perfil" element={<SoPerfil perfil={['colaborador', 'gestor']}><MeuPerfil /></SoPerfil>} />
      <Route path="/agenda" element={<SoPerfil perfil={['instrutor']}><ConfirmarAgenda /></SoPerfil>} />
      <Route path="/calendario" element={<SoPerfil perfil={['instrutor']}><CalendarioInstrutor /></SoPerfil>} />
      <Route path="/presenca" element={<SoPerfil perfil={['instrutor']}><PresencaInstrutor /></SoPerfil>} />
      <Route path="/eficacia" element={<SoPerfil perfil={['admin']}><Eficacia /></SoPerfil>} />
      <Route path="/satisfacao" element={<SoPerfil perfil={['admin']}><Satisfacao /></SoPerfil>} />
      <Route path="/lista-presenca" element={<SoPerfil perfil={gestao}><ListaPresenca /></SoPerfil>} />
      <Route path="/reciclagem" element={<SoPerfil perfil={['admin']}><Movimentacoes /></SoPerfil>} />
      <Route path="/cadastros" element={<SoPerfil perfil={['admin']}><Cadastros /></SoPerfil>} />
      <Route path="/acessos" element={<SoPerfil perfil={['admin']}><Acessos /></SoPerfil>} />
      <Route path="/notificacoes" element={<SoPerfil perfil={['admin']}><Notificacoes /></SoPerfil>} />
      <Route path="/envios" element={<Navigate to="/acessos?aba=envios" replace />} />
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  );
}

function ComLogin({ children }: { children: ReactNode }) {
  const { situacao, perfilAtivo } = useSessao();
  if (situacao === 'carregando') return <Carregando />;
  if (situacao === 'fora') return <Navigate to="/entrar" replace />;
  if (situacao === 'sem_cadastro' || situacao === 'inativo') return <AcessoBloqueado motivo={situacao} />;
  if (!perfilAtivo) return <EscolherPerfil />;
  return <>{children}</>;
}

function SoPerfil({ perfil, children }: { perfil: Perfil[]; children: ReactNode }) {
  const { perfilAtivo } = useSessao();
  return <ComLogin>{perfilAtivo && perfil.includes(perfilAtivo) ? children : <Navigate to="/" replace />}</ComLogin>;
}

function SoForaDoLogin({ children }: { children: ReactNode }) {
  const { situacao } = useSessao();
  if (situacao === 'carregando') return <Carregando />;
  if (situacao === 'fora') return <>{children}</>;
  return <Navigate to="/" replace />;
}
