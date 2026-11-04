import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { supabase, mensagemDeErro } from '../lib/supabase';
import { Moldura } from '../componentes/Moldura';

export function Entrar() {
  const [email, setEmail] = useState('');
  const [senha, setSenha] = useState('');
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function entrar(e: FormEvent) {
    e.preventDefault();
    setErro(null);
    setEnviando(true);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha });
    setEnviando(false);
    if (error) setErro(mensagemDeErro(error));
  }

  return (
    <Moldura>
      <form className="formulario" onSubmit={entrar} noValidate>
        <h2>Entrar</h2>
        <p className="apoio">Use o seu e-mail da Emais.</p>

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

        <label className="campo">
          <span>Senha</span>
          <input
            type="password"
            autoComplete="current-password"
            required
            value={senha}
            onChange={(e) => setSenha(e.target.value)}
          />
        </label>

        {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}

        <button className="botao" type="submit" disabled={enviando || !email || !senha}>
          {enviando ? 'Entrando' : 'Entrar'}
        </button>

        <Link className="link" to="/esqueci-senha">Esqueci minha senha</Link>
      </form>
    </Moldura>
  );
}
