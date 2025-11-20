FROM python:3.11-slim

WORKDIR /app

COPY app.py /app
COPY templates /app/templates
COPY static /app/static

RUN pip install flask psycopg2-binary

EXPOSE 8080

CMD ["python", "app.py"]