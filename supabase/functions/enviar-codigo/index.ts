// Primeiro acesso e troca de senha: gera o código de acesso e pede ao n8n para enviar o e-mail.
// Responde sempre do mesmo jeito, para não revelar quem tem acesso cadastrado.
import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

const cabecalhos = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const INTERVALO_SEGUNDOS = 60;
const responder = (status: number, corpo: unknown) => new Response(JSON.stringify(corpo), { status, headers: { ...cabecalhos, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cabecalhos });
  if (req.method !== 'POST') return responder(405, { erro: 'Use POST' });
  let email = '';
  try { email = String((await req.json())?.email ?? '').trim().toLowerCase(); } catch { /* corpo inválido */ }
  if (!EMAIL.test(email)) return responder(400, { erro: 'E-mail inválido' });

  const servico = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });

  // Um código por minuto para cada e-mail.
  const { data: ultimo } = await servico.from('codigos_acesso_envios').select('enviado_em').eq('email', email).maybeSingle();
  if (ultimo && Date.now() - new Date(ultimo.enviado_em).getTime() < INTERVALO_SEGUNDOS * 1000) return responder(429, { erro: 'Aguarde um minuto para pedir outro código.' });

  // Registra o pedido para qualquer e-mail, para a resposta não revelar quem tem acesso.
  await servico.from('codigos_acesso_envios').upsert({ email, enviado_em: new Date().toISOString() });
  const { data: usuario } = await servico.from('usuarios').select('nome, ativo').eq('email', email).maybeSingle();
  if (!usuario?.ativo) return responder(200, { ok: true });
  const { data: link, error } = await servico.auth.admin.generateLink({ type: 'magiclink', email });
  const codigo = link?.properties?.email_otp;
  if (error || !codigo) return responder(500, { erro: 'Não foi possível gerar o código. Tente de novo.' });

  const { data: conf } = await servico.from('configuracao_privada').select('chave, valor').in('chave', ['n8n_codigo_url', 'n8n_codigo_chave']);
  const valor = (k: string) => conf?.find((c) => c.chave === k)?.valor ?? '';
  const r = await fetch(valor('n8n_codigo_url'), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-chave-portal': valor('n8n_codigo_chave') },
    body: JSON.stringify({ email, nome: String(usuario.nome ?? '').split(' ')[0], codigo }),
    signal: AbortSignal.timeout(20000),
  }).catch(() => null);
  if (!r?.ok) {
    await servico.from('codigos_acesso_envios').delete().eq('email', email);
    return responder(502, { erro: 'O envio do e-mail falhou. Tente de novo em instantes.' });
  }
  return responder(200, { ok: true });
});
