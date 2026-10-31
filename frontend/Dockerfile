# Build context: repository root (the import sheet bundles ../examples/AGENT_PROMPT.md).
FROM node:22-alpine AS build
WORKDIR /srv/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
COPY examples /srv/examples
RUN npm run build

FROM nginx:1.27-alpine
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /srv/frontend/dist /usr/share/nginx/html
EXPOSE 80
