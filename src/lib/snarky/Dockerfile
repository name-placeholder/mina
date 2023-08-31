FROM ocaml/opam:debian-ocaml-4.14

# dependencies
RUN sudo apt-get update
RUN sudo apt-get install -y \
    build-essential \
    pkg-config=0.29.2-1 \
    git \
    libffi-dev=3.3-6 \
    libgmp-dev=2:6.2.1+dfsg-1+deb11u1 \
    libgmp3-dev=2:6.2.1+dfsg-1+deb11u1 \
    libprocps-dev=2:3.3.17-5 \
    libssl-dev \
    m4=1.4.18-5


# Create a volume we can work in. For initial build, 
# we'll copy the local context. To update the snarky 
# library itself later, bind mount your updated source 
# over this and run the build again.
COPY . /source
RUN sudo chown -R opam:opam /source
VOLUME /source

# Move to a newer version of OCaml and install dune.
RUN eval "$(opam config env)" 
RUN opam update -y
RUN opam upgrade -y
RUN opam install dune

WORKDIR /source

# Pin and install the dependencies.
RUN opam pin add -y --kind path .

CMD ["bash" "opam list"]
