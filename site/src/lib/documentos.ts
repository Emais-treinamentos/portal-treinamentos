import jsPDF from 'jspdf';
import { cargaTexto, dataBR, hora, horaFim, rpc, type SituacaoColaborador, type TurmaDetalhe } from './api';

type RGB = [number, number, number];
const verde: RGB = [0, 102, 102];
const cinza: RGB = [240, 240, 240];
const logoUrl = `${import.meta.env.BASE_URL}logo-emais.png`;

async function carregarLogo(): Promise<HTMLImageElement | null> {
  return new Promise((ok) => {
    const img = new Image();
    img.onload = () => ok(img);
    img.onerror = () => ok(null);
    img.src = logoUrl;
  });
}

const nomeArquivo = (n: string) => n.replace(/\s+/g, '_');

// F.109, Rev. 01: lista de treinamentos que a pessoa fez.
export async function gerarF109(s: SituacaoColaborador) {
  const pdf = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
  const logo = await carregarLogo();
  const m = 10; const W = pdf.internal.pageSize.getWidth() - m * 2; const H = pdf.internal.pageSize.getHeight() - m;
  let y = m;
  const linhas = (t: string, w: number) => pdf.splitTextToSize(t, Math.max(w - 4, 4)) as string[];
  const celula = (t: string, x: number, yy: number, w: number, h: number, o: { fill?: RGB; bold?: boolean; size?: number; align?: 'left' | 'center'; color?: RGB } = {}) => {
    pdf.setDrawColor(153, 153, 153); pdf.setLineWidth(0.2);
    if (o.fill) { pdf.setFillColor(...o.fill); pdf.rect(x, yy, w, h, 'FD'); } else pdf.rect(x, yy, w, h);
    pdf.setFont('helvetica', o.bold ? 'bold' : 'normal'); pdf.setFontSize(o.size ?? 9); pdf.setTextColor(...(o.color ?? ([0, 0, 0] as RGB)));
    const l = t ? linhas(t, w) : []; const lh = (o.size ?? 9) * 0.38;
    const sy = yy + Math.max(4.2, (h - l.length * lh) / 2 + lh - 0.5);
    if (l.length) pdf.text(l, o.align === 'center' ? x + w / 2 : x + 2, sy, { align: o.align ?? 'left', maxWidth: w - 4 });
    pdf.setTextColor(0, 0, 0);
  };
  // Cabeçalho do documento controlado
  const lw = 48, mw = 94, rw = W - lw - mw;
  pdf.setDrawColor(153, 153, 153); pdf.rect(m, y, W, 26); pdf.line(m + lw, y, m + lw, y + 26); pdf.line(m + lw + mw, y, m + lw + mw, y + 26);
  if (logo) { try { pdf.addImage(logo, 'PNG', m + 8, y + 7, 31, 11); } catch { /* segue sem logo */ } }
  pdf.setFont('helvetica', 'bold'); pdf.setFontSize(11); pdf.text('Sistema de Gestão da Qualidade', m + lw + mw / 2, y + 10, { align: 'center' });
  pdf.setFontSize(10); pdf.text('Lista de Treinamento Onboarding', m + lw + mw / 2, y + 17, { align: 'center' });
  [['Código', 'F.109'], ['Revisão', '01'], ['Data ver.:', '07/2026']].forEach(([a, b], i) => {
    const yy = y + i * (26 / 3); celula(a, m + lw + mw, yy, 22, 26 / 3, { bold: true, size: 8 }); celula(b, m + lw + mw + 22, yy, rw - 22, 26 / 3, { size: 8 });
  });
  y += 37;
  const c = s.colaborador;
  celula('Colaborador', m, y, 42, 8, { fill: cinza, bold: true }); celula(c.nome, m + 42, y, W - 42, 8); y += 8;
  celula('Cargo', m, y, 42, 8, { fill: cinza, bold: true }); celula(c.cargo ?? '', m + 42, y, 68, 8); celula('Data Admissão', m + 110, y, 38, 8, { fill: cinza, bold: true }); celula(dataBR(c.data_admissao), m + 148, y, W - 148, 8, { align: 'center' }); y += 8;
  celula('Setor / Área', m, y, 42, 8, { fill: cinza, bold: true }); celula(c.departamento ?? '', m + 42, y, W - 42, 8); y += 14;
  const ws = [10, 72, 20, 25, 25, 38]; const xs = ws.map((_, i) => m + ws.slice(0, i).reduce((a, b) => a + b, 0));
  const titulo = () => {
    ['#', 'Treinamento', 'C.H.', 'Data', 'Status', 'Cód. Registro da Turma'].forEach((t, i) => celula(t, xs.at(i)!, y, ws.at(i)!, 9, { fill: verde, bold: true, size: 8, align: i === 1 ? 'left' : 'center', color: [255, 255, 255] }));
    y += 9;
  };
  titulo();
  const feitos = s.historico.filter((h) => h.situacao === 'presente');
  if (!feitos.length) { celula('Nenhum treinamento registrado', m, y, W, 10, { align: 'center', color: [120, 120, 120] }); y += 10; }
  feitos.forEach((d, i) => {
    const h = Math.max(8, 4 + linhas(d.treinamento, ws[1]).length * 3.8);
    if (y + h > H) { pdf.addPage(); y = m; titulo(); }
    [String(i + 1), d.treinamento, cargaTexto(d.carga_minutos), dataBR(d.data), 'Realizado', d.turma_id.slice(0, 8).toUpperCase()].forEach((v, j) =>
      celula(v, xs.at(j)!, y, ws.at(j)!, h, { size: j === 5 ? 7 : 8, align: j === 1 ? 'left' : 'center', bold: j === 4, color: j === 4 ? verde : [0, 0, 0] }));
    y += h;
  });
  y += 6;
  pdf.setFont('helvetica', 'bold'); pdf.setFontSize(9); pdf.text(`Carga Horária Total: ${cargaTexto(feitos.reduce((a, d) => a + d.carga_minutos, 0))}`, m + W - 2, y, { align: 'right' }); y += 8;
  if (y + 35 > H) { pdf.addPage(); y = m; }
  pdf.rect(m, y, W, 35); pdf.text('Declaro que participei dos treinamentos acima descritos.', m + 4, y + 8);
  const fy = y + 18;
  [{ r: 'Nome do Colaborador', v: c.nome, x: m + 4, w: 72 }, { r: 'Assinatura', v: '', x: m + 82, w: 64 }, { r: 'Data', v: '____/____/________', x: m + 152, w: W - 156 }].forEach((f) => {
    pdf.setFont('helvetica', 'normal'); pdf.setFontSize(8); pdf.setTextColor(102, 102, 102); pdf.text(f.r, f.x, fy); pdf.setTextColor(0, 0, 0); pdf.line(f.x, fy + 8, f.x + f.w, fy + 8);
    if (f.v) pdf.text(f.v, f.x, fy + 6, { maxWidth: f.w });
  });
  y += 40;
  if (y + 70 > H) { pdf.addPage(); y = m; }
  pdf.rect(m, y, W, 70); pdf.setFillColor(...cinza); pdf.rect(m + 4, y + 4, W - 8, 9, 'F');
  pdf.setFont('helvetica', 'bold'); pdf.setFontSize(10); pdf.text('Avaliação de Eficácia', m + W / 2, y + 10.5, { align: 'center' });
  pdf.setFont('helvetica', 'italic'); pdf.setFontSize(8); pdf.setTextColor(120, 120, 120); pdf.text('(Preencher após 90 dias da conclusão dos treinamentos)', m + 4, y + 20); pdf.setTextColor(0, 0, 0);
  let ry = y + 25;
  [['Data da Avaliação', 8], ['Avaliador', 8], ['Resultado', 8], ['Observações', 21]].forEach(([r, h]) => {
    celula(r as string, m + 4, ry, 50, h as number, { fill: cinza, bold: true, size: 8 }); celula('', m + 54, ry, W - 58, h as number); ry += h as number;
  });
  pdf.save(`F109_${nomeArquivo(c.nome)}.pdf`);
}

