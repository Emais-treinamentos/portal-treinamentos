import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import { ProvedorSessao } from './lib/sessao';
import { App } from './App';
import './estilos.css';

createRoot(document.getElementById('raiz')!).render(
  <StrictMode>
    <BrowserRouter basename={import.meta.env.BASE_URL}>
      <ProvedorSessao>
        <App />
      </ProvedorSessao>
    </BrowserRouter>
  </StrictMode>,
);
