import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { supabase, mensagemDeErro } from '../lib/supabase';
import { useSessao } from '../lib/sessao';
import { Moldura } from '../componentes/Moldura';
import { Carregando } from '../componentes/Carregando';

const TAMANHO_MINIMO = 8;

export function NovaSenha() {
  const { situacao, sessao, concluirRecuperacao } = useSessao();
  const navegar = useNavigate();
  const [senha, setSenha] = useState('');
  const [confirmacao, setConfirmacao] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  if (situacao === 'carregando' && !sessao) return <Carregando />;

  if (!sessao) {
    return (
      <Moldura>
        <div className="formulario">
          <h2>Link vencido</h2>
          <p className="apoio">
            O link para criar a senha já foi usado ou passou do prazo. Peça um novo e abra no mesmo aparelho.
          </p>
          <Link className="botao" to="/esqueci-senha">Pedir novo link</Link>
        </div>
      </Moldura>
    );
  }

  const curta = senha.length > 0 && senha.length < TAMANHO_MINIMO;
  const diferente = confirmacao.length > 0 && confirmacao !== senha;

  async function salvar(e: FormEvent) {
    e.preventDefault();
    if (senha.length < TAMANHO_MINIMO || senha !== confirmacao) return;
    setErro(null);
    setSalvando(true);
    const { error } = await supabase.auth.updateUser({ password: senha });
    setSalvando(false);
    if (error) {
      setErro(mensagemDeErro(error));
      return;
    }
    concluirRecuperacao();
    navegar('/', { replace: true });
  }

  return (
    <Moldura>
      <form className="formulario" onSubmit={salvar} noValidate>
        <h2>Crie sua senha</h2>
        <p className="apoio">Acesso de {sessao.user.email}. Use pelo menos {TAMANHO_MINIMO} caracteres.</p>

        <label className="campo">
          <span>Nova senha</span>
          <input
            type="password"
            autoComplete="new-password"
            value={senha}
            aria-invalid={curta}
            onChange={(e) => setSenha(e.target.value)}
          />
          {curta && <small className="campo-erro">Faltam {TAMANHO_MINIMO - senha.length} caracteres.</small>}
        </label>

        <label className="campo">
          <span>Repita a senha</span>
          <input
            type="password"
            autoComplete="new-password"
            value={confirmacao}
            aria-invalid={diferente}
            onChange={(e) => setConfirmacao(e.target.value)}
          />
          {diferente && <small className="campo-erro">As duas senhas não estão iguais.</small>}
        </label>

        {erro && <p className="aviso aviso-erro" role="alert">{erro}</p>}

        <button
          className="botao"
          type="submit"
          disabled={salvando || senha.length < TAMANHO_MINIMO || senha !== confirmacao}
        >
          {salvando ? 'Salvando' : 'Salvar senha'}
        </button>
      </form>
    </Moldura>
  );
}
