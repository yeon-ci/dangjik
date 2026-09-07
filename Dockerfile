# ---- Build stage ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn -q -DskipTests package

# ---- Run stage ----
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/dangjik.jar app.jar

EXPOSE 8080
# 실제 배포 시 -e SERVER_NAME=Server-A / Server-B 로 서버마다 다르게 주입
ENTRYPOINT ["java", "-jar", "app.jar"]
