# install dependencies for C++ analysis
set -e

# The following error occurs without arch -arm64 on macOS-14 runner:
# Error: Cannot install under Rosetta 2 in ARM default prefix (/opt/homebrew)!
# To rerun under ARM use:
#     arch -arm64 brew install ...

# detect if this is arm64
#echo "uname -m: $(uname -m)"
#echo "arch: $(arch)"
#echo "uname -p: $(uname -p)"
#echo "uname -a: $(uname -a)"
#if [[ "$(uname -m)" == "arm64" ]]; then
#  brew_cmd="arch -arm64 brew"
#else
#  brew_cmd="brew"
#fi

# install dependencies
arch -arm64 brew install \
  boost \
  cmake \
  miniupnpc \
  node \
  opus \
  pkg-config

# build
mkdir -p build
cd build || exit 1
cmake -G "Unix Makefiles" ..
make -j"$(sysctl -n hw.logicalcpu)"

# skip autobuild
echo "skip_autobuild=true" >> "$GITHUB_OUTPUT"
