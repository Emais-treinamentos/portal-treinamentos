import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { supabase, mensagemDeErro } from '../lib/supabase';
import { useSessao } from '../lib/sessao';
import { Moldura } from '../componentes/Moldura';

// Primeiro acesso e troca de senha: código enviado ao e-mail cadastrado, depois a pessoa cria a senha.
export function EsqueciSenha() {
  const { marcarRecuperacao } = useSessao();
  const [email, setEmail] = useState('');
  const [codigo, setCodigo] = useState('');
  const [etapa, setEtapa] = useState<'email' | 'codigo'>('email');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<string | null>(null);
  const emailLimpo = email.trim().toLowerCase();

  async function pedirCodigo(e?: FormEvent) {
    e?.preventDefault();
    setErro(null); setAviso(null); setEnviando(true);
    // O código é gerado no Supabase e enviado pelo n8n. E-mail sem acesso recebe a mesma resposta.
    const { error } = await supabase.functions.invoke('enviar-codigo', { body: { email: emailLimpo } });
    setEnviando(false);
    if (error) {
      const r = (error as { context?: Response }).context;
      const j = r ? await r.json().catch(() => null) : null;
      setErro(j?.erro ?? 'Não foi possível enviar o código agora. Tente de novo em instantes.');
      return;
    }
    setEtapa('codigo');
    if (e === undefined) setAviso('Enviamos um novo código. Use o mais recente.');
  }

  async function confirmar(e: FormEvent) {
    e.preventDefault();
    setErro(null); setAviso(null); setEnviando(true);
    const { error } = await supabase.auth.verifyOtp({ email: emailLimpo, token: codigo.trim(), type: 'email' });
    setEnviando(false);
    if (!error) { marcarRecuperacao(true); return; }
    {
      setErro(/expired|invalid/i.test(error.message) ? 'Código inválido ou vencido. Confira os números ou peça um novo código.' : mensagemDeErro(error));
    }
  }

  return (
    <Moldura>
      {etapa === 'email' ? (
        <form className="formulario" onSubmit={pedirCodigo} noValidate>
          <h1>Primeiro acesso ou nova senha</h1>
          <p className="apoio">Informe o e-mail cadastrado pela Gente e Gestão. Vamos mandar um código para você criar a sua senha.</p>
          <label className="campo">
            <span>E-mail</span>
            <input type="email" autoComplete="email" inputMode="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
          </label>
          {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
          <button className="botao" type="submit" disabled={enviando || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(emailLimpo)}>{enviando ? 'Enviando' : 'Receber código'}</button>
          <Link className="link" to="/entrar">Voltar para a entrada</Link>
        </form>
      ) : (
        <form className="formulario" onSubmit={confirmar} noValidate>
          <h1>Digite o código</h1>
          <p className="apoio">Se <strong>{emailLimpo}</strong> tiver acesso ao portal, chega em instantes um e-mail com o código. Se não aparecer, olhe a caixa de spam.</p>
          <label className="campo">
            <span>Código</span>
            <input className="campo-codigo" inputMode="numeric" autoComplete="one-time-code" maxLength={10} required value={codigo} onChange={(e) => setCodigo(e.target.value.replace(/\D/g, ''))} />
          </label>
          {aviso && <p className="aviso aviso-ok" role="status">{aviso}</p>}
          {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}
          <button className="botao" type="submit" disabled={enviando || codigo.length < 6}>{enviando ? 'Conferindo' : 'Continuar'}</button>
          <button className="link botao-link" type="button" disabled={enviando} onClick={() => void pedirCodigo()}>Enviar outro código</button>
          <button className="link botao-link" type="button" onClick={() => { setEtapa('email'); setCodigo(''); setErro(null); setAviso(null); }}>Usar outro e-mail</button>
        </form>
      )}
    </Moldura>
  );
}
