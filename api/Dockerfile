# Build from the repository root: docker build -f api/Dockerfile .
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY api/package.json api/
COPY frontend/package.json frontend/
RUN npm ci --workspace=api
COPY api/ api/
RUN npm run build --workspace=api

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
COPY api/package.json api/
COPY frontend/package.json frontend/
RUN npm ci --workspace=api --omit=dev && npm cache clean --force
COPY --from=build /app/api/dist api/dist
# swagger-jsdoc reads the JSDoc annotations in src/ at runtime to build /api-docs
COPY api/src api/src
WORKDIR /app/api
EXPOSE 3000
USER node
CMD ["node", "dist/index.js"]
