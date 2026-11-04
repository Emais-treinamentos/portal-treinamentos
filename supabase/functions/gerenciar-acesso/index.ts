// Cria acessos e gera o link de primeiro acesso ou de nova senha. Só Gente e Gestão chama.
import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

const cabecalhos = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const DESTINOS = ['https://emais-treinamentos.github.io/portal-treinamentos/', 'http://localhost:5173/portal-treinamentos/', 'http://localhost:4173/portal-treinamentos/'];
const PERFIS = ['admin', 'seguranca', 'gestor', 'colaborador', 'instrutor'];
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const responder = (status: number, corpo: unknown) => new Response(JSON.stringify(corpo), { status, headers: { ...cabecalhos, 'Content-Type': 'application/json' } });
const erro = (status: number, mensagem: string) => responder(status, { erro: mensagem });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cabecalhos });
  if (req.method !== 'POST') return erro(405, 'Use POST');
  const servico = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false, autoRefreshToken: false } });

  const token = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
  const { data: quem } = token ? await servico.auth.getUser(token) : { data: null };
  if (!quem?.user) return erro(401, 'Sessão inválida. Entre de novo no portal.');
  const { data: chamador } = await servico.from('usuarios').select('perfil, ativo').eq('id', quem.user.id).maybeSingle();
  if (!chamador || chamador.perfil !== 'admin' || !chamador.ativo) return erro(403, 'Somente Gente e Gestão gerencia acessos');

  let c: Record<string, unknown>;
  try { c = await req.json(); } catch { return erro(400, 'Pedido inválido'); }
  const destino = String(c.destino ?? '');
  if (!DESTINOS.includes(destino)) return erro(400, 'Endereço de retorno não autorizado');
  const redirectTo = `${destino}nova-senha`;

  if (c.acao === 'criar') {
    const nome = String(c.nome ?? '').trim();
    const email = String(c.email ?? '').trim().toLowerCase();
    const perfil = String(c.perfil ?? '');
    const departamentos = Array.isArray(c.departamentos) ? c.departamentos.map(String) : [];
    if (nome.length < 2) return erro(400, 'Informe o nome');
    if (!EMAIL.test(email)) return erro(400, 'E-mail inválido');
    if (!PERFIS.includes(perfil)) return erro(400, 'Perfil inválido');
    if (perfil === 'gestor' && !departamentos.length) return erro(400, 'Escolha ao menos um departamento');
    const { data: criado, error } = await servico.auth.admin.createUser({ email, email_confirm: true });
    if (error || !criado.user) return erro(400, /already/i.test(error?.message ?? '') ? 'Este e-mail já tem acesso' : 'Não foi possível criar o acesso');
    const { error: e2 } = await servico.from('usuarios').insert({ id: criado.user.id, nome, email, perfil, colaborador_id: c.colaborador_id || null });
    if (e2) { await servico.auth.admin.deleteUser(criado.user.id); return erro(400, 'Não foi possível criar o acesso'); }
    if (perfil === 'gestor') await servico.from('usuarios_departamentos').insert(departamentos.map((d) => ({ usuario_id: criado.user.id, departamento_id: d })));
    const { data: link } = await servico.auth.admin.generateLink({ type: 'recovery', email, options: { redirectTo } });
    return responder(200, { link: link?.properties?.action_link ?? null });
  }
  if (c.acao === 'link') {
    const { data: u } = await servico.from('usuarios').select('email').eq('id', String(c.usuario_id ?? '')).maybeSingle();
    if (!u) return erro(404, 'Acesso não encontrado');
    const { data: link, error } = await servico.auth.admin.generateLink({ type: 'recovery', email: u.email, options: { redirectTo } });
    if (error) return erro(400, 'Não foi possível gerar o link');
    return responder(200, { link: link.properties.action_link });
  }
  if (c.acao === 'ativar') {
    const id = String(c.usuario_id ?? '');
    if (id === quem.user.id) return erro(400, 'Você não pode desativar o próprio acesso');
    const { error } = await servico.from('usuarios').update({ ativo: !!c.ativo }).eq('id', id);
    if (error) return erro(400, 'Não foi possível alterar o acesso');
    return responder(200, { ok: true });
  }
  return erro(400, 'Ação desconhecida');
});
