# =============================================================================
# Multi-stage build (EOL image hardening, #251-255/#346): compile everything in a
# full-toolchain `builder` stage, then ship a slim `runtime` stage carrying ONLY
# the runtime deps + built artifacts. Drops build-essential, all `-dev` headers,
# the C/C++ toolchain, and node from the shipped image — the bulk of the Trivy
# HIGH/CRITICAL CVEs (the ~1354 came from the full Debian base + build packages).
#
# Both stages are Debian bookworm on ruby 3.3.6, so the gems + python extensions
# compiled in `builder` are ABI-compatible when copied into `runtime`.
#
# WARNING: RUNTIME NOT YET VALIDATED end-to-end (the container booting + serving) —
# that needs a dev smoke once the EKS/Argo dev cluster is up. This pass proves the
# build assembles and the CVE count drops; runtime acceptance is the follow-up gate.
# =============================================================================

# ---------- builder: full toolchain (unchanged from the single-stage image) ----------
# bug-#001/#004: Ruby 3.1.6 (EOL) -> 3.3.6, pinned by multi-arch digest.
FROM ruby:3.3.6@sha256:347edd0c70ee08d87de9f01b99de2f14a64cedb5d1bfb38457dfe8cd0bf113c5 AS builder

RUN apt-get update && apt-get upgrade -y && \
  apt-get install -y \
  build-essential \
  default-libmysqlclient-dev \
  python3-dev \
  python3-pip \
  lsb-release \
  apt-transport-https

# samtools 1.17 (apt's 1.9 lacks the -X flag the AMR download service needs).
RUN curl -L https://github.com/samtools/samtools/releases/download/1.17/samtools-1.17.tar.bz2 | \
  tar xj && cd samtools-1.17/ && make && make install

# node pinned to .node-version (CZID-197) — build-time only (webpack); NOT shipped.
COPY .node-version /tmp/.node-version
RUN NODE_VERSION="$(cat /tmp/.node-version)" \
  && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.gz" \
  && tar -xzf "node-v${NODE_VERSION}-linux-x64.tar.gz" -C /usr/local --strip-components=1 --no-same-owner \
  && rm "node-v${NODE_VERSION}-linux-x64.tar.gz" \
  && node --version && npm --version
RUN npm i -g npm@11.16.0

RUN pip3 config set global.break-system-packages true
RUN pip3 install --upgrade pip

# chamber — pulls secrets at boot (bin/entrypoint.sh); needed at runtime, copied below.
RUN curl -L https://github.com/segmentio/chamber/releases/download/v2.10.8/chamber-v2.10.8-linux-amd64 -o /bin/chamber
RUN chmod +x /bin/chamber

COPY requirements.txt ./
RUN pip3 install "cython<3.0.0"
RUN pip3 install "pyyaml==5.4.1" --no-build-isolation
RUN pip3 install -r requirements.txt

WORKDIR /app

# .npmrc carries legacy-peer-deps=true (bug-#003) — must precede `npm ci`.
COPY .npmrc package.json package-lock.json ./
RUN npm ci --omit=optional

# Generate the app's static resources (webpack). 6GB heap for node.
ENV NODE_OPTIONS="--max_old_space_size=6144"
COPY app/assets app/assets
COPY webpack.config.common.js webpack.config.prod.js .babelrc ./
# CZID-380: cache-bust the asset build on any frontend source/config change.
ARG SRC_HASH=unset
RUN echo "asset source hash: ${SRC_HASH}"
RUN mkdir -p app/assets/dist && npm run build-img && ls -l app/assets/dist/

# RubyGems (.ruby-version needed: Gemfile pins `ruby file: '.ruby-version'`).
COPY Gemfile Gemfile.lock .ruby-version ./
RUN gem install bundler -v '2.5.22'
RUN bundle config set force_ruby_platform true
RUN bundle install --jobs 20 --retry 5

COPY . ./
ARG GIT_COMMIT
ENV GIT_VERSION=${GIT_COMMIT}

# ---------- runtime: slim — only runtime deps + built artifacts ----------
FROM ruby:3.3.6-slim AS runtime

# Runtime-only apt deps (NO compilers / -dev headers / node):
#  - libaio1 + the mysql-5.7 community client (deliberately non-MariaDB, for MySQL-8
#    virtual-generated-column import compat — see the original single-stage note).
#  - samtools shared libs (libncurses/libbz2/liblzma/zlib/libcurl/libdeflate).
#  - libmariadb3: the mysql2 gem's native ext links libmysqlclient (built against
#    default-libmysqlclient-dev = libmariadb-dev in builder).
#  - python3 runtime (the app shells out to python/awscli).
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
  ca-certificates curl wget tzdata procps \
  libaio1 libatomic1 libnuma1 \
  libncurses6 libbz2-1.0 liblzma5 zlib1g libcurl4 libdeflate0 \
  libmariadb3 \
  python3 libyaml-0-2 \
  && wget http://repo.mysql.com/apt/debian/pool/mysql-5.7/m/mysql-community/mysql-community-client_5.7.42-1debian10_amd64.deb \
  && (dpkg -i mysql-community-client*.deb || apt-get install -f -y --no-install-recommends) \
  && rm mysql-community-client*.deb \
  && rm -rf /var/lib/apt/lists/*

# Built artifacts from the builder stage.
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder /usr/local/bin/samtools /usr/local/bin/samtools
COPY --from=builder /bin/chamber /bin/chamber
# python packages + the awscli entrypoint (NOT /usr/local/bin wholesale — that would
# drag node back in). pip3 (break-system-packages) installs here on bookworm.
COPY --from=builder /usr/local/lib/python3.11/dist-packages /usr/local/lib/python3.11/dist-packages
COPY --from=builder /usr/local/bin/aws /usr/local/bin/aws

WORKDIR /app
COPY --from=builder /app /app

ARG GIT_COMMIT
ENV GIT_VERSION=${GIT_COMMIT}

EXPOSE 3000
ENTRYPOINT ["bin/entrypoint.sh"]
CMD ["rails", "server", "-b", "0.0.0.0", "-p", "3000"]
