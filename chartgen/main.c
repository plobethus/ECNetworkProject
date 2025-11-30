#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <libpq-fe.h>

#define DEFAULT_NOTIFY_URL "http://dashboard:8080/event/chart-updated"
#define DEFAULT_NOTIFY_URL_ALT "http://host.docker.internal:8080/event/chart-updated"

#define MAX_POINTS          5000
#define MAX_NODES           16
#define PX_PER_POINT        5       // fixed horizontal distance per sample
#define MIN_LABEL_PIXEL_GAP 80      // minimum pixel gap between timestamp labels

typedef struct {
    char id[64];
    long long timestamps[MAX_POINTS];
    double latency[MAX_POINTS];
    double jitter[MAX_POINTS];
    double packet_loss[MAX_POINTS];
    double bandwidth[MAX_POINTS];
    int count;
} NodeSeries;

typedef enum {
    METRIC_LATENCY = 0,
    METRIC_JITTER,
    METRIC_PACKET_LOSS,
    METRIC_BANDWIDTH
} MetricType;

static const char *COLOR_PALETTE[] = {
    "#007bff", "#ff4d4f", "#5cd65c", "#f7c948",
    "#9b59b6", "#00c4b4", "#ff8c42", "#e84393"
};
static const int COLOR_COUNT = sizeof(COLOR_PALETTE) / sizeof(COLOR_PALETTE[0]);

// ======================================================
// Helpers and SVG rendering (multi-node, per metric)
// ======================================================
int find_or_create_node(NodeSeries *nodes, int *node_count, const char *id) {
    for (int i = 0; i < *node_count; i++) {
        if (strncmp(nodes[i].id, id, sizeof(nodes[i].id)) == 0) {
            return i;
        }
    }
    if (*node_count >= MAX_NODES) {
        return -1;
    }
    snprintf(nodes[*node_count].id, sizeof(nodes[*node_count].id), "%s", id);
    nodes[*node_count].count = 0;
    (*node_count)++;
    return *node_count - 1;
}

double get_metric_value(const NodeSeries *node, int idx, MetricType metric) {
    switch (metric) {
        case METRIC_LATENCY:     return node->latency[idx];
        case METRIC_JITTER:      return node->jitter[idx];
        case METRIC_PACKET_LOSS: return node->packet_loss[idx];
        case METRIC_BANDWIDTH:   return node->bandwidth[idx];
        default:                 return 0.0;
    }
}

static int cmp_ll(const void *a, const void *b) {
    long long x = *(const long long *)a;
    long long y = *(const long long *)b;
    if (x < y) return -1;
    if (x > y) return 1;
    return 0;
}

int find_ts_index(const long long *timeline, int timeline_count, long long ts) {
    for (int i = 0; i < timeline_count; i++) {
        if (timeline[i] == ts) return i;
    }
    return -1;
}

void save_svg(const char *filename, NodeSeries *nodes, int node_count, MetricType metric, const char *title, const char *unit, long long *timeline, int timeline_count) {
    if (node_count == 0 || timeline_count < 2) return;

    int max_points = 0;
    double minVal = 0, maxVal = 0;
    int initialized = 0;

    for (int n = 0; n < node_count; n++) {
        int rows = nodes[n].count;
        for (int i = 0; i < rows; i++) {
            double v = get_metric_value(&nodes[n], i, metric);
            if (!initialized) {
                minVal = maxVal = v;
                initialized = 1;
            } else {
                if (v < minVal) minVal = v;
                if (v > maxVal) maxVal = v;
            }
        }
    }

    if (!initialized) return;
    max_points = timeline_count;

    double range = maxVal - minVal;
    if (range == 0) range = 1.0;

    int left_pad   = 80;
    int right_pad  = 20;
    int top_pad    = 10;
    int bottom_pad = 130;

    int plot_width = (max_points - 1) * PX_PER_POINT;
    int width      = left_pad + plot_width + right_pad;
    int height     = 520;

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
            "<text x=\"5\" y=\"%.1f\" font-size=\"12\" fill=\"#333\">%.2f %s</text>\n",
            y + 4, val, unit);
    }

    // ---------------- Legend ----------------
    int legend_x = left_pad;
    int legend_y = top_pad + 30;
    for (int n = 0; n < node_count; n++) {
        const char *color = COLOR_PALETTE[n % COLOR_COUNT];
        fprintf(f,
            "<rect x=\"%d\" y=\"%d\" width=\"14\" height=\"14\" fill=\"%s\" stroke=\"none\" />\n",
            legend_x, legend_y, color);
        fprintf(f,
            "<text x=\"%d\" y=\"%d\" font-size=\"13\" fill=\"#222\">%s</text>\n",
            legend_x + 20, legend_y + 12, nodes[n].id);
        legend_y += 18;
    }

    // ---------------- Data polylines per node ----------------
    for (int n = 0; n < node_count; n++) {
        const char *color = COLOR_PALETTE[n % COLOR_COUNT];
        fprintf(f, "<polyline fill=\"none\" stroke=\"%s\" stroke-width=\"2\" points=\"", color);
        for (int i = 0; i < nodes[n].count; i++) {
            int idx = find_ts_index(timeline, timeline_count, nodes[n].timestamps[i]);
            if (idx < 0) continue;
            double x = left_pad + idx * PX_PER_POINT;
            double norm = (get_metric_value(&nodes[n], i, metric) - minVal) / range;
            double y = top_pad + (1.0 - norm) * (height - top_pad - bottom_pad);
            fprintf(f, "%.1f,%.1f ", x, y);
        }
        fprintf(f, "\" />\n");
    }

    // ======================================================
