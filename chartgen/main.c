#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <libpq-fe.h>

#define MAX_POINTS          5000
#define PX_PER_POINT        5       // fixed horizontal distance per sample
#define MIN_LABEL_PIXEL_GAP 80      // minimum pixel gap between timestamp labels

// ======================================================
// Save SVG (fixed pixel spacing + locked timestamps)
// ======================================================
void save_svg(const char *filename, double *values, long long *timestamps, int rows) {
    if (rows <= 1) return;

    // ---------------- Min/max Y ----------------
    double minVal = values[0];
    double maxVal = values[0];
    for (int i = 1; i < rows; i++) {
        if (values[i] < minVal) minVal = values[i];
        if (values[i] > maxVal) maxVal = values[i];
    }
    double range = maxVal - minVal;
    if (range == 0) range = 1.0;

    // ---------------- Layout ----------------
    int left_pad   = 60;
    int right_pad  = 20;
    int top_pad    = 10;
    int bottom_pad = 110;    

    int plot_width = (rows - 1) * PX_PER_POINT;
    int width      = left_pad + plot_width + right_pad;
    int height     = 480;    

    // ---------------- Open file ----------------
    char path[256];
    snprintf(path, sizeof(path), "/output/%s", filename);
    FILE *f = fopen(path, "w");
    if (!f) { perror("SVG write failed"); return; }

    fprintf(f,
        "<svg width=\"%d\" height=\"%d\" xmlns=\"http://www.w3.org/2000/svg\">\n",
        width, height);

    fprintf(f,
        "<rect x=\"0\" y=\"0\" width=\"%d\" height=\"%d\" fill=\"white\" />\n",
        width, height);

    // ---------------- Y-axis grid ----------------
    int grid_lines = 6;
    for (int i = 0; i <= grid_lines; i++) {
        double frac = (double)i / grid_lines;
        double y = top_pad + (1.0 - frac) * (height - top_pad - bottom_pad);
        double val = minVal + frac * range;

        fprintf(f,
            "<line x1=\"%d\" y1=\"%.1f\" x2=\"%d\" y2=\"%.1f\" stroke=\"#e0e0e0\" />\n",
            left_pad, y, width - right_pad, y);

        fprintf(f,
            "<text x=\"5\" y=\"%.1f\" font-size=\"12\" fill=\"#333\">%.2f</text>\n",
            y + 4, val);
    }

    // ---------------- Data polyline ----------------
    fprintf(f, "<polyline fill=\"none\" stroke=\"blue\" stroke-width=\"2\" points=\"");

    for (int i = 0; i < rows; i++) {
        double x = left_pad + i * PX_PER_POINT;
        double norm = (values[i] - minVal) / range;
        double y = top_pad + (1.0 - norm) * (height - top_pad - bottom_pad);
        fprintf(f, "%.1f,%.1f ", x, y);
    }

    fprintf(f, "\" />\n");

    // ======================================================
    // TIMESTAMP LABELS — locked to datapoints
    // ======================================================
    int label_step = MIN_LABEL_PIXEL_GAP / PX_PER_POINT;
    if (label_step < 1) label_step = 1;

    for (int i = 0; i < rows; i += label_step) {

        double x = left_pad + i * PX_PER_POINT;

        long long ts_raw = timestamps[i];
        time_t seconds;
        long ms = 0;

        if (ts_raw > 1000000000000LL) { // epoch ms
            seconds = (time_t)(ts_raw / 1000);
            ms = (long)(ts_raw % 1000);
        } else {
            seconds = (time_t)ts_raw;
            ms = 0;
        }

        struct tm *tm_info = localtime(&seconds);
        if (!tm_info) continue;

        char base[32];
        strftime(base, sizeof(base), "%H:%M:%S", tm_info);

        char label[64];
        snprintf(label, sizeof(label), "%s.%03ld", base, ms);

        // FIX: move label up so rotation never gets cropped
        int text_y = height - bottom_pad + 35;

        fprintf(f,
            "<text x=\"%.1f\" y=\"%d\" font-size=\"12\" fill=\"#444\" "
            "transform=\"rotate(55 %.1f,%d)\">%s</text>\n",
            x, text_y, x, text_y, label);
    }

    fprintf(f, "</svg>\n");
    fclose(f);

    printf("Generated %s (%d points, width=%d)\n", filename, rows, width);
}

// ======================================================
// Fetch + render charts once
// ======================================================
void generate_charts_once(void) {

    PGconn *conn = PQconnectdb("host=db dbname=metrics user=admin password=admin");
    if (PQstatus(conn) != CONNECTION_OK) {
        fprintf(stderr, "DB connect error: %s\n", PQerrorMessage(conn));
        PQfinish(conn);
        return;
    }

    PGresult *res = PQexec(conn,
        "SELECT timestamp, latency, jitter, packet_loss, bandwidth "
        "FROM metrics ORDER BY timestamp ASC LIMIT 5000");

    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        fprintf(stderr, "Query fail: %s\n", PQerrorMessage(conn));
        PQclear(res);
        PQfinish(conn);
        return;
    }

    int rows = PQntuples(res);
    if (rows > MAX_POINTS) rows = MAX_POINTS;

    long long timestamps[MAX_POINTS];
    double latency[MAX_POINTS];
    double jitter[MAX_POINTS];
    double packet_loss[MAX_POINTS];
    double bandwidth[MAX_POINTS];

    for (int i = 0; i < rows; i++) {
        timestamps[i]   = atoll(PQgetvalue(res, i, 0));
        latency[i]      = atof(PQgetvalue(res, i, 1));
        jitter[i]       = atof(PQgetvalue(res, i, 2));
        packet_loss[i]  = atof(PQgetvalue(res, i, 3));
        bandwidth[i]    = atof(PQgetvalue(res, i, 4));
    }

    PQclear(res);
    PQfinish(conn);

    save_svg("latency.svg",      latency,     timestamps, rows);
    save_svg("jitter.svg",       jitter,      timestamps, rows);
    save_svg("packet_loss.svg",  packet_loss, timestamps, rows);
    save_svg("bandwidth.svg",    bandwidth,   timestamps, rows);
}

// ======================================================
// Main render loop
// ======================================================
int main(void) {
    while (1) {
        generate_charts_once();

        // Notify dashboard (SSE)
        int rc = system("curl -sS http://dashboard:8080/event/chart-updated >/dev/null 2>&1");
        if (rc != 0) {
            fprintf(stderr, "Warning: SSE notify fail rc=%d\n", rc);
        }

        usleep(200 * 1000);  // 200 ms
    }

    return 0;
}