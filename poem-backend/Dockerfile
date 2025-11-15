# Simplified Dockerfile - Binary is built natively and injected
# Run: ./scripts/build-docker-binary.sh before docker build
# Or use: just docker-build

FROM --platform=linux/amd64 debian:trixie-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -r -s /bin/false appuser

# Create data directory with proper permissions
RUN mkdir -p /data && chown appuser:appuser /data

# Copy pre-built binary (must be built with ./scripts/build-docker-binary.sh)
COPY target/docker/icp-marketplace-api /usr/local/bin/api-server

# Set permissions
RUN chown appuser:appuser /usr/local/bin/api-server && \
    chmod +x /usr/local/bin/api-server

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:58000/api/v1/health || exit 1

# Run the application
CMD ["api-server"]
