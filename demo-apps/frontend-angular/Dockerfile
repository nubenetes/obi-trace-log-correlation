FROM node:20-alpine

WORKDIR /app

# Copy application files
COPY package.json server.js ./
COPY src/ ./src/

EXPOSE 8086

# Non-root security context
USER 10001:10001

CMD ["node", "server.js"]
