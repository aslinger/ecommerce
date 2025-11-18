# Stage 1: Build the Spring Boot application using Maven and Corretto 17
FROM maven:3.9.5-amazoncorretto-17 AS build
WORKDIR /app
# Copy the pom.xml (assuming it includes the AWS SDK v2 SQS dependency)
COPY pom.xml .
# Download dependencies
RUN mvn dependency:go-offline
# Copy the source code and build the final JAR
COPY src ./src
RUN mvn clean package -DskipTests

# Stage 2: Create the final, small runtime image
FROM amazoncorretto:17-alpine-jdk
# Set timezone for correct logging timestamps
ENV TZ=UTC
WORKDIR /app
# Copy the built JAR from the build stage
COPY --from=build /app/target/*.jar app.jar
# Standard Spring Boot port
EXPOSE 8080
# Run the application
ENTRYPOINT [\"java\", \"-jar\", \"app.jar\"]