// TIMESTAMP LABELS - use longest series as reference
    // ======================================================
    int label_step = MIN_LABEL_PIXEL_GAP / PX_PER_POINT;
    if (label_step < 1) label_step = 1;
    for (int i = 0; i < timeline_count; i += label_step) {
        double x = left_pad + i * PX_PER_POINT;

        long long ts_raw = timeline[i];
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

        int text_y = height - bottom_pad + 35;

        fprintf(f,
            "<text x=\"%.1f\" y=\"%d\" font-size=\"12\" fill=\"#444\" "
            "transform=\"rotate(55 %.1f,%d)\">%s</text>\n",
            x, text_y, x, text_y, label);
    }

    fprintf(f, "</svg>\n");
    fclose(f);

    printf("Generated %s (nodes=%d, max_points=%d, width=%d)\n", filename, node_count, max_points, width);
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
        "SELECT node_id, timestamp, latency, jitter, packet_loss, bandwidth "
        "FROM metrics ORDER BY timestamp ASC LIMIT 5000");

    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        fprintf(stderr, "Query fail: %s\n", PQerrorMessage(conn));
        PQclear(res);
        PQfinish(conn);
        return;
    }

    int rows = PQntuples(res);

    NodeSeries nodes[MAX_NODES];
    int node_count = 0;
    long long timeline[MAX_POINTS];
    int timeline_count = 0;

    for (int i = 0; i < rows && i < MAX_POINTS; i++) {
        const char *node_id = PQgetvalue(res, i, 0);
        long long ts = atoll(PQgetvalue(res, i, 1));
        int idx = find_or_create_node(nodes, &node_count, node_id);
        if (idx < 0) {
            continue;
        }
        NodeSeries *node = &nodes[idx];
        if (node->count >= MAX_POINTS) continue;

        int pos = node->count;
        node->timestamps[pos]   = ts;
        node->latency[pos]      = atof(PQgetvalue(res, i, 2));
        node->jitter[pos]       = atof(PQgetvalue(res, i, 3));
        node->packet_loss[pos]  = atof(PQgetvalue(res, i, 4));
        node->bandwidth[pos]    = atof(PQgetvalue(res, i, 5));
        node->count++;

        // build global timeline (unique timestamps)
        if (timeline_count < MAX_POINTS) {
            timeline[timeline_count++] = ts;
        }
    }

    if (timeline_count > 1) {
        qsort(timeline, timeline_count, sizeof(long long), cmp_ll);
        // dedupe
        int unique = 1;
        for (int i = 1; i < timeline_count; i++) {
            if (timeline[i] != timeline[unique - 1]) {
                timeline[unique++] = timeline[i];
            }
        }
        timeline_count = unique;
    }

    PQclear(res);
    PQfinish(conn);

    save_svg("latency.svg",      nodes, node_count, METRIC_LATENCY, "Latency", "ms", timeline, timeline_count);
    save_svg("jitter.svg",       nodes, node_count, METRIC_JITTER, "Jitter", "ms", timeline, timeline_count);
    save_svg("packet_loss.svg",  nodes, node_count, METRIC_PACKET_LOSS, "Packet Loss", "%%", timeline, timeline_count);
    save_svg("bandwidth.svg",    nodes, node_count, METRIC_BANDWIDTH, "Bandwidth", "Mbps", timeline, timeline_count);
}

// ======================================================
// Main render loop
// ======================================================
int main(void) {
    const char *notify_url = getenv("CHARTGEN_NOTIFY_URL");
    if (!notify_url || strlen(notify_url) == 0) {
        notify_url = DEFAULT_NOTIFY_URL;
    }
    const char *notify_url_alt = getenv("CHARTGEN_NOTIFY_URL_ALT");
    if (!notify_url_alt || strlen(notify_url_alt) == 0) {
        notify_url_alt = DEFAULT_NOTIFY_URL_ALT;
    }

    while (1) {
        generate_charts_once();

        // Notify dashboard (SSE)
        const char *urls[2] = {notify_url, notify_url_alt};
        for (int i = 0; i < 2; i++) {
            if (!urls[i] || strlen(urls[i]) == 0) continue;
            char cmd[512];
            snprintf(cmd, sizeof(cmd), "curl -sS %s >/dev/null 2>&1", urls[i]);
            int rc = system(cmd);
            if (rc != 0) {
                fprintf(stderr, "Warning: SSE notify fail rc=%d url=%s\n", rc, urls[i]);
            }
        }

        usleep(200 * 1000);  // 200 ms
    }

    return 0;
}
