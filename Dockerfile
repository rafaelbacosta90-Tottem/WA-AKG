FROM node:20-alpine AS builder
WORKDIR /app

RUN apk add --no-cache openssl ca-certificates

ENV NEXT_TELEMETRY_DISABLED=1
ENV DATABASE_URL="postgresql://build_user:build_pass@localhost:5432/wa_akg"
ENV AUTH_SECRET="build_secret_must_be_at_least_32_characters_long_for_nextjs"
ENV NEXTAUTH_SECRET="build_secret_must_be_at_least_32_characters_long_for_nextjs"

# Copia arquivos de dependência e schema
COPY package*.json ./
COPY prisma ./prisma/

# Instala todas as dependências completas e fixa o Prisma 5.22.0
RUN npm install --legacy-peer-deps && npm install prisma@5.22.0 tsx typescript --legacy-peer-deps

# Copia o restante do código e gera o Client + Build do Next.js
COPY . .
RUN npx prisma generate && npm run build

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

CMD ["sh", "-c", "npx prisma db push && (if [ -n \"$ADMIN_EMAIL\" ] && [ -n \"$ADMIN_PASSWORD\" ]; then node scripts/setup-admin.js \"$ADMIN_EMAIL\" \"$ADMIN_PASSWORD\"; fi) && npx tsx src/server/index.ts"]
