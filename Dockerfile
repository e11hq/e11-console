# E11 Console — one container: the app server + the web app.
# Data (database, files, backups, trash) lives in /data, mapped to the NAS shared folder E11Console.
FROM node:22-bookworm-slim

# ffmpeg: image/video previews and logo resizing · poppler-utils: PDF previews · tini: clean shutdown
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg poppler-utils tini ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY server/package.json server/package.json
COPY server/src server/src
COPY web web
COPY VERSION VERSION

ENV NODE_ENV=production \
    NODE_NO_WARNINGS=1 \
    DATA_DIR=/data \
    WEB_DIR=/app/web \
    PORT=8080

VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server/src/index.js"]
