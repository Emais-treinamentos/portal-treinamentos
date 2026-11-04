import { useState } from 'react';
import { Link } from 'react-router-dom';
import { Pagina, Mensagem } from '../componentes/Pagina';
import { Carregando } from '../componentes/Carregando';
import { Dialogo } from '../componentes/Dialogo';
import { Calendario, type EventoCal } from '../componentes/Calendario';
import { Campo, FormDialogo, SeloSituacao } from '../componentes/Pecas';
import { cargaTexto, dataBR, hora, horaFim, nomesSituacao, rpc, useDados, type SituacaoColaborador } from '../lib/api';
import { supabase } from '../lib/supabase';
import { useSessao } from '../lib/sessao';

type TurmaCal = { id: string; treinamento: string; status: string; etapa: string; data: string; hora: string | null; carga_minutos: number; sala: string | null; instrutor: string; minha_situacao: string; participantes: string[] };
type Pendente = { turma_id: string; treinamento: string; data: string | null };

const usePendentes = () => useDados(() => rpc<Pendente[]>('minhas_avaliacoes'));

export function MeuCalendario() {
  const lista = useDados(() => rpc<TurmaCal[]>('meu_calendario'));
  const pend = usePendentes();
  const [sel, setSel] = useState<string | null>(null);
  const t = lista.dados?.find((x) => x.id === sel);
  const n = pend.dados?.length ?? 0;
  const eventos: EventoCal[] = (lista.dados ?? []).map((x) => ({ id: x.id, titulo: x.treinamento, data: x.data, hora: x.hora, cor: x.etapa === 'agendadas' ? 'confirmado' : 'feito' }));
  return (
    <Pagina titulo="Meu Calendário" apoio="Seus treinamentos do mês. Clique em um deles para ver instrutor, sala e participantes.">
      {lista.erro && <Mensagem tipo="erro">{lista.erro}</Mensagem>}
      {n > 0 && <div className="aviso-avaliar"><span>{n === 1 ? 'Você tem 1 treinamento para avaliar.' : `Você tem ${n} treinamentos para avaliar.`}</span><Link className="botao botao-pequeno" to="/meu-perfil">Avaliar</Link></div>}
      {lista.carregando && !lista.dados && <Carregando />}
      {lista.dados && <Calendario eventos={eventos} aoAbrir={setSel} legenda={[['confirmado', 'Agendado'], ['feito', 'Já ocorreu']]} />}
      {t && (
        <Dialogo aberto titulo={t.treinamento} aoFechar={() => setSel(null)}>
          <div className="detalhe">
            <dl className="dados">
              <div><dt>Data</dt><dd>{dataBR(t.data)}</dd></div>
              <div><dt>Horário</dt><dd>{hora(t.hora)} às {horaFim(t.hora, t.carga_minutos)}</dd></div>
              <div><dt>Carga</dt><dd>{cargaTexto(t.carga_minutos)}</dd></div>
              <div><dt>Sala</dt><dd>{t.sala ?? 'A definir'}</dd></div>
              <div><dt>Instrutor</dt><dd>{t.instrutor}</dd></div>
              <div><dt>Sua situação</dt><dd>{nomesSituacao[t.minha_situacao] ?? t.minha_situacao}</dd></div>
            </dl>
            <div>
              <h3>Participantes ({t.participantes.length})</h3>
              {t.participantes.map((p) => <div className="pessoa" key={p}><span>{p}</span></div>)}
            </div>
          </div>
        </Dialogo>
      )}
    </Pagina>
  );
}

export function MeuPerfil() {
  const { usuario } = useSessao();
  const meu = useDados(async () => (await supabase.from('usuarios').select('colaborador_id').eq('id', usuario!.id).single()).data?.colaborador_id as string | null);
  return (
    <Pagina titulo="Meu Perfil" apoio="Seus dados, seu histórico e a situação dos seus treinamentos.">
      {meu.carregando && !meu.dados && <Carregando />}
      {meu.dados ? <Perfil id={meu.dados} /> : !meu.carregando && <p className="vazio">Seu acesso ainda não está ligado a um colaborador. Fale com Gente e Gestão.</p>}
    </Pagina>
  );
}

