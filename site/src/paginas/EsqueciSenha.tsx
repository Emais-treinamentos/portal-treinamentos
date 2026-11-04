import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { supabase, mensagemDeErro, enderecoDoSite } from '../lib/supabase';
import { Moldura } from '../componentes/Moldura';

export function EsqueciSenha() {
  const [email, setEmail] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [enviado, setEnviado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function enviar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setEnviando(true);
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${enderecoDoSite}nova-senha`,
    });
    setEnviando(false);
    if (error) setErro(mensagemDeErro(error));
    else setEnviado(true);
  }

  return (
    <Moldura>
      {enviado ? (
        <div className="formulario">
          <h2>Confira seu e-mail</h2>
          <p className="apoio">
            Se <strong>{email.trim()}</strong> tiver acesso ao portal, chega em alguns minutos um link para criar a nova
            senha. Abra o link no mesmo aparelho. Se não aparecer, olhe a caixa de spam.
          </p>
          <Link className="link" to="/entrar">Voltar para a entrada</Link>
        </div>
      ) : (
        <form className="formulario" onSubmit={enviar} noValidate>
          <h2>Criar nova senha</h2>
          <p className="apoio">Informe o e-mail de acesso. Vamos mandar um link para você criar a senha.</p>

          <label className="campo">
            <span>E-mail</span>
            <input
              type="email"
              autoComplete="email"
              inputMode="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>

          {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}

          <button className="botao" type="submit" disabled={enviando || !email}>
            {enviando ? 'Enviando' : 'Enviar link'}
          </button>

          <Link className="link" to="/entrar">Voltar para a entrada</Link>
        </form>
      )}
    </Moldura>
  );
}
