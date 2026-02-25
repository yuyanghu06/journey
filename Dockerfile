FROM node:20-alpine AS builder
WORKDIR /app
RUN apk add --no-cache openssl
COPY . .
RUN npm ci
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
RUN apk add --no-cache openssl
COPY package*.json ./
COPY --from=builder /app/prisma ./prisma
RUN npm ci && npx prisma generate
COPY --from=builder /app/dist ./dist
COPY prompts ./prompts
COPY start.sh ./start.sh
EXPOSE 8080
CMD ["sh", "start.sh"]
