FROM node:22-alpine AS frontend
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html tsconfig.json vite.config.ts ./
COPY src ./src
COPY public ./public
RUN npm run build

FROM golang:1.22-alpine AS backend
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /portal .

FROM alpine:3.20
WORKDIR /app
COPY --from=backend /portal /app/portal
COPY --from=frontend /src/dist /app/dist
ENV PORTAL_STATIC_DIR=/app/dist
ENV PORTAL_ADDR=:8080
EXPOSE 8080
CMD ["/app/portal"]
