# Agenda Manicure

Agendamento online para manicure: a cliente escolhe serviço, dia e horário, e a confirmação é feita pelo WhatsApp. A profissional gerencia agenda, horários e serviços em um painel protegido por login.

## Páginas

| Página | Para quem | O que faz |
|---|---|---|
| `index.html` | Clientes | Escolher serviço, dia e horário livre; reservar e abrir o WhatsApp |
| `admin.html` | Profissional | Confirmar, remarcar e cancelar agendamentos; editar horários, folgas e serviços |

## Tecnologias

- HTML, CSS e JavaScript puros, sem etapa de build
- [Supabase](https://supabase.com) para banco de dados e login, com RLS (as clientes nunca leem dados de outras clientes)
- [Vercel](https://vercel.com) para hospedagem, com cabeçalhos de segurança em `vercel.json`

## Configuração

1. Crie um projeto no Supabase e rode `schema.sql` e depois `lembretes.sql` no SQL Editor.
2. Crie o usuário da profissional em **Authentication › Users** e torne-o administrador:
   ```sql
   insert into admins(user_id) select id from auth.users where email='EMAIL_DELA';
   ```
3. Em `config.js`, preencha:
   - `SUPABASE_URL` e `SUPABASE_ANON_KEY` (chave **anon**, nunca a `service_role`)
   - `WHATSAPP`: número com DDI e DDD, só dígitos (ex.: `5511987654321`)
   - `NOME_ESTUDIO`: nome exibido no topo das páginas
   - `LOGO` e `INSTAGRAM`: ícone redondo da marca e link do perfil (as imagens ficam em `img/`)
4. Publique a pasta na Vercel.

## Rodar localmente

Qualquer servidor estático serve, por exemplo:

```bash
npx serve .
```

## Privacidade (LGPD)

A cliente consente antes de agendar. A função `anonimizar_antigos()` apaga nome e telefone de atendimentos encerrados há mais de 6 meses. Rode-a mensalmente ou agende com `pg_cron`.
