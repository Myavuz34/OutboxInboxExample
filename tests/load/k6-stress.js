// =============================================================================
// Stress Testi - Kirilma Noktasi Bulma
// =============================================================================
// Amac: Sistemi progresif zorlayip kirilma noktasini bul
// Akis: 10 -> 50 -> 100 -> 200 -> 300 -> 0 RPS
// DB pool: 25 conn -> ~25 esanli istekte doyma bekleniyor
// =============================================================================

import { createOrder } from './helpers/common.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

export const options = {
    scenarios: {
        stress: {
            executor: 'ramping-arrival-rate',
            startRate: 10,
            timeUnit: '1s',
            preAllocatedVUs: 50,
            maxVUs: 200,
            stages: [
                { duration: '30s', target: 10 },   // baseline
                { duration: '1m', target: 50 },     // orta yuk
                { duration: '1m', target: 100 },    // agir yuk
                { duration: '1m', target: 200 },    // stres
                { duration: '30s', target: 300 },   // kirilma
                { duration: '1m', target: 0 },      // toparlanma
            ],
        },
    },
    thresholds: {
        http_req_duration: ['p(95)<2000'],
        http_req_failed: ['rate<0.10'],
    },
};

export default function () {
    createOrder();
}

export function handleSummary(data) {
    const lines = [];
    lines.push('');
    lines.push('╔══════════════════════════════════════════════════════╗');
    lines.push('║       STRESS TEST - k6 SONUCLARI                    ║');
    lines.push('╠══════════════════════════════════════════════════════╣');

    const reqs = data.metrics.http_reqs;
    const dur = data.metrics.http_req_duration;
    const failed = data.metrics.http_req_failed;
    const created = data.metrics.orders_created;

    if (reqs) {
        lines.push(`║  Toplam HTTP istek:  ${String(Math.round(reqs.values.count)).padStart(8)}                    ║`);
        lines.push(`║  Ortalama RPS:       ${String(reqs.values.rate.toFixed(1)).padStart(8)}                    ║`);
    }
    if (created) {
        lines.push(`║  Basarili siparis:   ${String(Math.round(created.values.count)).padStart(8)}                    ║`);
    }
    if (failed) {
        const pct = (failed.values.rate * 100).toFixed(2);
        lines.push(`║  Hata orani:         ${String(pct + '%').padStart(8)}                    ║`);
    }

    lines.push('╠══════════════════════════════════════════════════════╣');
    lines.push('║  LATENCY                                            ║');

    if (dur && dur.values) {
        const v = dur.values;
        const fmt = (val) => val !== undefined && val !== null ? val.toFixed(1) + 'ms' : 'N/A';
        lines.push(`║    p50:              ${String(fmt(v['p(50)'])).padStart(8)}                    ║`);
        lines.push(`║    p95:              ${String(fmt(v['p(95)'])).padStart(8)}                    ║`);
        lines.push(`║    p99:              ${String(fmt(v['p(99)'])).padStart(8)}                    ║`);
        lines.push(`║    max:              ${String(fmt(v.max)).padStart(8)}                    ║`);
        lines.push(`║    avg:              ${String(fmt(v.avg)).padStart(8)}                    ║`);
    }

    lines.push('╠══════════════════════════════════════════════════════╣');
    lines.push('║  STRESS ANALIZI                                     ║');
    if (dur) {
        const avgMs = dur.values.avg.toFixed(1);
        const p99Ms = dur.values['p(99)'].toFixed(1);
        if (parseFloat(p99Ms) > 1000) {
            lines.push('║    DB pool doyma:    EVET (p99 > 1000ms)            ║');
        } else {
            lines.push('║    DB pool doyma:    HAYIR                          ║');
        }
        if (failed && failed.values.rate > 0.01) {
            lines.push('║    Kirilma noktasi:  GORULDU (error > %1)           ║');
        } else {
            lines.push('║    Kirilma noktasi:  GORULMEDI                      ║');
        }
    }

    lines.push('╚══════════════════════════════════════════════════════╝');
    lines.push('');

    return {
        stdout: lines.join('\n') + '\n' + textSummary(data, { indent: '  ', enableColors: true }),
    };
}
