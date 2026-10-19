# Build from the repository root: docker build -f frontend/Dockerfile .
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY api/package.json api/
COPY frontend/package.json frontend/
RUN npm ci --workspace=frontend
COPY frontend/ frontend/
RUN npm run build --workspace=frontend

FROM nginx:alpine
COPY --from=build /app/frontend/dist/ /usr/share/nginx/html/
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY frontend/entrypoint.sh /entrypoint.sh

# Set proper permissions for the nginx html directory and entrypoint script
RUN chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chmod +x /entrypoint.sh

# Set default environment variables
ENV API_HOST=api
ENV API_PORT=3000

EXPOSE 80

# Use ENTRYPOINT instead of CMD for better handling in App Service
ENTRYPOINT ["/entrypoint.sh"]