// Grade de treinamentos: turmas da pessoa, sem canceladas ou recusadas.
export async function gerarGrade(s: SituacaoColaborador) {
  const ids = [...new Set(s.historico.filter((h) => ['presente', 'convocado'].includes(h.situacao)).map((h) => h.turma_id))];
  const turmas = await Promise.all(ids.map((id) => rpc<TurmaDetalhe>('turma_detalhe', { p_turma: id })));
  const rows = turmas.filter((t) => !['cancelada', 'precisa_replanejar'].includes(t.status)).sort((a, b) => `${a.data}${a.hora_inicio}`.localeCompare(`${b.data}${b.hora_inicio}`));
  if (!rows.length) throw new Error('Esta pessoa ainda não tem turmas para a grade.');
  const doc = new jsPDF({ orientation: 'landscape', unit: 'mm', format: 'a4' });
  const logo = await carregarLogo();
  const m = 10; const pw = doc.internal.pageSize.getWidth(); const ph = doc.internal.pageSize.getHeight(); const W = pw - m * 2;
  if (logo) { try { doc.addImage(logo, 'PNG', m, 8, 40, 16); } catch { /* segue sem logo */ } }
  doc.setFillColor(...verde); doc.rect(m, 32, W, 10, 'F'); doc.setTextColor(255, 255, 255); doc.setFontSize(11); doc.setFont('helvetica', 'bold');
  doc.text('INTEGRAÇÃO DO COLABORADOR EMAIS', pw / 2, 39, { align: 'center' });
  doc.setFillColor(...cinza); doc.rect(m, 46, W, 9, 'F'); doc.setTextColor(40, 40, 40); doc.setFontSize(10);
  doc.text(`${s.colaborador.nome.toUpperCase()}  |  ${(s.colaborador.cargo ?? '').toUpperCase()}`, pw / 2, 52.5, { align: 'center' });
  const cols = [['TREINAMENTOS', 0.28], ['RESP. TREINAMENTO', 0.2], ['CARGA HORÁRIA', 0.08], ['DATA', 0.09], ['HORA - INÍCIO', 0.08], ['HORA - TÉRMINO', 0.09], ['LOCAL', 0.18]] as const;
  let y = 60; let x = m; const rh = 9;
  doc.setFillColor(...verde); doc.rect(m, y, W, rh, 'F'); doc.setTextColor(255, 255, 255); doc.setFontSize(7);
  cols.forEach(([t, f]) => { doc.text(t, x + (W * f) / 2, y + 6, { align: 'center' }); x += W * f; });
  doc.setFont('helvetica', 'normal'); y += rh;
  rows.forEach((t, i) => {
    if (y + rh > ph - 10) { doc.addPage(); y = 15; }
    doc.setFillColor(i % 2 ? 245 : 255, i % 2 ? 245 : 255, i % 2 ? 245 : 255); doc.rect(m, y, W, rh, 'F'); doc.setDrawColor(220, 220, 220); doc.rect(m, y, W, rh, 'S');
    const h = t.hora_inicio ?? t.hora_opcao_1;
    const v = [t.treinamento, t.instrutor_email, cargaTexto(t.carga_minutos), dataBR(t.data), hora(h), horaFim(h, t.carga_minutos), t.sala ?? ''];
    doc.setTextColor(40, 40, 40); x = m;
    cols.forEach(([, f], j) => {
      const w = W * f; const l = doc.splitTextToSize(v.at(j) ?? '', w - 4) as string[];
      doc.text(l.at(0) ?? '', j === 0 ? x + 2 : x + w / 2, y + 6, { align: j === 0 ? 'left' : 'center' }); x += w;
    });
    y += rh;
  });
  doc.save(`Grade_Treinamentos_${nomeArquivo(s.colaborador.nome)}.pdf`);
}

