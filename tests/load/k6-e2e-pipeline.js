// =============================================================================
// E2E Pipeline Performans Testi
// =============================================================================
// Amac: Order -> Outbox -> RabbitMQ -> Inbox -> Stok dusumu pipeline throughput
// Enjeksiyon: 20 RPS x 2 dakika (~2400 siparis)
// Outbox relayer teorik limiti: ~20 msg/s (5s poll, 100 batch)
// =============================================================================

import { createOrder } from './helpers/common.js';
import { textSummary } from 'https://jslib.k6.io/k6-summary/0.1.0/index.js';

export const options = {
    scenarios: {
        pipeline_test: {
            executor: 'constant-arrival-rate',
            rate: 20,
            timeUnit: '1s',
            duration: '2m',
            preAllocatedVUs: 10,
            maxVUs: 30,
        },
    },
    thresholds: {
        http_req_duration: ['p(50)<200', 'p(95)<500', 'p(99)<1000'],
        http_req_failed: ['rate<0.01'],
        orders_created: ['count>2000'],
    },
};

export default function () {
    createOrder();
}

export function handleSummary(data) {
    const lines = [];
    lines.push('');
    lines.push('╔══════════════════════════════════════════════════════╗');
    lines.push('║       E2E PIPELINE - k6 SONUCLARI                   ║');
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

    lines.push('╚══════════════════════════════════════════════════════╝');
    lines.push('');

    return {
        stdout: lines.join('\n') + '\n' + textSummary(data, { indent: '  ', enableColors: true }),
    };
}
