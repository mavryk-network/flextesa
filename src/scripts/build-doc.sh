#! /bin/sh

set -e

usage () {
    cat >&2 <<EOF
usage: $0 <output-path>

EOF
}

shout () {
    YELLOW='\033[0;33m'
    NC='\033[0m'
    if [ "no_color" = "true" ]; then
        printf "$@"
    else
        printf "$YELLOW"; printf "$@" ; printf "$NC"
    fi
}

say () {
    shout "[Make-doc] " >&2
    printf "$@" >&2
    printf "\n" >&2
}

if ! [ -f src/scripts/build-doc.sh ] ; then
    say "This script should run from the root of the flextesa tree."
    exit 1
fi

output_path="$1"

mkdir -p "$output_path/api"

opam config exec -- dune build @doc

opam config exec -- opam install --yes odig omd

cp -r _build/default/_doc/_html/* "$output_path/"

cp -r $(odig odoc-theme path odig.solarized.dark)/* "$output_path/"

lib_index_fragment=$(mktemp "/tmp/lib-index-XXXX.html")
odoc html-frag src/doc/index.mld \
     -I _build/default/src/lib/.flextesa.objs/byte/ -o "$lib_index_fragment"
lib_index="$output_path/lib-index.html"

main_index_fragment=$(mktemp "/tmp/main-index-XXXX.html")
toc_spot=$(awk '/^<!--TOC-->/ { print NR + 1; exit 0; }' README.md)
say "README TOC is at line $toc_spot"
head -n "$toc_spot" ./README.md  | omd > "$main_index_fragment"
{ echo '# Table of Contents' ; tail +$toc_spot  ./README.md ; } \
    | omd -otoc >> "$main_index_fragment"
tail +$toc_spot  ./README.md \
    | sed 's@https://tezos.gitlab.io/flextesa/lib-index.html@./lib-index.html@' \
    | omd >> "$main_index_fragment"
main_index="$output_path/index.html"

make_page () {
    input="$1"
    output="$2"
    title="$3"
cat > "$output" <<EOF
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>$title</title>
    <link rel="stylesheet" href="./odoc.css"/>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width,initial-scale=1.0"/>
  </head>
  <body>
    <main class="content">
EOF
cat "$input" >> "$output"
cat >> "$output" <<'EOF'
    </main>
  </body>
</html>
EOF
}

make_page "$lib_index_fragment" "$lib_index" "Flextesa: API"
make_page "$main_index_fragment" "$main_index" "Flextesa: Home"


say "done: file://$PWD/$main_index"
say "done: file://$PWD/$lib_index"
say "done: file://$PWD/$output_path/flextesa/Flextesa/index.html"


