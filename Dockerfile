# E11 Console container for the office NAS.
# It holds only the runtime and the launcher; the launcher downloads E11 Console itself from the
# e11hq/e11-console GitHub releases and keeps it up to date (so this image rarely changes).
# Data (database, files, backups, app versions) lives in /data → the NAS shared folder E11Console.
FROM node:22-bookworm-slim

# ffmpeg: image/video previews and logo resizing · poppler-utils: PDF previews
# LibreOffice (no GUI): Word / PowerPoint / Excel previews · fonts so documents look right (incl. Arabic,
# and metric matches for Calibri/Cambria/Arial/Times) · tini: clean shutdown · tzdata: "update at 2 AM Dubai time"
RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg poppler-utils tini ca-certificates tzdata \
      libreoffice-nogui \
      fonts-liberation2 fonts-dejavu-core fonts-noto-core fonts-crosextra-carlito fonts-crosextra-caladea \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY launcher/package.json launcher/launcher.js launcher/

ENV NODE_ENV=production \
    NODE_NO_WARNINGS=1 \
    DATA_DIR=/data \
    PORT=8080 \
    TZ=Asia/Dubai

VOLUME /data
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "launcher/launcher.js"]
