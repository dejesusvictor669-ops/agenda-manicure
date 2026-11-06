const SUPABASE_URL = "https://karhmekwvyrkfwmaagvc.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImthcmhtZWt3dnlya2Z3bWFhZ3ZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5NjEwMzcsImV4cCI6MjEwOTUzNzAzN30.0PY1lSk692hQ2q1unAKFs-O3QY1hN76Dy34SE1WSBwQ"; // chave anon (pública). NUNCA use service_role aqui.
const WHATSAPP = "SEU_NUMERO_COM_DDI_E_DDD";
const NOME_ESTUDIO = "Studio de Unhas"; // nome que aparece no topo do site e do painel
const LOGO = "favicon.svg"; // troque por "logo.png" depois de colocar a imagem da logo nesta pasta
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Preenche nome e logo em todas as páginas
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".brand-name").forEach(e => e.textContent = NOME_ESTUDIO);
  document.querySelectorAll(".logo").forEach(e => { e.src = LOGO; e.alt = "Logo " + NOME_ESTUDIO; });
});
const brl = c => (c/100).toLocaleString("pt-BR",{style:"currency",currency:"BRL"});
const fmtDay = d => d.split("-").reverse().join("/");
const $ = s => document.querySelector(s);
