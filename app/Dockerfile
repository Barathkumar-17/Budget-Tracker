# Stage 1: build the Flutter web bundle.
FROM ghcr.io/cirruslabs/flutter:3.35.7 AS build

WORKDIR /app
COPY pubspec.yaml ./
COPY lib lib

# Address the browser uses to reach the API (baked into the bundle).
ARG API_URL=http://localhost:8000

RUN flutter create . --project-name budget_tracker --platforms=web \
 && flutter pub get \
 && flutter build web --release --dart-define=API_URL=${API_URL}

# Stage 2: serve the static files.
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
