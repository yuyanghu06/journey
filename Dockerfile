FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
COPY prisma ./prisma
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
COPY package*.json ./
COPY --from=builder /app/prisma ./prisma
RUN npm ci
COPY --from=builder /app/dist ./dist
COPY start.sh ./start.sh
EXPOSE 3000
CMD ["sh", "start.sh"]
