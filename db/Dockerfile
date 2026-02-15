FROM pgvector/pgvector:pg16

# PGroonga（日本語全文検索）のインストール
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      software-properties-common \
      gnupg \
      wget && \
    # Groonga公式APTリポジトリの追加
    wget -q -O /tmp/groonga.deb https://packages.groonga.org/debian/groonga-apt-source-latest-bookworm.deb && \
    dpkg -i /tmp/groonga.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-16-pgdg-pgroonga && \
    rm -rf /var/lib/apt/lists/* /tmp/*
