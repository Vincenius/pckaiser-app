# PCKaiser server (V2). Build from the REPOSITORY ROOT so the shared
# game_core package is in context:
#   docker build -f backend/Dockerfile -t pckaiser-server .
FROM dart:stable AS build
WORKDIR /app
COPY packages/game_core packages/game_core
COPY backend backend
WORKDIR /app/backend
RUN dart pub get && dart compile exe bin/server.dart -o /server

FROM debian:bookworm-slim
# FCM push (backend/lib/src/fcm_push_service.dart) calls fcm.googleapis.com
# over HTTPS; without a CA trust store every send fails with
# CERTIFICATE_VERIFY_FAILED, silently (push is fire-and-forget by design).
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /server /server
ENV PORT=3000 STORE_DIR=/data
VOLUME /data
EXPOSE 3000
CMD ["/server"]
