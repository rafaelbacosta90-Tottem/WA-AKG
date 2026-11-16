FROM node:20-alpine AS builder
WORKDIR /app

RUN apk add --no-cache openssl ca-certificates

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV DATABASE_URL="mysql://build_user:build_pass@localhost:3306/wa_akg"
ENV AUTH_SECRET="build_secret_must_be_at_least_32_characters_long_for_nextjs"
ENV NEXTAUTH_SECRET="build_secret_must_be_at_least_32_characters_long_for_nextjs"

# Copia dependências
COPY package*.json ./
COPY prisma ./prisma/
RUN npm ci --legacy-peer-deps && npm cache clean --force

# Copia o código e gera o client usando obrigatoriamente a versão local do projeto
COPY . .
RUN ./node_modules/.bin/prisma generate && npm run build

# Remove devDependencies
RUN npm prune --omit=dev && npm install --no-save tsx typescript

# Imagem final de produção
FROM node:20-alpine AS runner
WORKDIR /app

RUN apk add --no-cache openssl ca-certificates

COPY --from=builder --chown=node:node /app/package*.json ./
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/.next ./.next
COPY --from=builder --chown=node:node /app/src ./src
COPY --from=builder --chown=node:node /app/prisma ./prisma
COPY --from=builder --chown=node:node /app/public ./public
COPY --from=builder --chown=node:node /app/tsconfig.json ./
COPY --from=builder --chown=node:node /app/next.config.ts ./
COPY --from=builder --chown=node:node /app/scripts ./scripts

RUN mkdir -p /app/data/media /app/data/auth /app/uploads && chown -R node:node /app/data /app/uploads

USER node

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
EXPOSE 3000

CMD ["sh", "-c", "./node_modules/.bin/prisma db push && (if [ -n \"$ADMIN_EMAIL\" ] && [ -n \"$ADMIN_PASSWORD\" ]; then node scripts/setup-admin.js \"$ADMIN_EMAIL\" \"$ADMIN_PASSWORD\"; fi) && node node_modules/tsx/dist/cli.mjs src/server/index.ts"]
