# This file is part of SQbricks.
#
# Copyright (C) 2022-2026
# CEA (Commissariat à l'énergie atomique et aux énergies alternatives)
# Université Paris-Saclay
#
# you can redistribute it and/or modify it under the terms of the GNU
# Lesser General Public License as published by the Free Software
# Foundation, version 2.1.
#
# It is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# See the GNU Lesser General Public License version 2.1
# for more details (enclosed in the file licenses/LGPLv2.1).

FROM ocaml/opam:ubuntu-26.04-ocaml-5.5

RUN sudo apt-get update && sudo apt-get install -y \
  git \
  python3 \
  python3-pip \
  python3-tk \
  python3-venv \
  libgmp-dev pkg-config \
  bash-completion \
  texlive-latex-base \
  texlive-latex-recommended \
  texlive-fonts-recommended \
  texlive-pictures \
  texlive-science \
  && sudo apt-get clean 

RUN git clone https://github.com/Z3Prover/z3.git && \
  cd z3 && \
  git checkout z3-4.16.0 && \
  python3 scripts/mk_make.py

RUN cd z3/build && \
  sudo make -j$(nproc) && \
  sudo make install && \
  sudo ldconfig && \
  cd ../.. && rm -rf z3
RUN sudo apt-get update && sudo apt-get install -y libboost-regex-dev

RUN opam init --disable-sandboxing -y && \
  opam update && \
  opam install -y \
  "dune>=3.17" \
  zarith \
  landmarks \
  benchmark \
  lwt \
  batteries \
  logs \
  menhir \
  landmarks-ppx \
  alcotest \
  odoc

RUN opam env >> ~/.bashrc
ENV PATH="/home/opam/sqbricks-python/bin:/home/opam/.opam/default/bin:$PATH"

COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /home/opam/sqbricks-python && \
  /home/opam/sqbricks-python/bin/pip install --no-cache-dir -r /tmp/requirements.txt

WORKDIR /sqbricks
COPY . /sqbricks
RUN sudo chown -R opam:opam /sqbricks
RUN chmod +x /sqbricks/scripts/benchmarks.sh

RUN sudo mv /usr/lib/libz3.so /usr/lib/libz3.so.4.12

RUN eval $(opam env) && opam install . --deps-only -y

RUN eval $(opam env) && dune build

# Quantikz needs xargs/environ, provided by texlive-latex-extra on Ubuntu 22.04.
RUN sudo apt-get update && sudo apt-get install -y \
  texlive-latex-extra \
  && sudo apt-get clean

# Install the current Quantikz2 TikZ library from CTAN without rebuilding the
# heavier OCaml/Python layers above.
RUN tmp="$(mktemp -d)" && \
  python3 -c "import urllib.request; urllib.request.urlretrieve('https://mirrors.ctan.org/graphics/pgf/contrib/quantikz.zip', '$tmp/quantikz.zip')" && \
  python3 -m zipfile -e "$tmp/quantikz.zip" "$tmp" && \
  sudo mkdir -p /usr/local/share/texmf/tex/latex/quantikz && \
  sudo install -m 0644 "$tmp/quantikz/tikzlibraryquantikz.code.tex" /usr/local/share/texmf/tex/latex/quantikz/ && \
  sudo install -m 0644 "$tmp/quantikz/tikzlibraryquantikz2.code.tex" /usr/local/share/texmf/tex/latex/quantikz/ && \
  sudo texhash && \
  kpsewhich tikzlibraryquantikz2.code.tex && \
  rm -rf "$tmp"

CMD ["/bin/bash"]
