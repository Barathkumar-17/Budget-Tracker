# The whole app in one image: the Flutter web app and the API behind one port.
#   docker build -t budget-tracker . && docker run -p 8000:8000 budget-tracker
# Then open http://localhost:8000 (app) and http://localhost:8000/docs (API).

# Stage 1: build the Flutter web app. It talks to the API on the same origin.
FROM ghcr.io/cirruslabs/flutter:3.35.7 AS web
WORKDIR /src/app
COPY app/pubspec.yaml ./
COPY app/assets assets
COPY app/lib lib
COPY app/brand brand
COPY app/tool/patch_web.py tool/patch_web.py
# The web shell gets the app's own title, colours and icons (needs Python).
RUN (command -v python3 >/dev/null || (apt-get update -qq && apt-get install -y -qq python3)) \
 && flutter create . --project-name budget_tracker --platforms=web \
 && python3 tool/patch_web.py \
 && flutter pub get \
 && flutter build web --release --dart-define=API_URL=same-origin --dart-define=SHOW_DEMO=true

# Stage 2: the API, serving the built app at "/".
FROM python:3.12-slim
WORKDIR /srv
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/main.py backend/seed_demo.py backend/seed_review.py backend/start.sh ./
COPY --from=web /src/app/build/web ./web

# SQLite lives in /data (a volume locally; ephemeral on free hosting tiers).
ENV BUDGET_DB=/data/budget.db
RUN mkdir /data
VOLUME /data

# Hosts like Render pass the port in $PORT; default to 8000 locally.
EXPOSE 8000
CMD ["sh", "start.sh"]