// Lista de presença da turma, para assinatura em papel.
export async function gerarListaPresenca(t: TurmaDetalhe) {
  const pdf = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
  const logo = await carregarLogo();
  const m = 15; const pw = pdf.internal.pageSize.getWidth(); const W = pw - m * 2; const ph = pdf.internal.pageSize.getHeight();
  if (logo) { try { pdf.addImage(logo, 'PNG', m, 10, 36, 13); } catch { /* segue sem logo */ } }
  pdf.setFont('helvetica', 'bold'); pdf.setFontSize(13); pdf.text('LISTA DE PRESENÇA', pw / 2, 30, { align: 'center' });
  pdf.setFontSize(10); pdf.setFont('helvetica', 'normal');
  const h = t.hora_inicio ?? t.hora_opcao_1;
  [`Treinamento: ${t.treinamento}`, `Data: ${dataBR(t.data)}   Horário: ${hora(h)} às ${horaFim(h, t.carga_minutos)}   Carga horária: ${cargaTexto(t.carga_minutos)}`, `Sala: ${t.sala ?? ''}   Instrutor: ${t.instrutor_email}`].forEach((l, i) => pdf.text(l, m, 40 + i * 6));
  let y = 60;
  const cab = () => { pdf.setFillColor(...verde); pdf.rect(m, y, W, 8, 'F'); pdf.setTextColor(255, 255, 255); pdf.setFont('helvetica', 'bold'); pdf.setFontSize(9); pdf.text('Nome', m + 2, y + 5.5); pdf.text('Cargo', m + 72, y + 5.5); pdf.text('Assinatura', m + 130, y + 5.5); pdf.setTextColor(0, 0, 0); pdf.setFont('helvetica', 'normal'); y += 8; };
  cab();
  t.participantes.filter((p) => p.situacao !== 'nao_aplicavel').forEach((p) => {
    if (y + 10 > ph - 15) { pdf.addPage(); y = 15; cab(); }
    pdf.setDrawColor(180, 180, 180); pdf.rect(m, y, W, 10); pdf.line(m + 70, y, m + 70, y + 10); pdf.line(m + 128, y, m + 128, y + 10);
    pdf.setFontSize(8.5); pdf.text((pdf.splitTextToSize(p.nome, 66) as string[]).at(0) ?? '', m + 2, y + 6.5); pdf.text((pdf.splitTextToSize(p.cargo ?? '', 54) as string[]).at(0) ?? '', m + 72, y + 6.5); y += 10;
  });
  pdf.save(`Lista_Presenca_${nomeArquivo(t.treinamento)}_${t.data ?? ''}.pdf`);
}

