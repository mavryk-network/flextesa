#! /bin/sh

set -e

dest_dir="$1"
if ! [ -d "$dest_dir" ] ; then
    echo "usage: $0 <destination-path>" >&2
    echo "       <destination-path> should be an existing directory." >&2
    exit 3
fi

# - Go to https://gitlab.com/tezos/tezos/
# - Find a successful master-branch pipeline.
# - Get the 2 jobs making x86_64 and arm64 static binaries.
# - Download the artifacts and put them in a more durable place.
# - Put those durable URLs down there, as `download_uri`:
#
# This time: https://gitlab.com/tezos/tezos/-/pipelines/587803531
# (from 2022-07-14)
# 
directory_name=
case $(uname -m) in
    x86_64 ) 
        download_uri="https://www.dropbox.com/s/e1wpv0ns0uoybzq/octez-static-x86_64-20220714-16139989.zip?raw=1"
        directory_name=x86_64 ;;
    aarch64 )
        download_uri="https://www.dropbox.com/s/22r5zxvrdk1m669/octez-static-arm64-20220714-16139989.zip?raw=1"
        directory_name=arm64 ;;
    * ) echo "Unknown architecture: $(uname -a)" >&2 ; exit 4 ;;
esac

(
    curl -L "$download_uri" -o "$dest_dir/bins.zip"
    cd "$dest_dir"
    unzip bins.zip
    mv tezos-binaries/$directory_name/* .
    rm -fr bins.zip tezos-binaries/
    chmod a+rx tezos-*
)
