# Idea Board team server — no npm packages needed, only Node.js built-ins.
FROM node:22-alpine
WORKDIR /app
COPY server/server.js ./server.js
COPY index.html FONT-LICENSE.txt ./public/
ENV PORT=8080 DATA_DIR=/data PUBLIC_DIR=/app/public NODE_ENV=production
RUN mkdir -p /data && chown node:node /data
USER node
VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:8080/api/health >/dev/null || exit 1
CMD ["node", "server.js"]