const TEXTOS_TERMO = {
  contexto: 'Conforme diretriz interna da Emais Urbanismo, baseada no critério de análise de reciclagem de treinamentos, colaboradores com mais de 24 meses de empresa e que tenham sido movimentados internamente nos últimos 24 meses passam por avaliação de lacunas de capacitação, considerando como referência a última movimentação interna, com base na matriz de treinamentos vigente.',
  resultado: 'Após análise técnica realizada pelo setor de Gente & Gestão, foi constatado que o(a) colaborador(a) não apresenta lacunas de conhecimento, nem necessidade de atualização nos treinamentos obrigatórios, técnicos ou informativos relacionados à sua nova função.',
  motivos: ['Concluiu todos os treinamentos obrigatórios relacionados ao cargo atual.', 'Em caso de movimentação interna nos últimos 24 meses, concluiu também os treinamentos exigidos para o novo cargo.', 'Não houve mudança de escopo técnico ou estratégico na movimentação.', 'Os conteúdos aplicáveis à nova função permanecem os mesmos da função anterior.', 'Outros (especificar): _______________________________________________'],
  d1: 'Declaro, para os devidos fins, que fui devidamente informado(a) sobre a política de reciclagem de treinamentos e que, nesta ocasião, estou sendo dispensado(a) da participação em treinamentos de reciclagem em razão da justificativa mencionada acima.',
  d2: 'Estou ciente de que esta decisão está registrada e poderá ser revista caso haja alteração nas políticas internas, atualização de conteúdos ou mudanças futuras em meu cargo ou departamento.',
};

