# Binary is built natively and injected

FROM --platform=linux/amd64 debian:trixie-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with specific UID/GID to match host user
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g 1000 -s /bin/false appuser

# Create data directory with proper permissions
RUN mkdir -p /data && chown appuser:appuser /data

# Copy pre-built binary (must be built with cargo build --release)
COPY target/release/icp-marketplace-api /usr/local/bin/api-server

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
