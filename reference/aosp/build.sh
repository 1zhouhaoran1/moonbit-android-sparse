#!/usr/bin/env bash
# Build untouched, pinned AOSP libsparse; no package installation is performed.
# Debian/Ubuntu prerequisites: g++ curl zlib1g-dev android-libbase-dev.
# Run: bash reference/aosp/build.sh [cache-directory]
set -euo pipefail
revision=f7b2fc8117d44a26866f87392acbc5ad5c54d7a7
cache=${1:-${SPARSE_REFERENCE_CACHE:-${TMPDIR:-/tmp}/android-sparse-reference}}
compiler=${CXX:-g++}
command -v "$compiler" >/dev/null || { echo "Missing C++ compiler: $compiler" >&2; exit 2; }
command -v curl >/dev/null || { echo 'Missing curl' >&2; exit 2; }
command -v sha256sum >/dev/null || { echo 'Missing sha256sum' >&2; exit 2; }
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
mkdir -p "$cache/source/include/sparse"
cache=$(cd -- "$cache" && pwd)
triplet=$("$compiler" -dumpmachine)
# Override these flags if the distribution installs libbase elsewhere.
read -r -a base_cxx <<< "${AOSP_BASE_CXXFLAGS:--I/usr/include/android}"
read -r -a base_ld <<< "${AOSP_BASE_LDFLAGS:--L/usr/lib/$triplet/android -Wl,-rpath,/usr/lib/$triplet/android -lbase}"
printf '%s\n' '#include <android-base/stringprintf.h>' '#include <android-base/mapped_file.h>' '#include <zlib.h>' 'int main() { return android::base::StringPrintf("%d", zlibVersion()[0]).empty(); }' > "$cache/dependency-check.cpp"
if ! "$compiler" -std=c++17 "${base_cxx[@]}" "$cache/dependency-check.cpp" "${base_ld[@]}" -lz -o "$cache/dependency-check"; then
  echo 'Missing/incompatible C++ headers, zlib development files, or android-libbase-dev; no packages were installed.' >&2
  exit 2
fi
files=(backed_block.cpp backed_block.h output_file.cpp output_file.h sparse.cpp sparse_crc32.cpp sparse_crc32.h sparse_defs.h sparse_err.cpp sparse_file.h sparse_format.h sparse_read.cpp defs.h include/sparse/sparse.h)
for file in "${files[@]}"; do
  curl --fail --location --retry 2 --connect-timeout 15 --max-time 60 \
    "https://raw.githubusercontent.com/aosp-mirror/platform_system_core/$revision/libsparse/$file" \
    --output "$cache/source/$file.part"
  mv -- "$cache/source/$file.part" "$cache/source/$file"
done
(cd "$cache/source" && sha256sum "${files[@]}") > "$cache/source-sha256.txt"
sources=(backed_block.cpp output_file.cpp sparse.cpp sparse_crc32.cpp sparse_err.cpp sparse_read.cpp)
inputs=()
for file in "${sources[@]}"; do inputs+=("$cache/source/$file"); done
"$compiler" -std=c++17 -O2 -D_GNU_SOURCE -I"$cache/source/include" -I"$cache/source" \
  "${base_cxx[@]}" "${inputs[@]}" "$root/reference/aosp/harness.cpp" \
  "${base_ld[@]}" -lz -o "$cache/oracle"
printf '%s\n' "$revision" > "$cache/revision.txt"
"$compiler" --version > "$cache/compiler-version.txt"
sha256sum "$cache/oracle" > "$cache/binary-sha256.txt"
echo "Built pinned CRC-verifying oracle: $cache/oracle"
echo "Run: node reference/aosp/compare.mjs '$cache'"