// Termo de Dispensa, com os textos do modelo oficial. Motivos marcados à caneta na assinatura.
export async function gerarTermoDispensa(s: SituacaoColaborador) {
  const pdf = new jsPDF({ orientation: 'portrait', unit: 'mm', format: 'a4' });
  const logo = await carregarLogo();
  const pw = pdf.internal.pageSize.getWidth(); const ph = pdf.internal.pageSize.getHeight(); const m = 20; const W = pw - m * 2; let y = m;
  const garantir = (h: number) => { if (y + h > ph - m) { pdf.addPage(); y = m; } };
  const secao = (t: string) => { garantir(14); pdf.setFont('helvetica', 'bold'); pdf.setFontSize(11); pdf.text(t, m, y); y += 6; };
  const texto = (t: string, gap = 5) => { pdf.setFont('helvetica', 'normal'); pdf.setFontSize(10); const l = pdf.splitTextToSize(t, W) as string[]; garantir(l.length * 4.5 + gap); pdf.text(l, m, y); y += l.length * 4.5 + gap; };
  if (logo) { try { pdf.addImage(logo, 'PNG', m, y, 40, 14); } catch { /* segue sem logo */ } }
  y += 20; pdf.setFont('helvetica', 'bold'); pdf.setFontSize(14); pdf.text('TERMO DE DISPENSA DE RECICLAGEM DE TREINAMENTOS', pw / 2, y, { align: 'center', maxWidth: W }); y += 10;
  const campo = (r: string, v: string) => { pdf.setFont('helvetica', 'bold'); pdf.setFontSize(10); pdf.text(`${r}:`, m, y); const w = pdf.getTextWidth(`${r}: `); pdf.setFont('helvetica', 'normal'); pdf.text(v, m + w, y); pdf.setLineWidth(0.2); pdf.line(m + w + (v ? pdf.getTextWidth(v) + 1 : 0), y + 1, m + W, y + 1); y += 8; };
  const [atual, anterior] = s.movimentacoes;
  campo('Nome do Colaborador', s.colaborador.nome); campo('Cargo Atual', s.colaborador.cargo ?? ''); campo('Cargo Anterior', anterior?.cargo ?? ''); campo('Departamento', s.colaborador.departamento ?? '');
  campo('Data da última Movimentação', dataBR(anterior?.data_inicio)); campo('Data da Movimentação atual', dataBR(atual?.data_inicio)); y += 4;
  secao('1. Contexto da Avaliação'); texto(TEXTOS_TERMO.contexto); secao('2. Resultado da Avaliação'); texto(TEXTOS_TERMO.resultado); secao('3. Motivo da Dispensa');
  TEXTOS_TERMO.motivos.forEach((t) => { const l = pdf.splitTextToSize(t, W - 10) as string[]; garantir(l.length * 4.5 + 3); pdf.setLineWidth(0.3); pdf.rect(m + 1, y - 3.2, 3.5, 3.5); pdf.setFont('helvetica', 'normal'); pdf.setFontSize(10); pdf.text(l, m + 8, y); y += l.length * 4.5 + 3; });
  y += 4; secao('4. Treinamentos Realizados (Lista de treinamentos com datas de realização)');
  const feitos = s.historico.filter((h) => h.situacao === 'presente');
  if (!feitos.length) texto('Nenhum treinamento confirmado registrado.', 4);
  feitos.forEach((f) => texto(`${f.treinamento}: ${dataBR(f.data)}`, 2));
  y += 3; garantir(60); secao('5. Declaração'); texto(TEXTOS_TERMO.d1); texto(TEXTOS_TERMO.d2, 8);
  garantir(40); pdf.setFont('helvetica', 'normal'); pdf.setFontSize(10); pdf.text('Local e Data: _______________________, ____/____/______', m, y); y += 22;
  pdf.setLineWidth(0.3); pdf.line((pw - 80) / 2, y, (pw + 80) / 2, y); y += 5; pdf.text('Assinatura do Colaborador', pw / 2, y, { align: 'center' });
  pdf.save(`Termo_Dispensa_${nomeArquivo(s.colaborador.nome)}.pdf`);
}