function Perfil({ id }: { id: string }) {
  const d = useDados(() => rpc<SituacaoColaborador>('situacao_colaborador', { p_colaborador: id }), [id]);
  const pend = usePendentes();
  const [avaliar, setAvaliar] = useState<Pendente | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const s = d.dados;
  if (!s) return d.erro ? <Mensagem tipo="erro">{d.erro}</Mensagem> : <Carregando />;
  const c = s.colaborador;
  const feitos = s.itens.filter((i) => i.situacao === 'realizado').length;
  return (
    <>
      {msg && <Mensagem tipo="ok" aoFechar={() => setMsg(null)}>{msg}</Mensagem>}
      {(pend.dados ?? []).map((p) => (
        <div className="aviso-avaliar" key={p.turma_id}>
          <span><strong>Como foi o treinamento de {p.treinamento}?</strong><small>Realizado em {dataBR(p.data)}. Leva menos de 1 minuto e sua resposta é confidencial.</small></span>
          <button className="botao botao-pequeno" type="button" onClick={() => setAvaliar(p)}>Avaliar</button>
        </div>
      ))}
      <section className="plano-etapa">
        <h2>{c.nome}</h2>
        <dl className="dados">
          <div><dt>Cargo</dt><dd>{c.cargo}</dd></div>
          <div><dt>Departamento</dt><dd>{c.departamento}</dd></div>
          <div><dt>Data de admissão</dt><dd>{dataBR(c.data_admissao)}</dd></div>
        </dl>
      </section>
      <section className="plano-etapa">
        <h2>Meus treinamentos <small>{feitos} de {s.itens.length} feitos</small></h2>
        {!s.itens.length && <p className="apoio">Nenhum treinamento obrigatório para o seu cargo.</p>}
        <div>
          {s.itens.map((i) => (
            <div className="pessoa" key={i.treinamento_id}>
              <span>{i.treinamento}<small>{i.ultima ? `Realizado em ${dataBR(i.ultima)}` : i.data_turma ? `Turma em ${dataBR(i.data_turma)}` : ''}</small></span>
              <SeloSituacao situacao={i.situacao} />
            </div>
          ))}
        </div>
      </section>
      {s.movimentacoes.length > 1 && (
        <section className="plano-etapa">
          <h2>Histórico de movimentações</h2>
          <div>{s.movimentacoes.map((m, i) => <div className="pessoa" key={i}><span>{m.cargo}<small>{m.tipo}</small></span><small>{dataBR(m.data_inicio)}{m.data_fim ? ` a ${dataBR(m.data_fim)}` : ' até hoje'}</small></div>)}</div>
        </section>
      )}
      {avaliar && <FormAvaliacao p={avaliar} aoFechar={() => setAvaliar(null)} aoEnviar={() => { setMsg('Avaliação enviada de forma confidencial. Obrigado.'); void pend.recarregar(); }} />}
    </>
  );
}

const topicos = [['conteudo', 'O conteúdo será útil no meu dia a dia'], ['instrutor', 'O instrutor explicou com clareza'], ['tempo', 'O tempo foi suficiente'], ['local', 'A sala e o material estavam adequados']] as const;
const opcoes = [['nao', 'Não'], ['parte', 'Em parte'], ['sim', 'Sim']] as const;
const pontos = ['Mais exemplos práticos', 'Mais tempo', 'Sala ou local', 'Material', 'Linguagem mais simples', 'Pontualidade'];
const horarios = [['horario', 'Sim, no horário'], ['ate_15', 'Atrasou até 15 minutos'], ['mais_15', 'Atrasou mais de 15 minutos']] as const;

function FormAvaliacao({ p, aoFechar, aoEnviar }: { p: Pendente; aoFechar: () => void; aoEnviar: () => void }) {
  const [nota, setNota] = useState(0);
  const [pont, setPont] = useState('');
  const [resp, setResp] = useState<Record<string, string>>({});
  const [melhorias, setMelhorias] = useState<string[]>([]);
  const [comentario, setComentario] = useState('');
  const completo = nota > 0 && !!pont && topicos.every(([k]) => resp[k]);
  return (
    <FormDialogo titulo="Como foi o treinamento?" rotulo="Enviar avaliação" desabilitar={!completo} aoFechar={aoFechar}
      aoEnviar={async () => { await rpc('enviar_avaliacao', { p_turma: p.turma_id, p_nota: nota, p_pontualidade: pont, p_conteudo: resp.conteudo, p_instrutor: resp.instrutor, p_tempo: resp.tempo, p_local: resp.local, p_melhorias: melhorias, p_comentario: comentario || null }); aoEnviar(); }}>
      <p className="apoio">{p.treinamento}, {dataBR(p.data)}</p>
      <fieldset className="aval-grupo"><legend>Sua nota geral</legend>
        <div className="aval-notas">{[1, 2, 3, 4, 5].map((n) => <button key={n} type="button" className="aval-opcao" aria-pressed={nota === n} onClick={() => setNota(n)}>{n}</button>)}</div>
        <div className="aval-escala"><span>Muito ruim</span><span>Excelente</span></div>
      </fieldset>
      <fieldset className="aval-grupo"><legend>O treinamento começou no horário?</legend>
        <div className="aval-lista">{horarios.map(([v, r]) => <button key={v} type="button" className="aval-opcao" aria-pressed={pont === v} onClick={() => setPont(v)}>{r}</button>)}</div>
      </fieldset>
      {topicos.map(([k, r]) => (
        <fieldset className="aval-grupo" key={k}><legend>{r}</legend>
          <div className="aval-tres">{opcoes.map(([v, t]) => <button key={v} type="button" className="aval-opcao" aria-pressed={resp[k] === v} onClick={() => setResp({ ...resp, [k]: v })}>{t}</button>)}</div>
        </fieldset>
      ))}
      <fieldset className="aval-grupo"><legend>O que poderia melhorar? (opcional)</legend>
        <div className="chips">{pontos.map((m) => <button key={m} type="button" className="chip" aria-pressed={melhorias.includes(m)} onClick={() => setMelhorias(melhorias.includes(m) ? melhorias.filter((x) => x !== m) : [...melhorias, m])}>{m}</button>)}</div>
      </fieldset>
      <Campo rotulo="Comentário (opcional)"><textarea rows={3} value={comentario} onChange={(e) => setComentario(e.target.value)} /></Campo>
      <p className="apoio">Evite citar nomes ou detalhes que identifiquem você. Sua resposta é guardada sem o seu nome, e Gente e Gestão vê apenas o conjunto das respostas.</p>
    </FormDialogo>
  );
}
