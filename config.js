const SUPABASE_URL = "https://karhmekwvyrkfwmaagvc.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImthcmhtZWt3dnlya2Z3bWFhZ3ZjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5NjEwMzcsImV4cCI6MjEwOTUzNzAzN30.0PY1lSk692hQ2q1unAKFs-O3QY1hN76Dy34SE1WSBwQ"; // chave anon (pública). NUNCA use service_role aqui.
const WHATSAPP = "5531994205120"; // 55 + DDD + número, só dígitos
const NOME_ESTUDIO = "Glauciane Rosa"; // nome que aparece no rodapé e no painel
const LOGO = "img/icone.png";        // ícone redondo (monograma GR)
const INSTAGRAM = "https://www.instagram.com/glaucianerosa_nails";
const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Preenche nome, logo e Instagram em todas as páginas
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".brand-name").forEach(e => e.textContent = NOME_ESTUDIO);
  document.querySelectorAll(".logo").forEach(e => { e.src = LOGO; e.alt = "Logo " + NOME_ESTUDIO; });
  const insta = document.getElementById("insta");
  if (insta) insta.href = INSTAGRAM;
});
const brl = c => (c/100).toLocaleString("pt-BR",{style:"currency",currency:"BRL"});
const fmtDay = d => d.split("-").reverse().join("/");
const $ = s => document.querySelector(s);
