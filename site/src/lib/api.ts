import { useCallback, useEffect, useState, useRef } from 'react';
import { supabase } from './supabase';

// Toda regra mora no banco. O site só chama as funções e mostra o resultado.
export async function rpc<T = unknown>(nome: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(nome, args);
  if (error) throw new Error(error.message);
  return data as T;
}

export function useDados<T>(carregar: () => Promise<T>, deps: unknown[] = []) {
  const [dados, setDados] = useState<T | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(true);
  const ultimoPedido = useRef(0);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const recarregar = useCallback(async () => {
    // Só a última consulta vale: uma resposta atrasada não pode trocar a tela depois de outra mais nova.
    const pedido = ++ultimoPedido.current;
    setCarregando(true);
    try {
      const novo = await carregar();
      if (pedido !== ultimoPedido.current) return;
      setDados(novo);
      setErro(null);
    } catch (e) {
      if (pedido === ultimoPedido.current) setErro(textoErro(e));
    } finally {
      if (pedido === ultimoPedido.current) setCarregando(false);
    }
  }, deps);
  useEffect(() => { void recarregar(); }, [recarregar]);
  // Ao voltar para a aba, os dados são lidos de novo: a tela nunca fica com a turma antiga.
  useEffect(() => {
    const aoFocar = () => { void recarregar(); };
    window.addEventListener('focus', aoFocar);
    return () => window.removeEventListener('focus', aoFocar);
  }, [recarregar]);
  return { dados, erro, carregando, recarregar };
}

export function textoErro(e: unknown): string {
  const m = e instanceof Error ? e.message : String(e);
  if (/fetch|network/i.test(m)) return 'Sem conexão com o servidor. Confira a internet e tente de novo.';
  return m;
}

export const dataBR = (d?: string | null) => (d ? d.slice(0, 10).split('-').reverse().join('/') : '');
export const hora = (h?: string | null) => (h ? h.slice(0, 5) : '');
export const cargaTexto = (min: number) => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;
export const horaFim = (h: string | null | undefined, min: number) => {
  if (!h) return '';
  const [a, b] = h.split(':').map(Number);
  const t = a * 60 + b + min;
  return `${String(Math.floor(t / 60) % 24).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`;
};

export type Etapa = 'a_planejar' | 'aguardando_instrutor' | 'formalizar' | 'agendadas' | 'presenca' | 'realizadas' | 'canceladas';
export const nomesEtapa: Record<Etapa, string> = {
  a_planejar: 'A planejar', aguardando_instrutor: 'Aguardando instrutor', formalizar: 'Formalizar', agendadas: 'Agendadas',
  presenca: 'Presença a registrar', realizadas: 'Realizadas', canceladas: 'Canceladas',
};

export const nomesStatus: Record<string, string> = {
  pendente: 'Pendente', aguardando_instrutor: 'Aguardando instrutor', agenda_confirmada: 'Agenda confirmada', precisa_replanejar: 'Precisa replanejar',
  convite_enviado: 'Convite enviado', realizada: 'Realizada', encerrada: 'Encerrada, sem presentes', cancelada: 'Cancelada',
};
export const nomesSituacao: Record<string, string> = {
  realizado: 'Realizado', agendado: 'Agendado', planejado: 'Em planejamento', pendente: 'Pendente', ausente: 'Ausente', dispensado: 'Dispensado',
  convocado: 'Convocado', presente: 'Presente', a_validar: 'A validar', nao_aplicavel: 'Não se aplica',
};
export const corSituacao: Record<string, string> = {
  realizado: 'verde', presente: 'verde', dispensado: 'cinza', nao_aplicavel: 'cinza', agendado: 'amarelo', planejado: 'amarelo', convocado: 'amarelo', a_validar: 'amarelo', pendente: 'vermelho', ausente: 'vermelho',
};
export const nomesTipoSolicitacao: Record<string, string> = {
  nova_agenda: 'Nova agenda', alteracao: 'Alteração', cancelamento: 'Cancelamento', correcao_presenca: 'Correção de presença',
};
export const nomesMovimentacao: Record<string, string> = {
  step_horizontal: 'Step horizontal', promocao_lideranca: 'Promoção para liderança', mudanca_departamento: 'Mudança de departamento', promocao_vertical: 'Promoção vertical', interinidade: 'Interinidade',
};
export const nomesAcao: Record<string, string> = { total: 'Total', parcial: 'Parcial', dispensa: 'Dispensa' };

export type Pessoa = { colaborador_id: string; nome: string; cargo: string | null; situacao: string; codigo?: string | null; origem: string };
export type Solicitacao = { id: string; tipo: string; motivo: string; proposta: { data?: string; hora?: string; sala?: string; instrutor_email?: string }; status: string; resposta: string | null; solicitado_em: string };
export type TurmaDetalhe = {
  id: string; treinamento_id: string; treinamento: string; carga_minutos: number; etapa: Etapa; status: string; tipo: string; data: string | null; hora_opcao_1: string | null; hora_opcao_2: string | null; hora_inicio: string | null;
  sala: string | null; instrutor_email: string; motivo_replanejamento: string | null; inicio: string | null; fim: string | null; sou_instrutor: boolean; instrutor_tem_acesso: boolean; presenca_concluida_em: string | null;
  cargos: { cargo_id: string; nome: string; incluir: boolean; elegiveis: number }[];
  participantes: Pessoa[]; solicitacoes: Solicitacao[]; conflitos: { tipo: string; turma_id: string; treinamento: string }[];
};
export type ItemSituacao = { treinamento_id: string; treinamento: string; situacao: string; turma_id: string | null; data_turma: string | null; ultima: string | null };
export type SituacaoColaborador = {
  colaborador: { id: string; nome: string; email: string | null; cargo_id: string; cargo: string; departamento: string; data_admissao: string | null; data_referencia: string | null; ativo: boolean };
  itens: ItemSituacao[];
  historico: { turma_id: string; codigo?: string | null; treinamento: string; carga_minutos: number; data: string | null; situacao: string; origem: string; instrutor_email: string | null; cargo: string | null }[];
  movimentacoes: { cargo: string; data_inicio: string; data_fim: string | null; tipo: string }[];
  decisao: { acao_final: string; tipo_movimentacao: string; decidido_em: string; cargo_anterior_id: string | null } | null;
};
