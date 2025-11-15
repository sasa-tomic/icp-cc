# Minimal Dockerfile for isolated wrangler execution
# Lightweight container focused only on Cloudflare Workers development

FROM node:22-alpine

# Install curl for health checks and ca-certificates for HTTPS
RUN apk add --no-cache curl ca-certificates

# Create non-root user for security
RUN adduser -D -u 1000 ubuntu

# Set working directory
WORKDIR /code/cloudflare-api

# Install wrangler globally
RUN npm install -g wrangler

# Switch to non-root user
USER ubuntu

# Ensure .wrangler directory exists for state persistence
RUN mkdir -p /home/ubuntu/.wrangler

# Expose port 8787 (will be managed by docker-compose)
EXPOSE 8787

# Default command (will be overridden by docker-compose)
CMD ["wrangler", "dev", "--config", "wrangler.local.jsonc", "--port", "8787"]