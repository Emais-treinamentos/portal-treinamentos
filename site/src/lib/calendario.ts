// Levar um treinamento para o calendário do Outlook: link direto ou arquivo .ics.
export type EventoAgenda = { id: string; titulo: string; inicio: string; fim: string; sala: string | null; detalhes?: string };

const utc = (d: string) => new Date(d).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const texto = (t: string) => t.replace(/\\/g, '\\\\').replace(/[,;]/g, (x) => `\\${x}`).replace(/\n/g, '\\n');

// O corpo do evento no Outlook web é HTML: sem <br> as linhas ficariam emendadas.
const paraHtml = (t: string) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>');

export function linkOutlook(e: EventoAgenda) {
  const q = new URLSearchParams({ path: '/calendar/action/compose', rru: 'addevent', subject: e.titulo, startdt: new Date(e.inicio).toISOString(), enddt: new Date(e.fim).toISOString(), location: e.sala ?? '', body: paraHtml(e.detalhes ?? '') });
  return `https://outlook.office.com/calendar/0/deeplink/compose?${q.toString()}`;
}

// O padrão do .ics pede linhas curtas: as longas continuam na linha seguinte, iniciada por espaço.
const dobrar = (l: string) => (l.match(/.{1,60}/gu) ?? ['']).join('\r\n ');

export function baixarIcs(eventos: EventoAgenda[], nome: string) {
  const agora = utc(new Date().toISOString());
  const corpo = eventos.map((e) => ['BEGIN:VEVENT', `UID:${e.id}@portal-treinamentos.emais`, `DTSTAMP:${agora}`, `DTSTART:${utc(e.inicio)}`, `DTEND:${utc(e.fim)}`, `SUMMARY:${texto(e.titulo)}`, `LOCATION:${texto(e.sala ?? '')}`, dobrar(`DESCRIPTION:${texto(e.detalhes ?? '')}`), 'END:VEVENT'].join('\r\n'));
  const ics = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Grupo Emais//Portal de Treinamentos//PT-BR', 'CALSCALE:GREGORIAN', ...corpo, 'END:VCALENDAR'].join('\r\n');
  const url = URL.createObjectURL(new Blob([ics], { type: 'text/calendar;charset=utf-8' }));
  const a = document.createElement('a'); a.href = url; a.download = nome; a.click(); URL.revokeObjectURL(url);
}
