#!/usr/bin/env bash
# Gera docs/ (versão publicada, minificada) a partir dos arquivos-fonte.
# Rodar sempre antes de publicar:  bash build.sh
set -e
cd "$(dirname "$0")"

rm -rf docs
mkdir -p docs/assets docs/admin
cp assets/* docs/assets/

for page in index.html admin/index.html; do
  npx --yes html-minifier-terser "$page" \
    --collapse-whitespace --remove-comments --minify-css true --minify-js true \
    -o "docs/$page"
  echo "docs/$page gerado a partir de $page."
done

# Domínio próprio: crie um arquivo CNAME na raiz com o domínio e ele vai junto.
[ -f CNAME ] && cp CNAME docs/CNAME && echo "docs/CNAME copiado."
echo "Pronto. Publique a pasta docs/."
