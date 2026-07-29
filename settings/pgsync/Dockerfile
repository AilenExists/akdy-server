FROM python:3.11-slim

RUN pip install --no-cache-dir pgsync

WORKDIR /app
COPY schema.json .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]