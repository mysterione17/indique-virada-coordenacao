# Indique & Ganhe

Programa de indicação ("member get member") para funil de vendas: o cliente gera um link
pessoal, compartilha, e cada venda que vier por aquele link vira 1 ponto no ranking.
Quem mais indica, ganha os prêmios que você definir.

Adaptado da página de indicação NR-10 da Elétrica Academy
(`tools.eletricaacademy/deploy/wp-content/themes/academy-tools-child/page-indicacao-nr10.php`)
como template reutilizável — desacoplado do WordPress e com todo o conteúdo em um único
bloco de configuração.

## O que o cliente recebe

| Peça | O que faz |
|---|---|
| `index.html` | Landing do programa + painel do indicador (link, código, pontos, posição, conversões, ranking). Arquivo único, sem build, sem framework. |
| `admin/index.html` | Painel de gestão: KPIs ao vivo, ranking, inscritos, compras, busca e exportação para Excel. Protegido por login. |
| `supabase/schema.sql` | Banco completo: tabelas, índices, trigger de pontuação e as regras de segurança. |
| `supabase/functions/webhook-hotmart/` | Webhook de venda como Edge Function — é ele que transforma venda aprovada em ponto. |
| `api/webhook-hotmart.php` | Mesmo webhook em PHP, para quem prefere usar a hospedagem que já tem. |

## Como funciona

```
  visitante                                    dono da campanha
      │                                              │
      ├─ preenche nome/e-mail/WhatsApp               │
      │  → ganha um código único (ex.: LucasMPWQK)   │
      │                                              │
      ├─ compartilha o link                          │
      │  ...?sck=LucasMPWQK&utm_source=LucasMPWQK    │
      │                                              │
   colega clica → registra clique → página de vendas │
      │                                              │
   colega compra → plataforma chama o WEBHOOK        │
      │            → grava referral_leads            │
      │            → trigger soma +1 ponto           │
      │                                              │
      └─ vê pontos e posição no painel        vê tudo em /admin
```

O ponto só entra com **venda aprovada** — compartilhar link não pontua. É o webhook, e não
a página, que credita, então não dá para inflar o ranking pelo navegador.

## Segurança dos dados

A página é estática, então a chave pública do Supabase fica visível no código-fonte. Por
isso as tabelas ficam **fechadas**: o site só chama funções (`ig_*`) que devolvem
exclusivamente o que pode ser público — nome, código e pontos. E-mail e WhatsApp dos
inscritos nunca saem numa listagem. O `/admin` lê as tabelas com um usuário autenticado
de verdade.

Isso importa na hora de vender: você não está entregando ao cliente uma página que vaza
a base de leads dele.

## Estrutura

```
indique-e-ganhe-base/
├── index.html                 # FONTE — landing + painel do indicador (é este que se edita)
├── admin/index.html           # FONTE — painel administrativo
├── assets/favicon.svg         # placeholder — trocar pelo do cliente
├── supabase/
│   ├── schema.sql             # rodar uma vez no SQL Editor do Supabase
│   └── functions/webhook-hotmart/index.ts
├── api/webhook-hotmart.php    # alternativa ao Edge Function
├── build.sh                   # gera docs/ (versão minificada para publicar)
├── README.md                  # este arquivo
└── REPLICAR.md                # passo a passo para configurar um novo cliente
```

## Modo demo

Enquanto `SUPABASE_URL`/`SUPABASE_ANON_KEY` estiverem com os valores `SUA_...`, a página
roda com dados falsos e não grava nada: o formulário gera um código, o painel abre, o
ranking aparece preenchido. Serve para demonstrar o produto antes de a venda fechar.

## Testar localmente

```bash
python -m http.server 8000
```

E abrir `http://localhost:8000`. Para ver a faixa de convite, abrir com `?ref=QualquerCodigo`.

## Publicar

```bash
bash build.sh        # gera docs/ minificado
```

Publicar a pasta `docs/` — GitHub Pages, FTP, Vercel, qualquer hospedagem estática. Não há
dependência de servidor: o único componente que roda no back-end é o webhook, e ele vive
dentro do próprio Supabase.

O passo a passo completo de configuração está em **[REPLICAR.md](REPLICAR.md)**.
