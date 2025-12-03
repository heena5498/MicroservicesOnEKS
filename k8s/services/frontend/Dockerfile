# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY frontend/package.json ./

# Install dependencies using npm
RUN npm install

# Copy source code
COPY frontend/ .

# Build the production bundle
ARG VITE_API_URL=http://localhost
ENV VITE_API_URL=${VITE_API_URL}
RUN npm run build

# Production stage - serve with nginx
FROM nginx:alpine

# Copy custom nginx config for SPA
RUN rm /etc/nginx/conf.d/default.conf
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf

# Copy built assets from builder
COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
