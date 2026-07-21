# Como configurar para um novo cliente

Copie a pasta inteira com um nome novo (ex.: `indique-cliente-x/`) e siga os passos abaixo.
Tempo típico: 30–40 minutos, sendo a maior parte esperando o Supabase provisionar.

Tudo que muda está no bloco `window.CONFIG`, no topo do `index.html`. **Nada abaixo do
comentário "MOTOR" precisa ser tocado** — é o mesmo código para qualquer cliente.

---

## 1. Criar o banco (Supabase)

1. Em [supabase.com](https://supabase.com), criar um projeto novo **na conta do cliente**
   (o plano gratuito atende de sobra: uma campanha inteira cabe em poucos MB).
2. Abrir **SQL Editor** → colar o conteúdo de `supabase/schema.sql` → **Run**.
   O script é idempotente: pode rodar de novo sem quebrar nada.
3. Em **Settings → API**, copiar:
   - **Project URL** → vai em `SUPABASE_URL`
   - chave **anon / public** → vai em `SUPABASE_ANON_KEY`

Cole esses dois valores no `index.html` **e** no `admin/index.html` (os mesmos valores nos
dois arquivos).

> A chave `anon` é pública por natureza — pode ficar no código-fonte. A **service_role**
> nunca: ela só aparece no webhook, que roda no servidor.

## 2. Criar o acesso ao painel admin

Em **Authentication → Users → Add user**, criar o e-mail e senha do dono da campanha
(marcar "Auto confirm user"). Depois liste esse e-mail em `ALLOWED_EMAILS`, no topo do
`admin/index.html`:

```js
ALLOWED_EMAILS: ['dono@clientex.com.br'],
```

Lista vazia = qualquer usuário autenticado do projeto entra. Prefira sempre listar.

## 3. Publicar o webhook de venda

Sem esta etapa a página funciona, mas **ninguém pontua** — é o webhook que transforma venda
aprovada em ponto.

### Opção A — Edge Function (recomendada, não precisa de servidor)

```bash
supabase login
supabase link --project-ref <ref-do-projeto>
supabase functions deploy webhook-hotmart --no-verify-jwt
supabase secrets set HOTMART_HOTTOK=<hottok> CAMPAIGN_ID=<mesmo-do-CONFIG>
```

O `--no-verify-jwt` é obrigatório: quem chama é a plataforma de pagamento, não um usuário
logado. A autenticação é feita pelo hottok.

Na Hotmart (**Ferramentas → Webhook**), cadastrar:

- URL: `https://<ref-do-projeto>.supabase.co/functions/v1/webhook-hotmart`
- Eventos: **Compra aprovada** e **Compra completa**

### Opção B — PHP (se o cliente já tem hospedagem)

Preencher as três constantes no topo de `api/webhook-hotmart.php`, subir para a hospedagem
e apontar o webhook da Hotmart para a URL do arquivo. A `SUPABASE_SERVICE_KEY` dá acesso
total ao banco — esse arquivo não pode ir para repositório público.

### Outra plataforma que não seja Hotmart

O webhook lê o parâmetro de rastreamento `sck`. Kiwify, Eduzz e Ticto mandam o equivalente
com outro nome e outro formato de corpo — adapte o trecho que monta a variável `sck` e a
lista de eventos aprovados. O resto (achar o indicador, checar duplicidade, inserir o lead)
é igual.

## 4. Preencher o CONFIG

No topo do `index.html`:

| Campo | O que é |
|---|---|
| `CAMPAIGN_ID` | Identificador da campanha. Um mesmo Supabase aguenta várias — troque este valor e publique outra cópia da página. |
| `SALES_PAGE` | Página de vendas para onde o link de indicação leva o colega. |
| `CHECKOUT_BASE` | Link de checkout. O código do indicador entra como `&sck=CODIGO` — é assim que a venda é atribuída. |
| `WHATSAPP_MSG` | Mensagem pronta do botão de compartilhar. `{{link}}` e `{{nome}}` são substituídos. |
| `BRAND` | Nome (dividido em duas partes: preta e dourada), favicon e as 3 cores da marca. |
| `TITLE` / `TOPBAR` | Título da aba e faixa preta do topo. |
| `HERO` | Chapéu, headline (`<em>` sai em dourado), subtítulo e os selos. |
| `INVITE` | Faixa que só aparece para quem chega por um link de indicação. `enabled: false` desliga. |
| `RULES` | Os passos numerados do "Como funciona". |
| `PRIZES` | Cards de premiação — `tier` aceita `all`, `gold`, `silver`, `bronze` (muda a cor da borda). |
| `URGENCY` | Bloco de prazo. `null` remove a seção inteira. |
| `FOOTER` | Linhas do rodapé. |

**Cores:** só as três de `BRAND.colors` precisam mudar. Todo o CSS deriva delas — botões,
selos, medalhas e destaques se atualizam sozinhos.

**Regra de ouro da premiação:** deixe explícito que ponto é *venda*, não compartilhamento.
É a dúvida número 1 dos participantes e evita reclamação no fim da campanha.

## 5. Testar antes de entregar

```bash
python -m http.server 8000
```

Confira, nesta ordem:

- [ ] Textos, cores e favicon batem com a marca do cliente.
- [ ] Preencher o formulário gera um código e abre o modal com o link.
- [ ] "Ver meu painel" abre o painel; sair e clicar em **Entrar** com o mesmo e-mail
      recupera o cadastro.
- [ ] Copiar o link e abrir numa aba anônima: a faixa de convite aparece com o nome de
      quem indicou, e o botão leva ao checkout com o `sck` certo.
- [ ] No `/admin`, o login funciona e o inscrito de teste aparece em **Inscritos**.
- [ ] **Teste de venda:** dispare o webhook de teste da Hotmart (ou faça uma compra de
      R$ 1). O ponto tem que aparecer no painel do indicador e em **Compras** no admin.
      Se não aparecer, veja os logs em Supabase → Edge Functions → Logs: o motivo quase
      sempre é o `sck` chegando em um campo diferente do esperado.
- [ ] Console do navegador sem erros.

Ao final, apague os registros de teste (Supabase → Table Editor → `referrers` /
`referral_leads`) para a campanha começar zerada.

## 6. Publicar

```bash
bash build.sh
```

Gera `docs/` minificado. Publique essa pasta.

**GitHub Pages:**

```bash
git init && git add . && git commit -m "Indique e Ganhe — cliente X"
gh repo create indique-cliente-x --private --source=. --push
```

Em **Settings → Pages**, servir a branch `main` pela pasta `/docs`. Para domínio próprio,
criar um arquivo `CNAME` na raiz com o domínio — o `build.sh` copia junto.

**FTP:** subir o conteúdo de `docs/` para a pasta desejada. O `/admin` precisa ir junto,
como subpasta.

---

## Rodar mais de uma campanha no mesmo Supabase

Basta trocar `CAMPAIGN_ID` e publicar outra cópia da pasta. As tabelas são compartilhadas e
todas as consultas filtram por campanha — ranking, KPIs e admin ficam isolados. Só o campo
`codigo` é único globalmente, então o mesmo participante recebe códigos diferentes em
campanhas diferentes.

## Perguntas que o cliente sempre faz

**"Dá para contar ponto por inscrição em lista, não só por venda?"**
Dá — nesse caso o webhook passa a ser o da ferramenta de e-mail (ActiveCampaign, RD) em vez
do da plataforma de pagamento. A lógica de gravar em `referral_leads` é a mesma.

**"E se a pessoa perder o link?"**
Clica em **Entrar** e informa o e-mail do cadastro — o painel volta com o mesmo código.

**"E se alguém comprar sem passar pelo link?"**
O webhook ignora a venda (sem `sck`, sem ponto) e responde 200, para a plataforma não ficar
reenviando.

**"Dá para premiar mais gente do que os tops?"**
Sim — é só editar os cards em `PRIZES`. O ranking mostra os 50 primeiros; para mudar esse
limite, ajuste o `limit 50` na função `ig_ranking` do `schema.sql`.
