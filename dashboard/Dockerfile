FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y curl && apt-get clean

COPY app.py /app
COPY templates /app/templates
COPY static /app/static

RUN pip install flask psycopg2-binary

EXPOSE 8080

RUN pip install gunicorn gevent

CMD ["gunicorn", "-k", "gevent", "--bind", "0.0.0.0:8080", "app:app", "--timeout", "120", "--worker-connections", "1000"]