#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libpq-fe.h>

#define SVG_WIDTH 800
#define SVG_HEIGHT 300
#define MAX_POINTS 1000

// ===================== SVG GENERATION =====================
void save_svg(const char *filename, double *values, int rows) {
    if (rows <= 0) {
        printf("Skipping %s (no data)\n", filename);
        return;
    }

    double minVal = values[0];
    double maxVal = values[0];

    for (int i = 1; i < rows; i++) {
        if (values[i] < minVal) minVal = values[i];
        if (values[i] > maxVal) maxVal = values[i];
    }

    double range = maxVal - minVal;
    if (range == 0) range = 1;

    char path[256];
    snprintf(path, sizeof(path), "/output/%s", filename);

    FILE *f = fopen(path, "w");
    if (!f) {
        perror("SVG write failed");
        return;
    }

    fprintf(f,
        "<svg width=\"%d\" height=\"%d\" xmlns=\"http://www.w3.org/2000/svg\">\n",
        SVG_WIDTH, SVG_HEIGHT);

    fprintf(f,
        "<rect x=\"0\" y=\"0\" width=\"%d\" height=\"%d\" "
        "fill=\"white\" stroke=\"lightgray\" />\n",
        SVG_WIDTH, SVG_HEIGHT);

    fprintf(f,
        "<polyline fill=\"none\" stroke=\"blue\" stroke-width=\"2\" points=\"");

    for (int i = 0; i < rows; i++) {
        double x = (double)i / (double)(rows - 1) * (SVG_WIDTH - 20) + 10;
        double norm = (values[i] - minVal) / range;
        double y = (1.0 - norm) * (SVG_HEIGHT - 20) + 10;
        fprintf(f, "%.1f,%.1f ", x, y);
    }

    fprintf(f, "\" />\n</svg>\n");
    fclose(f);

    printf("Generated %s (%d points)\n", filename, rows);
}

// ===================== MAIN PROGRAM =====================
int main() {
    PGconn *conn = PQconnectdb(
        "host=db dbname=metrics user=admin password=admin"
    );

    if (PQstatus(conn) != CONNECTION_OK) {
        fprintf(stderr, "DB connection failed: %s\n", PQerrorMessage(conn));
        PQfinish(conn);
        return 1;
    }

    // New query — timestamp is already a BIGINT
    PGresult *res = PQexec(conn,
        "SELECT timestamp, latency, jitter, packet_loss, bandwidth "
        "FROM metrics ORDER BY timestamp ASC LIMIT 500"
    );

    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        fprintf(stderr, "Query failed: %s\n", PQerrorMessage(conn));
        PQclear(res);
        PQfinish(conn);
        return 1;
    }

    int rows = PQntuples(res);
    if (rows > MAX_POINTS) rows = MAX_POINTS;

    double latency[MAX_POINTS];
    double jitter[MAX_POINTS];
    double packet_loss[MAX_POINTS];
    double bandwidth[MAX_POINTS];

    for (int i = 0; i < rows; i++) {
        latency[i]      = atof(PQgetvalue(res, i, 1));
        jitter[i]       = atof(PQgetvalue(res, i, 2));
        packet_loss[i]  = atof(PQgetvalue(res, i, 3));
        bandwidth[i]    = atof(PQgetvalue(res, i, 4));
    }

    PQclear(res);
    PQfinish(conn);

    save_svg("latency.svg", latency, rows);
    save_svg("jitter.svg", jitter, rows);
    save_svg("packet_loss.svg", packet_loss, rows);
    save_svg("bandwidth.svg", bandwidth, rows);

    printf("All charts generated.\n");
    return 0;
}