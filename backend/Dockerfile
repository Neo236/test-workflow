# ==========================================
# Dockerfile Backend - Java 17 Spring Boot
# ==========================================
# Basado en el del repo oficial, con 2 fixes necesarios para la VM OCI (ARM64):
# 1. Imágenes multi-arch: las variantes -alpine de maven/temurin no publican
#    ARM64 y el build falla en la VM Ampere.
# 2. Sin HEALTHCHECK de /actuator/health: el pom no incluye
#    spring-boot-starter-actuator (pendiente en el repo oficial; al agregarlo,
#    restaurar el HEALTHCHECK).
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /app

COPY analisis-energetico-api/pom.xml .
COPY analisis-energetico-api/.mvn .mvn
COPY analisis-energetico-api/mvnw .
COPY analisis-energetico-api/mvnw.cmd .

RUN ./mvnw dependency:go-offline -B || true

COPY analisis-energetico-api/src ./src

RUN ./mvnw clean package -DskipTests

# ==========================================
# Runtime Stage
# ==========================================
FROM eclipse-temurin:17-jre AS runner

WORKDIR /app

RUN groupadd --system appgroup && useradd --system --gid appgroup appuser

COPY --from=builder /app/target/*.jar app.jar
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

ENV PORT=8080 \
    SPRING_PROFILES_ACTIVE=prod \
    JAVA_OPTS="-XX:+UseG1GC -XX:MaxRAMPercentage=75.0 -Duser.timezone=UTC"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
