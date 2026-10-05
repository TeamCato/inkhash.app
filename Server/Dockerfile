FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
COPY inkhashd.ts store.ts accounts.ts ./
COPY admin ./admin
RUN npm ci && npx tsc --pretty false

FROM node:24-alpine
LABEL org.opencontainers.image.source=https://github.com/teamCato/inkhash.app
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY package.json ./
ARG VERSION=0.0.0
RUN npm pkg set version="$VERSION" && mkdir -p /data && chown node:node /data && chmod 700 /data
ENV INKHASH_DATA=/data
ENV INKHASH_HOST=0.0.0.0
ENV INKHASH_PORT=8787
ENV NODE_ENV=production
USER node
VOLUME /data
EXPOSE 8787
HEALTHCHECK CMD node -e "fetch('http://127.0.0.1:8787/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/inkhashd.js"]
