FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
EXPOSE 8083
USER 10001:10001
CMD ["node", "server.js"]
