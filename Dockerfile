# syntax=docker/dockerfile:1.4

FROM ghcr.io/foundry-rs/foundry:nightly

RUN mkdir /app
WORKDIR /app
COPY . .
RUN forge build

EXPOSE 8545

ENTRYPOINT ["/bin/sh", "anvil.sh"]
