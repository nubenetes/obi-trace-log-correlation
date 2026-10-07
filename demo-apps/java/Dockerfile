# Multi-stage build for minimal Java 21 container image
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app
COPY App.java .
RUN javac App.java

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=builder /app/*.class .

# Runtime configuration:
# - USE_VIRTUAL_THREADS=false (default): Uses platform thread pool (Works out of the box with OBI)
# - USE_VIRTUAL_THREADS=true: Enables Java 21 Project Loom virtual threads (demonstrates carrier collision)
ENV USE_VIRTUAL_THREADS=false
ENV PORT=8085

EXPOSE 8085
USER 10001:10001
CMD ["java", "App"]
